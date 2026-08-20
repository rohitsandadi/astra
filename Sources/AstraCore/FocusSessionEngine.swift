import Foundation

public enum FocusSessionEngineError: Error, Equatable, Sendable {
    case sessionAlreadyActive
    case noActiveSession
    case invalidDuration
    case interruptionNotAllowed
    case breakAlreadyActive
    case invalidBreakDuration
    case unexpectedBreakDuration
    case challengeAlreadyPending
    case challengeNotFound
    case challengeNotReady(availableAt: Date)
}

public struct FocusSessionEngine: Sendable {
    public static let allowedSessionDurationSeconds = 5 * 60 ... 24 * 60 * 60
    public static let allowedBreakDurationMinutes = 1 ... 15

    public private(set) var session: FocusSession?

    public init(session: FocusSession? = nil) {
        self.session = session
    }

    public init(restoring session: FocusSession, at date: Date = Date()) throws {
        try session.validate()
        self.session = session
        _ = refresh(at: date)
    }

    @discardableResult
    public mutating func startSession(
        preset: FocusPreset,
        durationSeconds: Int? = nil,
        intention: String? = nil,
        at startDate: Date = Date(),
        enforcementHealth: EnforcementHealth = EnforcementHealth()
    ) throws -> FocusSession {
        if let session, !session.status.isTerminal {
            throw FocusSessionEngineError.sessionAlreadyActive
        }
        try preset.validate()

        let duration = durationSeconds ?? preset.defaultDurationSeconds
        guard Self.allowedSessionDurationSeconds.contains(duration) else {
            throw FocusSessionEngineError.invalidDuration
        }

        let newSession = FocusSession(
            preset: preset,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(TimeInterval(duration)),
            difficulty: preset.difficulty,
            intention: intention,
            enforcementHealth: enforcementHealth
        )
        session = newSession
        return newSession
    }

    @discardableResult
    public mutating func refresh(at date: Date = Date()) -> FocusSession? {
        guard var current = session, !current.status.isTerminal else { return session }

        if date >= current.endDate {
            current.status = .completed
            current.activeBreak = nil
            current.pendingInterruption = nil
        } else if current.status == .onBreak,
                  let activeBreak = current.activeBreak,
                  date >= activeBreak.endsAt {
            current.status = .active
            current.activeBreak = nil
        }

        session = current
        return current
    }

    @discardableResult
    public mutating func requestInterruption(
        _ kind: InterruptionKind,
        breakDurationMinutes: Int? = nil,
        at date: Date = Date()
    ) throws -> InterruptionChallenge {
        _ = refresh(at: date)
        guard var current = session, !current.status.isTerminal else {
            throw FocusSessionEngineError.noActiveSession
        }
        guard current.difficulty != .locked else {
            throw FocusSessionEngineError.interruptionNotAllowed
        }
        guard current.pendingInterruption == nil else {
            throw FocusSessionEngineError.challengeAlreadyPending
        }

        switch kind {
        case .takeBreak:
            guard current.status != .onBreak else {
                throw FocusSessionEngineError.breakAlreadyActive
            }
            guard let breakDurationMinutes,
                  Self.allowedBreakDurationMinutes.contains(breakDurationMinutes)
            else {
                throw FocusSessionEngineError.invalidBreakDuration
            }
        case .endSession:
            guard breakDurationMinutes == nil else {
                throw FocusSessionEngineError.unexpectedBreakDuration
            }
        }

        let wait = Self.interruptionWaitDuration(
            for: current.difficulty,
            priorRequestCount: current.interruptionRequestCount
        )
        let challenge = InterruptionChallenge(
            kind: kind,
            requestedAt: date,
            availableAt: date.addingTimeInterval(wait),
            breakDurationMinutes: breakDurationMinutes
        )
        current.interruptionRequestCount += 1
        current.pendingInterruption = challenge
        session = current
        return challenge
    }

    @discardableResult
    public mutating func cancelInterruption(
        challengeID: UUID,
        at date: Date = Date()
    ) throws -> FocusSession {
        _ = refresh(at: date)
        guard var current = session, !current.status.isTerminal else {
            throw FocusSessionEngineError.noActiveSession
        }
        guard current.pendingInterruption?.id == challengeID else {
            throw FocusSessionEngineError.challengeNotFound
        }
        current.pendingInterruption = nil
        session = current
        return current
    }

    @discardableResult
    public mutating func commitInterruption(
        challengeID: UUID,
        at date: Date = Date()
    ) throws -> FocusSession {
        _ = refresh(at: date)
        guard var current = session, !current.status.isTerminal else {
            throw FocusSessionEngineError.noActiveSession
        }
        guard let challenge = current.pendingInterruption,
              challenge.id == challengeID
        else {
            throw FocusSessionEngineError.challengeNotFound
        }
        guard date >= challenge.availableAt else {
            throw FocusSessionEngineError.challengeNotReady(availableAt: challenge.availableAt)
        }

        current.pendingInterruption = nil
        switch challenge.kind {
        case .endSession:
            current.status = .endedEarly
            current.activeBreak = nil
        case .takeBreak:
            guard let breakMinutes = challenge.breakDurationMinutes else {
                throw FocusSessionEngineError.invalidBreakDuration
            }
            let requestedEnd = date.addingTimeInterval(TimeInterval(breakMinutes * 60))
            let breakEnd = min(requestedEnd, current.endDate)
            current.status = .onBreak
            current.breakCount += 1
            current.activeBreak = FocusBreak(
                startedAt: date,
                endsAt: breakEnd,
                requestedDurationMinutes: breakMinutes
            )
        }

        session = current
        return current
    }

    public mutating func updateEnforcementHealth(_ health: EnforcementHealth) throws {
        guard var current = session, !current.status.isTerminal else {
            throw FocusSessionEngineError.noActiveSession
        }
        current.enforcementHealth = health
        session = current
    }

    static func interruptionWaitDuration(
        for difficulty: Difficulty,
        priorRequestCount: Int
    ) -> TimeInterval {
        switch difficulty {
        case .flexible:
            return 6
        case .commitment:
            let waits: [TimeInterval] = [30, 60, 120, 240]
            return waits[min(max(priorRequestCount, 0), waits.count - 1)]
        case .locked:
            // Locked requests are rejected before reaching this method.
            return 0
        }
    }
}
