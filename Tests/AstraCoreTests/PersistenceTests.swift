import Foundation
import XCTest
@testable import AstraCore

final class PersistenceTests: XCTestCase {
    func testStoreRoundTripsVersionedPresetCollection() async throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("nested/presets.json")
        let store = try FocusPresetStore(fileURL: fileURL)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let presets = [
            FocusPreset(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Writing",
                domainRules: [try DomainRule("news.example")],
                defaultDurationSeconds: 25 * 60,
                difficulty: .commitment,
                createdAt: date,
                updatedAt: date
            )
        ]

        let saved = try await store.save(presets, at: date)
        let loaded = try await store.load()

        XCTAssertEqual(saved.schemaVersion, 1)
        XCTAssertEqual(loaded, saved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testMissingFileLoadsAsNilAndDeleteIsIdempotent() async throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try FocusSessionStore(fileURL: directory.appendingPathComponent("session.json"))

        let initial = try await store.load()
        XCTAssertNil(initial)
        try await store.delete()
        try await store.delete()
    }

    func testStoreRejectsUnsupportedSchemaVersion() async throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("presets.json")
        let writer = try FocusPresetStore(fileURL: fileURL, schemaVersion: 1)
        _ = try await writer.save([], at: Date(timeIntervalSince1970: 1_700_000_000))
        let newerReader = try FocusPresetStore(fileURL: fileURL, schemaVersion: 2)

        do {
            _ = try await newerReader.load()
            XCTFail("Expected the schema mismatch to be rejected")
        } catch {
            XCTAssertEqual(
                error as? PersistenceError,
                .unsupportedSchemaVersion(found: 1, supported: 2)
            )
        }
    }

    func testStoreRejectsInvalidConfiguredSchemaVersion() {
        XCTAssertThrowsError(
            try FocusPresetStore(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("invalid.json"),
                schemaVersion: 0
            )
        ) { error in
            XCTAssertEqual(error as? PersistenceError, .invalidSchemaVersion(0))
        }
    }

    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AstraCoreTests-\(UUID().uuidString)", isDirectory: true)
    }
}
