import Foundation
import ServiceManagement

@MainActor
private final class FakeLoginService: HUDLoginRegistering {
    enum Failure: Error { case test }
    var status: SMAppService.Status = .notRegistered
    var registeredStatus: SMAppService.Status = .enabled
    var registrations = 0
    var removals = 0
    var registrationError = false
    var removalError = false
    func register() throws {
        registrations += 1
        status = registeredStatus
        if registrationError { throw Failure.test }
    }
    func unregister() async throws {
        removals += 1
        if removalError { throw Failure.test }
        status = .notRegistered
    }
}

@main struct LoginItemTests {
    @MainActor static func main() async throws {
        let service = FakeLoginService()
        let login = HUDLoginItem(service: service)
        precondition(login.status == .notRegistered && service.registrations == 0,
                     "Fresh settings must not automatically register a login item")
        try await login.setEnabled(false)
        precondition(service.removals == 0, "Off is already the default")
        var changing: [Bool] = []
        login.onChange = { changing.append(login.isChanging) }
        try await login.setEnabled(true)
        precondition(login.status == .enabled && service.registrations == 1)
        precondition(changing == [true, false], "Menu must be disabled until registration finishes")
        try await login.setEnabled(true)
        precondition(service.registrations == 1, "Selecting On again must not re-register")
        service.removalError = true
        do { try await login.setEnabled(false); preconditionFailure("Expected unregister error") }
        catch { precondition(login.status == .enabled && !login.isChanging, "Failed removal must not show Off") }
        service.removalError = false
        try await login.setEnabled(false)
        precondition(login.status == .notRegistered && service.removals == 2)
        service.registeredStatus = .requiresApproval
        service.registrationError = true
        try await login.setEnabled(true)
        precondition(login.status == .requiresApproval, "Approval is distinct from enabled")
        let attempts = service.registrations
        try await login.setEnabled(true)
        precondition(service.registrations == attempts, "Waiting for approval must not override the user's choice")
        try await login.setEnabled(false)
        precondition(login.status == .notRegistered, "Off must also remove a pending login item")
        service.status = .enabled
        precondition(login.status == .enabled, "Changes from System Settings must be reflected")
        service.status = .requiresApproval
        precondition(login.status == .requiresApproval && service.registrations == attempts,
                     "Revoked approval must not cause automatic re-registration")
        service.status = .notFound
        service.registeredStatus = .notFound
        do { try await login.setEnabled(true); preconditionFailure("Expected registration error") }
        catch { precondition(login.status == .notFound && !login.isChanging) }
        print("PASS: login starts Off; On/Off registration, pending approval, external changes and failures stay accurate. No real login item changed.")
    }
}
