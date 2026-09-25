import Foundation

final class Client: NSObject, PowerHelperProtocol {
    let id = UUID()
    let sampler: PowerSampler
    init(sampler: PowerSampler) { self.sampler = sampler }
    func sample(reply: @escaping (NSDictionary) -> Void) { sampler.sample(client: id, reply: reply) }
    func stop(reply: @escaping () -> Void) { sampler.stop(client: id, reply: reply) }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let sampler = PowerSampler()
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let requirement = PowerHelperIdentity.requirement(for: PowerHelperIdentity.app) else { return false }
        connection.setCodeSigningRequirement(requirement)
        let client = Client(sampler: sampler)
        connection.exportedInterface = NSXPCInterface(with: PowerHelperProtocol.self)
        connection.exportedObject = client
        connection.invalidationHandler = { [sampler, id = client.id] in sampler.stop(client: id) }
        connection.interruptionHandler = { [sampler, id = client.id] in sampler.stop(client: id) }
        connection.resume()
        return true
    }
}
let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: PowerHelperIdentity.service)
listener.delegate = delegate
listener.resume()
withExtendedLifetime(delegate) { dispatchMain() }
