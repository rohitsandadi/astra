import Foundation

public struct VersionedDocument<Value: Codable & Sendable>: Codable, Sendable {
    public let schemaVersion: Int
    public let savedAt: Date
    public let value: Value

    public init(schemaVersion: Int, savedAt: Date = Date(), value: Value) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.value = value
    }
}

extension VersionedDocument: Equatable where Value: Equatable {}

public enum PersistenceError: Error, Equatable, Sendable {
    case invalidSchemaVersion(Int)
    case unsupportedSchemaVersion(found: Int, supported: Int)
}

public actor AtomicJSONFileStore<Value: Codable & Sendable> {
    public let fileURL: URL
    public let schemaVersion: Int

    public init(fileURL: URL, schemaVersion: Int = 1) throws {
        guard schemaVersion > 0 else {
            throw PersistenceError.invalidSchemaVersion(schemaVersion)
        }
        self.fileURL = fileURL
        self.schemaVersion = schemaVersion
    }

    public func load() throws -> VersionedDocument<Value>? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(VersionedDocument<Value>.self, from: data)
        guard document.schemaVersion == schemaVersion else {
            throw PersistenceError.unsupportedSchemaVersion(
                found: document.schemaVersion,
                supported: schemaVersion
            )
        }
        return document
    }

    @discardableResult
    public func save(_ value: Value, at date: Date = Date()) throws -> VersionedDocument<Value> {
        let document = VersionedDocument(
            schemaVersion: schemaVersion,
            savedAt: date,
            value: value
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        return document
    }

    public func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

public typealias FocusPresetStore = AtomicJSONFileStore<[FocusPreset]>
public typealias FocusSessionStore = AtomicJSONFileStore<FocusSession>
