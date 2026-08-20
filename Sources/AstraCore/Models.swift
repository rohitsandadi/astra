import Foundation

public enum Difficulty: String, Codable, CaseIterable, Sendable {
    case flexible
    case commitment
    case locked
}

public struct BlockedApplication: Identifiable, Codable, Hashable, Sendable {
    public static let protectedBundleIdentifiers: Set<String> = [
        "com.rohitsandadi.astra",
        "com.rohitsandadi.astra.enforcer",
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.windowmanager",
        "com.apple.systemuiserver"
    ]

    public var id: String { bundleIdentifier }
    public var isProtectedSystemApplication: Bool {
        Self.protectedBundleIdentifiers.contains(bundleIdentifier.lowercased())
    }

    public let bundleIdentifier: String
    public let displayName: String

    public init(bundleIdentifier: String, displayName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }
}

public enum FocusPresetValidationError: Error, Equatable, Sendable {
    case emptyName
    case durationOutOfRange
    case invalidChronology
    case invalidApplication
}

public struct FocusPreset: Identifiable, Codable, Hashable, Sendable {
    public static let allowedDurationSeconds = 5 * 60 ... 24 * 60 * 60

    public let id: UUID
    public var name: String
    public var blockedApplications: [BlockedApplication]
    public var domainRules: [DomainRule]
    public var defaultDurationSeconds: Int
    public var difficulty: Difficulty
    public let createdAt: Date
    public var updatedAt: Date

    public var defaultDuration: TimeInterval {
        TimeInterval(defaultDurationSeconds)
    }

    public init(
        id: UUID = UUID(),
        name: String,
        blockedApplications: [BlockedApplication] = [],
        domainRules: [DomainRule] = [],
        defaultDurationSeconds: Int,
        difficulty: Difficulty,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.blockedApplications = blockedApplications
        self.domainRules = domainRules
        self.defaultDurationSeconds = defaultDurationSeconds
        self.difficulty = difficulty
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FocusPresetValidationError.emptyName
        }
        guard Self.allowedDurationSeconds.contains(defaultDurationSeconds) else {
            throw FocusPresetValidationError.durationOutOfRange
        }
        guard updatedAt >= createdAt else {
            throw FocusPresetValidationError.invalidChronology
        }
        guard blockedApplications.allSatisfy({ application in
            !application.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !application.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !application.isProtectedSystemApplication
        }) else {
            throw FocusPresetValidationError.invalidApplication
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case blockedApplications
        case domainRules
        case defaultDurationSeconds
        case difficulty
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            blockedApplications: try container.decode(
                [BlockedApplication].self,
                forKey: .blockedApplications
            ),
            domainRules: try container.decode([DomainRule].self, forKey: .domainRules),
            defaultDurationSeconds: try container.decode(Int.self, forKey: .defaultDurationSeconds),
            difficulty: try container.decode(Difficulty.self, forKey: .difficulty),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt)
        )
        do {
            try validate()
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .name,
                in: container,
                debugDescription: "Invalid focus preset: \(error)"
            )
        }
    }
}

public enum FocusSessionStatus: String, Codable, CaseIterable, Sendable {
    case active
    case onBreak
    case completed
    case endedEarly

    public var isTerminal: Bool {
        self == .completed || self == .endedEarly
    }
}

public struct FocusBreak: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let endsAt: Date
    public let requestedDurationMinutes: Int

    public init(startedAt: Date, endsAt: Date, requestedDurationMinutes: Int) {
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.requestedDurationMinutes = requestedDurationMinutes
    }
}

public enum InterruptionKind: String, Codable, CaseIterable, Sendable {
    case takeBreak
    case endSession
}

public struct InterruptionChallenge: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: InterruptionKind
    public let requestedAt: Date
    public let availableAt: Date
    public let breakDurationMinutes: Int?

    public var waitDuration: TimeInterval {
        availableAt.timeIntervalSince(requestedAt)
    }

    public init(
        id: UUID = UUID(),
        kind: InterruptionKind,
        requestedAt: Date,
        availableAt: Date,
        breakDurationMinutes: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.requestedAt = requestedAt
        self.availableAt = availableAt
        self.breakDurationMinutes = breakDurationMinutes
    }
}

public enum SupportedBrowser: String, Codable, CaseIterable, Sendable {
    case safari
    case chrome
    case dia

    public var bundleIdentifier: String {
        switch self {
        case .safari: "com.apple.Safari"
        case .chrome: "com.google.Chrome"
        case .dia: "company.thebrowser.dia"
        }
    }

    public var displayName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Google Chrome"
        case .dia: "Dia"
        }
    }

    public static func browser(forBundleIdentifier bundleIdentifier: String?) -> Self? {
        allCases.first { $0.bundleIdentifier == bundleIdentifier }
    }
}

public enum BrowserPermissionState: String, Codable, CaseIterable, Sendable {
    case unavailable
    case notDetermined
    case authorized
    case denied
    case incompatible
}

public struct BrowserEnforcementHealth: Codable, Equatable, Sendable {
    public let browser: SupportedBrowser
    public var isInstalled: Bool
    public var permissionState: BrowserPermissionState
    public var message: String?

