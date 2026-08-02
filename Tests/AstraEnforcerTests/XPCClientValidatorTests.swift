import XCTest
@testable import AstraEnforcer

final class XPCClientValidatorTests: XCTestCase {
    func testFindsSiblingMainExecutableInsideAppBundle() {
        let helper = URL(fileURLWithPath: "/Applications/Astra.app/Contents/MacOS/AstraEnforcer")
        XCTAssertEqual(
            AstraXPCClientValidator.expectedMainExecutable(forHelperAt: helper)?.path,
            "/Applications/Astra.app/Contents/MacOS/Astra"
        )
    }

    func testRejectsUnexpectedHelperLayout() {
        let helper = URL(fileURLWithPath: "/tmp/AstraEnforcer")
        XCTAssertNil(AstraXPCClientValidator.expectedMainExecutable(forHelperAt: helper))
    }
}
