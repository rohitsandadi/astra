import Foundation

#if os(macOS)
/// The intentionally narrow Objective-C surface shared by the UI and helper.
/// Every argument is JSON-encoded `Data`; no arbitrary object graphs cross XPC.
@objc(AstraEnforcerXPCProtocol) public protocol AstraEnforcerXPCProtocol {
    func startSession(_ request: Data, withReply reply: @escaping (Data) -> Void)
    func currentSnapshot(withReply reply: @escaping (Data) -> Void)
    func requestInterruption(_ request: Data, withReply reply: @escaping (Data) -> Void)
    func cancelInterruption(_ request: Data, withReply reply: @escaping (Data) -> Void)
    func commitInterruption(_ request: Data, withReply reply: @escaping (Data) -> Void)
    func permissionHealth(withReply reply: @escaping (Data) -> Void)
    func requestBrowserPermission(_ request: Data, withReply reply: @escaping (Data) -> Void)
}
#endif

public struct AstraStartSessionRequest: Codable, Equatable, Sendable {
    public let preset: FocusPreset
    public let durationSeconds: Int?
    public let intention: String?

    public init(preset: FocusPreset, durationSeconds: Int? = nil, intention: String? = nil) {
        self.preset = preset
        self.durationSeconds = durationSeconds
        self.intention = intention
    }
}

public struct AstraInterruptionRequest: Codable, Equatable, Sendable {
    public let kind: InterruptionKind
    public let breakDurationMinutes: Int?

    public init(kind: InterruptionKind, breakDurationMinutes: Int? = nil) {
        self.kind = kind
        self.breakDurationMinutes = breakDurationMinutes
    }
}

public struct AstraCommitInterruptionRequest: Codable, Equatable, Sendable {
    public let challengeID: UUID

    public init(challengeID: UUID) {
        self.challengeID = challengeID
    }
}

public struct AstraCancelInterruptionRequest: Codable, Equatable, Sendable {
    public let challengeID: UUID

    public init(challengeID: UUID) {
        self.challengeID = challengeID
    }
}

public struct AstraBrowserPermissionRequest: Codable, Equatable, Sendable {
    public let browser: SupportedBrowser

    public init(browser: SupportedBrowser) {
        self.browser = browser
    }
}

public struct AstraSessionSnapshot: Codable, Equatable, Sendable {
    public let session: FocusSession?
    public let enforcementHealth: EnforcementHealth

    public init(session: FocusSession?, enforcementHealth: EnforcementHealth) {
        self.session = session
        self.enforcementHealth = enforcementHealth
    }
}

public struct AstraInterruptionResponse: Codable, Equatable, Sendable {
    public let challenge: InterruptionChallenge
    public let snapshot: AstraSessionSnapshot

    public init(challenge: InterruptionChallenge, snapshot: AstraSessionSnapshot) {
        self.challenge = challenge
        self.snapshot = snapshot
    }
}

public enum AstraXPCErrorCode: String, Codable, CaseIterable, Sendable {
    case invalidRequest
    case invalidState
    case permissionDenied
    case internalFailure
}

public struct AstraXPCError: Error, Codable, Equatable, Sendable {
    public let code: AstraXPCErrorCode
    public let message: String

    public init(code: AstraXPCErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

public enum AstraXPCResponse<Payload: Codable & Sendable>: Codable, Sendable {
    case success(Payload)
    case failure(AstraXPCError)

    public var value: Payload? {
        guard case .success(let value) = self else { return nil }
        return value
    }

    public var error: AstraXPCError? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}

extension AstraXPCResponse: Equatable where Payload: Equatable {}

public enum AstraXPCJSONCodec {
    public static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    public static func decode<Value: Decodable>(
        _ type: Value.Type = Value.self,
        from data: Data
    ) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
