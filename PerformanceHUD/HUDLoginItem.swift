import ServiceManagement

@MainActor
protocol HUDLoginRegistering {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
}

@MainActor
private final class HUDSystemLoginService: HUDLoginRegistering {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() async throws { try await SMAppService.mainApp.unregister() }
}

/// macOS owns this setting; reading it never registers or re-enables the app.
@MainActor
final class HUDLoginItem {
    private let service: any HUDLoginRegistering
    private(set) var isChanging = false
    var onChange: (() -> Void)?

    init(service: (any HUDLoginRegistering)? = nil) {
        self.service = service ?? HUDSystemLoginService()
    }

    var status: SMAppService.Status { service.status }

    func setEnabled(_ enabled: Bool) async throws {
        guard !isChanging else { return }
        isChanging = true
        onChange?()
        defer { isChanging = false; onChange?() }
        if enabled {
            guard status != .enabled, status != .requiresApproval else { return }
            do { try service.register() }
            catch { if status != .requiresApproval { throw error } }
        } else if status == .enabled || status == .requiresApproval {
            try await service.unregister()
        }
    }
}
