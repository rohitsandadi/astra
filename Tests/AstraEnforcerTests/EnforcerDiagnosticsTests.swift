import XCTest
@testable import AstraEnforcer

final class EnforcerDiagnosticsTests: XCTestCase {
    func testDiagnosticReportIsEncodableAndDoesNotInspectSessionContent() throws {
        let data = try EnforcerDiagnostics.encodedReport()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertNotNil(object["executablePath"] as? String)
        XCTAssertNotNil(object["browsers"] as? [[String: Any]])
        XCTAssertNil(object["session"])
        XCTAssertNil(object["intention"])
        XCTAssertNil(object["domains"])
    }
}
