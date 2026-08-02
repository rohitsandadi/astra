import AstraCore
import Foundation

enum SessionPersistenceError: Error, Equatable {
    case unsupportedVersion(Int)
}

protocol SessionPersisting: Sendable {
    func load() throws -> FocusSession?
    func save(_ session: FocusSession) throws
    func clear() throws
}

/// A single-record, versioned store. Atomic replacement ensures a crash cannot
/// leave the helper with a partially written active session.
final class JSONSessionStore: SessionPersisting, @unchecked Sendable {
    private struct Envelope: Codable {
        let version: Int
        let session: FocusSession
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = base
                .appendingPathComponent("Astra", isDirectory: true)
                .appendingPathComponent("active-session.json", isDirectory: false)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load() throws -> FocusSession? {
        try lock.withLock {
            guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
            let envelope = try decoder.decode(Envelope.self, from: Data(contentsOf: fileURL))
            guard envelope.version == 1 else {
                throw SessionPersistenceError.unsupportedVersion(envelope.version)
            }
            return envelope.session
        }
    }

    func save(_ session: FocusSession) throws {
        try lock.withLock {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(Envelope(version: 1, session: session))
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        }
    }

    func clear() throws {
        try lock.withLock {
            guard fileManager.fileExists(atPath: fileURL.path) else { return }
            try fileManager.removeItem(at: fileURL)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
