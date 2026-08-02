import XCTest
@testable import Astra

final class AstraUpdateCheckerTests: XCTestCase {
    func testRecognizesNewerSemanticVersion() {
        XCTAssertTrue(AstraUpdateChecker.isNewer("v0.2.0", than: "0.1.9"))
        XCTAssertTrue(AstraUpdateChecker.isNewer("1.0.1", than: "1.0"))
    }

    func testRejectsSameOrOlderVersion() {
        XCTAssertFalse(AstraUpdateChecker.isNewer("v1.2.3", than: "1.2.3"))
        XCTAssertFalse(AstraUpdateChecker.isNewer("1.1.9", than: "1.2.0"))
    }

    func testIgnoresPrereleaseSuffixForNumericComparison() {
        XCTAssertTrue(AstraUpdateChecker.isNewer("v2.0.0-beta.1", than: "1.9.9"))
    }
}
