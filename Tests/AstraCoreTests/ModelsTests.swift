import Foundation
import XCTest
@testable import AstraCore

final class ModelsTests: XCTestCase {
    func testPresetValidationEnforcesNameDurationAndSafeApplications() {
        let emptyName = FocusPreset(
            name: "  ",
            defaultDurationSeconds: 25 * 60,
            difficulty: .flexible
        )
        XCTAssertThrowsError(try emptyName.validate()) { error in
            XCTAssertEqual(error as? FocusPresetValidationError, .emptyName)
        }

        let shortDuration = FocusPreset(
            name: "Focus",
            defaultDurationSeconds: 4 * 60,
            difficulty: .flexible
        )
        XCTAssertThrowsError(try shortDuration.validate()) { error in
            XCTAssertEqual(error as? FocusPresetValidationError, .durationOutOfRange)
        }

        let finder = FocusPreset(
            name: "Focus",
            blockedApplications: [
                BlockedApplication(bundleIdentifier: "com.apple.finder", displayName: "Finder")
            ],
            defaultDurationSeconds: 25 * 60,
            difficulty: .locked
        )
        XCTAssertThrowsError(try finder.validate()) { error in
            XCTAssertEqual(error as? FocusPresetValidationError, .invalidApplication)
        }
    }

    func testPresetDecoderRejectsInvalidPersistentData() throws {
        let valid = FocusPreset(
            name: "Focus",
            defaultDurationSeconds: 25 * 60,
            difficulty: .flexible,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(valid)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var malformed = object
        malformed["defaultDurationSeconds"] = 1

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                FocusPreset.self,
                from: JSONSerialization.data(withJSONObject: malformed)
            )
        )
    }

    func testSupportedDurationBoundariesAreAccepted() throws {
        for duration in [5 * 60, 24 * 60 * 60] {
            let preset = FocusPreset(
                name: "Focus",
                defaultDurationSeconds: duration,
                difficulty: .commitment
            )
            XCTAssertNoThrow(try preset.validate())
        }
    }

    func testWindowManagerIsProtectedCaseInsensitively() {
        let application = BlockedApplication(
            bundleIdentifier: "com.apple.WindowManager",
            displayName: "WindowManager"
        )
        XCTAssertTrue(application.isProtectedSystemApplication)
    }
}
