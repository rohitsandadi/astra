import Foundation
import XCTest
@testable import AstraCore

final class XPCWireTests: XCTestCase {
    func testStartRequestRoundTripsThroughSharedCodec() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let request = AstraStartSessionRequest(
            preset: FocusPreset(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Research",
                blockedApplications: [
                    BlockedApplication(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
                ],
                domainRules: [try DomainRule("news.example")],
                defaultDurationSeconds: 45 * 60,
                difficulty: .commitment,
                createdAt: date,
                updatedAt: date
            ),
            durationSeconds: 60 * 60,
            intention: "Draft the proposal"
        )

        let data = try AstraXPCJSONCodec.encode(request)
        let decoded = try AstraXPCJSONCodec.decode(AstraStartSessionRequest.self, from: data)

        XCTAssertEqual(decoded, request)
    }

    func testTypedSuccessAndFailureResponsesRoundTrip() throws {
        let health = EnforcementHealth(appBlockingOperational: true)
        let snapshot = AstraSessionSnapshot(session: nil, enforcementHealth: health)
        let success = AstraXPCResponse<AstraSessionSnapshot>.success(snapshot)
        let decodedSuccess = try AstraXPCJSONCodec.decode(
            AstraXPCResponse<AstraSessionSnapshot>.self,
            from: AstraXPCJSONCodec.encode(success)
        )
        XCTAssertEqual(decodedSuccess, success)
        XCTAssertEqual(decodedSuccess.value, snapshot)
        XCTAssertNil(decodedSuccess.error)

        let failure = AstraXPCResponse<AstraSessionSnapshot>.failure(
            AstraXPCError(code: .invalidState, message: "No active session")
        )
        let decodedFailure = try AstraXPCJSONCodec.decode(
            AstraXPCResponse<AstraSessionSnapshot>.self,
            from: AstraXPCJSONCodec.encode(failure)
        )
        XCTAssertEqual(decodedFailure, failure)
        XCTAssertNil(decodedFailure.value)
        XCTAssertEqual(decodedFailure.error?.code, .invalidState)
    }

    func testInterruptionRequestsKeepDifficultyDecisionsOutOfClientPayload() throws {
        let request = AstraInterruptionRequest(kind: .takeBreak, breakDurationMinutes: 10)
        let data = try AstraXPCJSONCodec.encode(request)
        let decoded = try AstraXPCJSONCodec.decode(AstraInterruptionRequest.self, from: data)

        XCTAssertEqual(decoded, request)
    }

    func testCancelAndCommitPayloadsIdentifyOnlyServerIssuedChallenge() throws {
        let challengeID = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
        let cancel = AstraCancelInterruptionRequest(challengeID: challengeID)
        let commit = AstraCommitInterruptionRequest(challengeID: challengeID)

        XCTAssertEqual(
            try AstraXPCJSONCodec.decode(
                AstraCancelInterruptionRequest.self,
                from: AstraXPCJSONCodec.encode(cancel)
            ),
            cancel
        )
        XCTAssertEqual(
            try AstraXPCJSONCodec.decode(
                AstraCommitInterruptionRequest.self,
                from: AstraXPCJSONCodec.encode(commit)
            ),
            commit
        )
    }

    func testSupportedBrowserMetadataIsStableAcrossProcesses() {
        XCTAssertEqual(SupportedBrowser.safari.bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(SupportedBrowser.chrome.bundleIdentifier, "com.google.Chrome")
        XCTAssertEqual(SupportedBrowser.dia.bundleIdentifier, "company.thebrowser.dia")
        XCTAssertEqual(
            SupportedBrowser.browser(forBundleIdentifier: "company.thebrowser.dia"),
            .dia
        )
    }

    func testPermissionRequestRoundTripsSelectedBrowser() throws {
        let request = AstraBrowserPermissionRequest(browser: .dia)
        let decoded = try AstraXPCJSONCodec.decode(
            AstraBrowserPermissionRequest.self,
            from: AstraXPCJSONCodec.encode(request)
        )
        XCTAssertEqual(decoded, request)
    }
}
