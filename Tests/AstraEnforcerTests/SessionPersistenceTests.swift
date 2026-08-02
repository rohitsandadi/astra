import AstraCore
import Foundation
import XCTest
@testable import AstraEnforcer

final class SessionPersistenceTests: XCTestCase {
    func testRoundTripsSessionAndClearsIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("active.json")
        let store = JSONSessionStore(fileURL: fileURL)
        let preset = FocusPreset(
            name: "Test",
            blockedApplications: [BlockedApplication(bundleIdentifier: "com.example.app", displayName: "Example")],
            domainRules: [try DomainRule("https://www.Example.com/path")],
            defaultDurationSeconds: 1_000,
            difficulty: .flexible,
            createdAt: Date(timeIntervalSince1970: 500),
            updatedAt: Date(timeIntervalSince1970: 500)
        )
        let session = FocusSession(
            id: UUID(),
            preset: preset,
            startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 2_000),
            difficulty: .flexible,
            intention: "Write the draft"
        )

        try store.save(session)
        XCTAssertEqual(try store.load(), session)
        try store.clear()
        XCTAssertNil(try store.load())

        try? FileManager.default.removeItem(at: directory)
    }

    func testBlockPageEscapesIntentionAndContainsNoExternalResources() {
        let start = Date(timeIntervalSince1970: 1_000)
        let preset = FocusPreset(
            name: "Test",
            defaultDurationSeconds: 1_000,
            difficulty: .flexible,
            createdAt: start,
            updatedAt: start
        )
        let session = FocusSession(
            preset: preset,
            startDate: start,
            endDate: Date(timeIntervalSince1970: 2_000),
            difficulty: .flexible,
            intention: "Ship <Astra> & focus"
        )
        let html = BlockPageRenderer.render(session: session)

        XCTAssertTrue(html.contains("Ship &lt;Astra&gt; &amp; focus"))
        XCTAssertTrue(html.contains("default-src 'none'"))
        XCTAssertFalse(html.contains("https://"))
    }
}
