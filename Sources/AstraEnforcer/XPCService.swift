import AstraCore
import Foundation

final class AstraEnforcerXPCService: NSObject, AstraEnforcerXPCProtocol, @unchecked Sendable {
    private let coordinator: EnforcementCoordinator

    init(coordinator: EnforcementCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    func startSession(_ request: Data, withReply reply: @escaping (Data) -> Void) {
        perform(request, reply: reply) { (request: AstraStartSessionRequest) in
            try self.coordinator.start(request)
        }
    }

    func currentSnapshot(withReply reply: @escaping (Data) -> Void) {
        respond(reply, result: .success(coordinator.currentSnapshot()))
    }

    func requestInterruption(_ request: Data, withReply reply: @escaping (Data) -> Void) {
        perform(request, reply: reply) { (request: AstraInterruptionRequest) in
            try self.coordinator.requestInterruption(request)
        }
    }

    func commitInterruption(_ request: Data, withReply reply: @escaping (Data) -> Void) {
        perform(request, reply: reply) { (request: AstraCommitInterruptionRequest) in
            try self.coordinator.commitInterruption(request)
        }
    }

    func cancelInterruption(_ request: Data, withReply reply: @escaping (Data) -> Void) {
        perform(request, reply: reply) { (request: AstraCancelInterruptionRequest) in
            try self.coordinator.cancelInterruption(request)
        }
    }

    func permissionHealth(withReply reply: @escaping (Data) -> Void) {
        respond(reply, result: .success(coordinator.permissionHealth()))
    }

    func requestBrowserPermission(_ request: Data, withReply reply: @escaping (Data) -> Void) {
        perform(request, reply: reply) { (request: AstraBrowserPermissionRequest) in
            self.coordinator.requestBrowserPermission(request)
        }
    }

    private func perform<Request: Decodable, Payload: Codable & Sendable>(
        _ requestData: Data,
        reply: @escaping (Data) -> Void,
        operation: (Request) throws -> Payload
    ) {
        let request: Request
        do {
            request = try AstraXPCJSONCodec.decode(Request.self, from: requestData)
        } catch {
            respond(
                reply,
                result: AstraXPCResponse<Payload>.failure(
                    AstraXPCError(code: .invalidRequest, message: error.localizedDescription)
                )
            )
            return
        }

        do {
            respond(reply, result: .success(try operation(request)))
        } catch {
            respond(
                reply,
                result: AstraXPCResponse<Payload>.failure(
                    AstraXPCError(code: .invalidState, message: error.localizedDescription)
                )
            )
        }
    }

    private func respond<Payload: Codable & Sendable>(
        _ reply: @escaping (Data) -> Void,
        result: AstraXPCResponse<Payload>
    ) {
        do {
            reply(try AstraXPCJSONCodec.encode(result))
        } catch {
            reply(Data())
        }
    }
}

final class AstraEnforcerXPCListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: AstraEnforcerXPCService
    private let clientValidator: AstraXPCClientValidator

    init(
        service: AstraEnforcerXPCService,
        clientValidator: AstraXPCClientValidator = AstraXPCClientValidator()
    ) {
        self.service = service
        self.clientValidator = clientValidator
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard clientValidator.accepts(processIdentifier: connection.processIdentifier) else {
            EnforcerLog.xpc.error("Rejected XPC client pid \(connection.processIdentifier, privacy: .public)")
            return false
        }
        EnforcerLog.xpc.notice("Accepted Astra XPC client")
        connection.exportedInterface = NSXPCInterface(with: AstraEnforcerXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}
