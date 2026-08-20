import Foundation
import XCTest
@testable import AstraCore

final class FocusSessionEngineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testStartingSessionCapturesImmutablePresetSnapshotAndEndTime() throws {
        var preset = makePreset(difficulty: .flexible, duration: 25 * 60)
        var engine = FocusSessionEngine()

        let session = try engine.startSession(preset: preset, at: start)
        preset.name = "Changed later"

        XCTAssertEqual(session.preset.name, "Deep Work")
        XCTAssertEqual(session.difficulty, .flexible)
        XCTAssertEqual(session.endDate, start.addingTimeInterval(25 * 60))
        XCTAssertEqual(session.status, .active)
    }

    func testCannotReplaceActiveSessionOrUseOutOfRangeDuration() throws {
        var engine = FocusSessionEngine()
        let preset = makePreset(difficulty: .flexible)
        _ = try engine.startSession(preset: preset, at: start)

        XCTAssertThrowsError(try engine.startSession(preset: preset, at: start)) { error in
            XCTAssertEqual(error as? FocusSessionEngineError, .sessionAlreadyActive)
        }

        var freshEngine = FocusSessionEngine()
        XCTAssertThrowsError(
            try freshEngine.startSession(preset: preset, durationSeconds: 299, at: start)
        ) { error in
            XCTAssertEqual(error as? FocusSessionEngineError, .invalidDuration)
        }
    }

    func testFlexibleInterruptionAlwaysWaitsSixSeconds() throws {
        var engine = FocusSessionEngine()
        _ = try engine.startSession(preset: makePreset(difficulty: .flexible), at: start)

        let first = try engine.requestInterruption(.endSession, at: start)
        XCTAssertEqual(first.waitDuration, 6)
        _ = try engine.cancelInterruption(challengeID: first.id, at: start)

        let second = try engine.requestInterruption(.takeBreak, breakDurationMinutes: 5, at: start)
        XCTAssertEqual(second.waitDuration, 6)
        XCTAssertEqual(engine.session?.interruptionRequestCount, 2)
    }

    func testCommitmentWaitEscalatesAndCapsAtFourMinutes() throws {
        var engine = FocusSessionEngine()
        _ = try engine.startSession(preset: makePreset(difficulty: .commitment), at: start)

        var waits: [TimeInterval] = []
        for attempt in 0 ..< 6 {
            let requestedAt = start.addingTimeInterval(TimeInterval(attempt))
            let challenge = try engine.requestInterruption(.endSession, at: requestedAt)
            waits.append(challenge.waitDuration)
            _ = try engine.cancelInterruption(challengeID: challenge.id, at: requestedAt)
        }

        XCTAssertEqual(waits, [30, 60, 120, 240, 240, 240])
    }

    func testChallengeCannotBeBypassedByCommittingEarlyOrUsingWrongID() throws {
        var engine = FocusSessionEngine()
        _ = try engine.startSession(preset: makePreset(difficulty: .flexible), at: start)
        let challenge = try engine.requestInterruption(.endSession, at: start)

        XCTAssertThrowsError(
            try engine.commitInterruption(challengeID: UUID(), at: challenge.availableAt)
        ) { error in
            XCTAssertEqual(error as? FocusSessionEngineError, .challengeNotFound)
        }
        XCTAssertThrowsError(
            try engine.commitInterruption(
                challengeID: challenge.id,
                at: challenge.availableAt.addingTimeInterval(-0.001)
            )
        ) { error in
            XCTAssertEqual(
                error as? FocusSessionEngineError,
                .challengeNotReady(availableAt: challenge.availableAt)
            )
        }

        let result = try engine.commitInterruption(
            challengeID: challenge.id,
            at: challenge.availableAt
        )
        XCTAssertEqual(result.status, .endedEarly)
        XCTAssertNil(result.pendingInterruption)
    }

    func testLockedSessionRejectsAllInterruptionRequests() throws {
        var engine = FocusSessionEngine()
        _ = try engine.startSession(preset: makePreset(difficulty: .locked), at: start)

        XCTAssertThrowsError(try engine.requestInterruption(.endSession, at: start)) { error in
            XCTAssertEqual(error as? FocusSessionEngineError, .interruptionNotAllowed)
        }
        XCTAssertThrowsError(
            try engine.requestInterruption(.takeBreak, breakDurationMinutes: 5, at: start)
        ) { error in
            XCTAssertEqual(error as? FocusSessionEngineError, .interruptionNotAllowed)
        }
    }

    func testBreakDurationMustBeWholeMinutesWithinRange() throws {
        var engine = FocusSessionEngine()
        _ = try engine.startSession(preset: makePreset(difficulty: .flexible), at: start)

        for invalidDuration in [0, 16] {
            XCTAssertThrowsError(
                try engine.requestInterruption(
                    .takeBreak,
                    breakDurationMinutes: invalidDuration,
                    at: start
                )
            ) { error in
                XCTAssertEqual(error as? FocusSessionEngineError, .invalidBreakDuration)
            }
        }
        XCTAssertThrowsError(
            try engine.requestInterruption(.endSession, breakDurationMinutes: 1, at: start)
        ) { error in
            XCTAssertEqual(error as? FocusSessionEngineError, .unexpectedBreakDuration)
        }
    }

    func testBreakNeverExtendsOriginalSessionEnd() throws {
        var engine = FocusSessionEngine()
        _ = try engine.startSession(
            preset: makePreset(difficulty: .flexible, duration: 5 * 60),
            at: start
        )
        let requestTime = start.addingTimeInterval(4 * 60)
        let challenge = try engine.requestInterruption(
            .takeBreak,
            breakDurationMinutes: 15,
            at: requestTime
        )
        let result = try engine.commitInterruption(
            challengeID: challenge.id,
            at: challenge.availableAt
        )

        XCTAssertEqual(result.status, .onBreak)
        XCTAssertEqual(result.breakCount, 1)
        XCTAssertEqual(result.activeBreak?.endsAt, result.endDate)
        XCTAssertEqual(result.endDate, start.addingTimeInterval(5 * 60))

        let completed = try XCTUnwrap(engine.refresh(at: result.endDate))
        XCTAssertEqual(completed.status, .completed)
        XCTAssertNil(completed.activeBreak)
    }

    func testRefreshReturnsToActiveWhenBreakEndsBeforeSession() throws {
        var engine = FocusSessionEngine()
        _ = try engine.startSession(preset: makePreset(difficulty: .flexible), at: start)
        let challenge = try engine.requestInterruption(
            .takeBreak,
            breakDurationMinutes: 1,
            at: start
        )
        let onBreak = try engine.commitInterruption(
            challengeID: challenge.id,
            at: challenge.availableAt
        )
        let resumed = try XCTUnwrap(engine.refresh(at: try XCTUnwrap(onBreak.activeBreak?.endsAt)))

        XCTAssertEqual(resumed.status, .active)
        XCTAssertNil(resumed.activeBreak)
        XCTAssertEqual(resumed.breakCount, 1)
    }

    func testExpiredSessionClearsPendingChallenge() throws {
        var engine = FocusSessionEngine()
        _ = try engine.startSession(
            preset: makePreset(difficulty: .commitment, duration: 5 * 60),
            at: start
        )
        _ = try engine.requestInterruption(
            .endSession,
            at: start.addingTimeInterval(4 * 60 + 50)
        )

        let completed = try XCTUnwrap(engine.refresh(at: start.addingTimeInterval(5 * 60)))
        XCTAssertEqual(completed.status, .completed)
        XCTAssertNil(completed.pendingInterruption)
    }

    func testInterruptionStateSurvivesCodableRoundTrip() throws {
        var engine = FocusSessionEngine()
        _ = try engine.startSession(preset: makePreset(difficulty: .commitment), at: start)
        _ = try engine.requestInterruption(.takeBreak, breakDurationMinutes: 3, at: start)
        let original = try XCTUnwrap(engine.session)

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(FocusSession.self, from: data)

        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.pendingInterruption?.waitDuration, 30)
        XCTAssertEqual(restored.interruptionRequestCount, 1)
    }

    func testRestoringSessionValidatesPersistentStateAndRefreshesExpiration() throws {
        let preset = makePreset(difficulty: .commitment, duration: 5 * 60)
        let endedAt = start.addingTimeInterval(5 * 60)
        let persisted = FocusSession(
            preset: preset,
            startDate: start,
            endDate: endedAt,
            difficulty: .commitment
        )

        let engine = try FocusSessionEngine(restoring: persisted, at: endedAt)
        XCTAssertEqual(engine.session?.status, .completed)

        let malformed = FocusSession(
            preset: preset,
            startDate: start,
            endDate: endedAt,
            difficulty: .commitment,
            status: .onBreak,
            activeBreak: nil
        )
        XCTAssertThrowsError(try FocusSessionEngine(restoring: malformed, at: start)) { error in
            XCTAssertEqual(error as? FocusSessionValidationError, .inconsistentBreakState)
        }
    }

    func testRestoringSessionRejectsDurationOutsideSupportedRange() {
        let preset = makePreset(difficulty: .commitment, duration: 5 * 60)
        for duration in [5 * 60 - 1, 24 * 60 * 60 + 1] {
            let malformed = FocusSession(
                preset: preset,
                startDate: start,
                endDate: start.addingTimeInterval(TimeInterval(duration)),
                difficulty: .commitment
            )

            XCTAssertThrowsError(try FocusSessionEngine(restoring: malformed, at: start)) { error in
                XCTAssertEqual(error as? FocusSessionValidationError, .invalidDuration)
            }
        }
    }

    private func makePreset(difficulty: Difficulty, duration: Int = 60 * 60) -> FocusPreset {
        FocusPreset(
            name: "Deep Work",
            blockedApplications: [
                BlockedApplication(bundleIdentifier: "com.example.Distraction", displayName: "Distraction")
            ],
            defaultDurationSeconds: duration,
            difficulty: difficulty,
            createdAt: start,
            updatedAt: start
        )
    }
}
