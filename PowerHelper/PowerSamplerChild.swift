import Foundation
import Darwin
import MachO

// Internal exec trampoline, never exposed through XPC. Process starts its child
// in a separate group; rejoin the launchd job before exec so job teardown also
// kills powermetrics (including when the helper itself receives SIGKILL).
enum PowerSamplerChild {
    static let argument = "--power-sampler"
    static let executable = "/usr/bin/powermetrics"
    // Use the default continuous mode; the meaning of a zero count differs
    // between powermetrics versions.
    static let arguments = [executable, "--samplers", "cpu_power,gpu_power",
                            "--sample-rate", "1000",
                            "--format", "plist", "--buffer-size", "0"]

    // An auxiliary executable inside an .app must not use Bundle.main's
    // CFBundleExecutable, which may identify the GUI app rather than this helper.
    static var helperExecutableURL: URL? {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        guard size > 0 else { return nil }
        var path = [CChar](repeating: 0, count: Int(size))
        let result = path.withUnsafeMutableBufferPointer { _NSGetExecutablePath($0.baseAddress, &size) }
        guard result == 0 else { return nil }
        return URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath()
    }

    static func joinParentProcessGroup() -> Bool {
        let parent = getppid()
        guard parent > 1 else { return false }
        let group = getpgid(parent)
        guard group > 1, setpgid(0, group) == 0 else { return false }
        // If the parent died during setup, do not start an orphan sampler.
        return getppid() == parent
    }

    static func runIfRequested() {
        guard CommandLine.arguments.count == 2,
              CommandLine.arguments[1] == argument else { return }
        guard joinParentProcessGroup() else { _exit(EXIT_FAILURE) }
        let argv = arguments.map { strdup($0) } + [nil]
        guard argv.dropLast().allSatisfy({ $0 != nil }) else { _exit(EXIT_FAILURE) }
        argv.withUnsafeBufferPointer { buffer in
            _ = execv(executable, buffer.baseAddress!)
        }
        // exec only returns on failure. No listener or retry loop in child mode.
        _exit(EXIT_FAILURE)
    }
}