    public init(
        browser: SupportedBrowser,
        isInstalled: Bool,
        permissionState: BrowserPermissionState,
        message: String? = nil
    ) {
        self.browser = browser
        self.isInstalled = isInstalled
        self.permissionState = permissionState
        self.message = message
    }
}

public struct EnforcementHealth: Codable, Equatable, Sendable {
    public var appBlockingOperational: Bool
    public var browserHealth: [BrowserEnforcementHealth]
    public var issues: [String]
    public var lastCheckedAt: Date?

    public init(
        appBlockingOperational: Bool = false,
        browserHealth: [BrowserEnforcementHealth] = [],
        issues: [String] = [],
        lastCheckedAt: Date? = nil
    ) {
        self.appBlockingOperational = appBlockingOperational
        self.browserHealth = browserHealth
        self.issues = issues
        self.lastCheckedAt = lastCheckedAt
    }
}

public enum FocusSessionValidationError: Error, Equatable, Sendable {
    case presetDifficultyMismatch
    case invalidChronology
    case invalidDuration
    case invalidCounters
    case inconsistentBreakState
    case inconsistentChallengeState
}

public struct FocusSession: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let preset: FocusPreset
    public let startDate: Date
    public let endDate: Date
    public let difficulty: Difficulty
    public let intention: String?
    public var status: FocusSessionStatus
    public var breakCount: Int
    public var activeBreak: FocusBreak?
    public var pendingInterruption: InterruptionChallenge?
    public var interruptionRequestCount: Int
    public var enforcementHealth: EnforcementHealth

    public var remainingTime: TimeInterval {
        remainingTime(at: Date())
    }

    public init(
        id: UUID = UUID(),
        preset: FocusPreset,
        startDate: Date,
        endDate: Date,
        difficulty: Difficulty,
        intention: String? = nil,
        status: FocusSessionStatus = .active,
        breakCount: Int = 0,
        activeBreak: FocusBreak? = nil,
        pendingInterruption: InterruptionChallenge? = nil,
        interruptionRequestCount: Int = 0,
        enforcementHealth: EnforcementHealth = EnforcementHealth()
    ) {
        self.id = id
        self.preset = preset
        self.startDate = startDate
        self.endDate = endDate
        self.difficulty = difficulty
        self.intention = intention?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.status = status
        self.breakCount = breakCount
        self.activeBreak = activeBreak
        self.pendingInterruption = pendingInterruption
        self.interruptionRequestCount = interruptionRequestCount
        self.enforcementHealth = enforcementHealth
    }

    public func remainingTime(at date: Date) -> TimeInterval {
        max(0, endDate.timeIntervalSince(date))
    }

    public func validate() throws {
        try preset.validate()
        guard difficulty == preset.difficulty else {
            throw FocusSessionValidationError.presetDifficultyMismatch
        }
        guard endDate > startDate else {
            throw FocusSessionValidationError.invalidChronology
        }
        let duration = endDate.timeIntervalSince(startDate)
        guard duration >= TimeInterval(FocusSessionEngine.allowedSessionDurationSeconds.lowerBound),
              duration <= TimeInterval(FocusSessionEngine.allowedSessionDurationSeconds.upperBound)
        else {
            throw FocusSessionValidationError.invalidDuration
        }
        guard breakCount >= 0,
              interruptionRequestCount >= 0,
              breakCount <= interruptionRequestCount
        else {
            throw FocusSessionValidationError.invalidCounters
        }

        switch status {
        case .active:
            guard activeBreak == nil else {
                throw FocusSessionValidationError.inconsistentBreakState
            }
        case .onBreak:
            guard breakCount > 0,
                  difficulty != .locked,
                  let activeBreak,
                  activeBreak.startedAt >= startDate,
                  activeBreak.endsAt > activeBreak.startedAt,
                  activeBreak.endsAt <= endDate,
                  FocusSessionEngine.allowedBreakDurationMinutes.contains(
                      activeBreak.requestedDurationMinutes
                  )
            else {
                throw FocusSessionValidationError.inconsistentBreakState
            }
        case .completed, .endedEarly:
            guard activeBreak == nil, pendingInterruption == nil else {
                throw FocusSessionValidationError.inconsistentBreakState
            }
        }

        if let pendingInterruption {
            let expectedWait = FocusSessionEngine.interruptionWaitDuration(
                for: difficulty,
                priorRequestCount: interruptionRequestCount - 1
            )
            guard interruptionRequestCount > 0,
                  difficulty != .locked,
                  pendingInterruption.requestedAt >= startDate,
                  pendingInterruption.requestedAt < endDate,
                  pendingInterruption.availableAt >= pendingInterruption.requestedAt,
                  abs(pendingInterruption.waitDuration - expectedWait) < 0.001
            else {
                throw FocusSessionValidationError.inconsistentChallengeState
            }
            switch pendingInterruption.kind {
            case .takeBreak:
                guard let minutes = pendingInterruption.breakDurationMinutes,
                      FocusSessionEngine.allowedBreakDurationMinutes.contains(minutes),
                      status == .active
                else {
                    throw FocusSessionValidationError.inconsistentChallengeState
                }
            case .endSession:
                guard pendingInterruption.breakDurationMinutes == nil else {
                    throw FocusSessionValidationError.inconsistentChallengeState
                }
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
