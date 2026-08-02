import Foundation
import XCTest
@testable import AstraCore

final class DomainRuleTests: XCTestCase {
    func testNormalizationAcceptsCommonWebsiteInputs() throws {
        XCTAssertEqual(try DomainRule.normalize("example.com"), "example.com")
        XCTAssertEqual(
            try DomainRule.normalize(" HTTPS://WWW.Example.COM:443/articles?id=1 "),
            "example.com"
        )
        XCTAssertEqual(try DomainRule.normalize("sub.example.com/path"), "sub.example.com")
        XCTAssertEqual(try DomainRule.normalize("example.com."), "example.com")
    }

    func testNormalizationRejectsEmptyInvalidAndLoopbackHosts() {
        XCTAssertThrowsError(try DomainRule("   ")) { error in
            XCTAssertEqual(error as? DomainRuleError, .empty)
        }
        XCTAssertThrowsError(try DomainRule("not a host")) { error in
            XCTAssertEqual(error as? DomainRuleError, .invalidHost)
        }
        XCTAssertThrowsError(try DomainRule(".example.com")) { error in
            XCTAssertEqual(error as? DomainRuleError, .invalidHost)
        }
        XCTAssertThrowsError(try DomainRule("999.999.999.999")) { error in
            XCTAssertEqual(error as? DomainRuleError, .invalidHost)
        }
        XCTAssertThrowsError(try DomainRule("localhost:8080")) { error in
            XCTAssertEqual(error as? DomainRuleError, .loopbackHost)
        }
        XCTAssertThrowsError(try DomainRule("api.localhost")) { error in
            XCTAssertEqual(error as? DomainRuleError, .loopbackHost)
        }
        XCTAssertThrowsError(try DomainRule("127.44.2.9/path")) { error in
            XCTAssertEqual(error as? DomainRuleError, .loopbackHost)
        }
        XCTAssertThrowsError(try DomainRule("http://[::1]:8080")) { error in
            XCTAssertEqual(error as? DomainRuleError, .loopbackHost)
        }
    }

    func testRuleMatchesExactHostAndSubdomainsWithoutSubstringFalsePositives() throws {
        let rule = try DomainRule("www.example.com")

        XCTAssertTrue(rule.matches(host: "example.com"))
        XCTAssertTrue(rule.matches(host: "news.example.com"))
        XCTAssertTrue(rule.matches(host: "NEWS.EXAMPLE.COM."))
        XCTAssertFalse(rule.matches(host: "notexample.com"))
        XCTAssertFalse(rule.matches(host: "example.com.evil.test"))
        XCTAssertFalse(rule.matches(host: "localhost"))
    }

    func testExactRuleDoesNotMatchSubdomains() throws {
        let rule = try DomainRule("example.com", includeSubdomains: false)

        XCTAssertTrue(rule.matches(host: "www.example.com"))
        XCTAssertFalse(rule.matches(host: "mail.example.com"))
    }

    func testURLMatchingUsesOnlyHostname() throws {
        let rule = try DomainRule("social.example")

        XCTAssertTrue(rule.matches(url: try XCTUnwrap(URL(string: "https://app.social.example/feed"))))
        XCTAssertFalse(rule.matches(url: try XCTUnwrap(URL(string: "https://allowed.example/social.example"))))
    }

    func testDecodingRevalidatesPersistedHost() throws {
        let invalid = Data(#"{"host":"localhost","includeSubdomains":true}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(DomainRule.self, from: invalid))
    }
}
