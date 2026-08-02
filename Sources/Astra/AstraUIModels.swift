import AppKit
import AstraCore
import Foundation

enum AstraDestination: String, CaseIterable, Identifiable {
    case focus
    case presets
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .focus: "Focus"
        case .presets: "Routines"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .focus: "circle.dashed"
        case .presets: "square.stack.3d.up"
        case .settings: "gearshape"
        }
    }
}

typealias AstraDifficulty = Difficulty

extension Difficulty {
    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .flexible: "leaf"
        case .commitment: "hourglass"
        case .locked: "lock"
        }
    }

    var detail: String {
        switch self {
        case .flexible:
            "Pause for six seconds before taking a break or ending early."
        case .commitment:
            "Interruptions become progressively slower: 30 seconds, 1, 2, then 4 minutes."
        case .locked:
            "No breaks and no early ending after your final confirmation."
        }
    }
}

typealias AstraBlockedApplication = BlockedApplication

extension BlockedApplication {
    var icon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}

typealias AstraPreset = FocusPreset

extension FocusPreset {
    init(
        id: UUID = UUID(),
        name: String,
        applications: [AstraBlockedApplication] = [],
        domains: [String] = [],
        durationMinutes: Int = 45,
        difficulty: AstraDifficulty = .commitment
    ) {
        self.init(
            id: id,
            name: name,
            blockedApplications: applications,
            domainRules: domains.compactMap { try? DomainRule($0) },
            defaultDurationSeconds: durationMinutes * 60,
            difficulty: difficulty
        )
    }

    static let starter = AstraPreset(
        name: "Deep Work",
        domains: ["youtube.com", "reddit.com"],
        durationMinutes: 45,
        difficulty: .commitment
    )

    var applications: [AstraBlockedApplication] {
        get { blockedApplications }
        set { blockedApplications = newValue }
    }

    var domains: [String] {
        get { domainRules.map(\.host) }
        set { domainRules = newValue.compactMap { try? DomainRule($0) } }
    }

    var durationMinutes: Int {
        get { defaultDurationSeconds / 60 }
        set { defaultDurationSeconds = newValue * 60 }
    }
}

struct AstraFocusRequest: Codable, Hashable {
    var preset: AstraPreset
    var intention: String
    var durationMinutes: Int
    var difficulty: AstraDifficulty
}

typealias AstraFocusSession = FocusSession

extension FocusSession {
    var startedAt: Date { startDate }
    var endsAt: Date { endDate }
    var breakEndsAt: Date? { activeBreak?.endsAt }

    func remaining(at date: Date) -> TimeInterval {
        remainingTime(at: date)
    }

    func progress(at date: Date) -> Double {
        let total = endDate.timeIntervalSince(startDate)
        guard total > 0 else { return 1 }
        return min(max(1 - remaining(at: date) / total, 0), 1)
    }

    func breakRemaining(at date: Date) -> TimeInterval? {
        guard let activeBreak else { return nil }
        return max(0, min(activeBreak.endsAt.timeIntervalSince(date), remaining(at: date)))
    }
}

typealias AstraBrowser = SupportedBrowser

enum AstraPermissionStatus: String, Codable {
    case ready
    case notRequested
    case denied
    case notInstalled

    var title: String {
        switch self {
        case .ready: "Ready"
        case .notRequested: "Permission needed"
        case .denied: "Permission denied"
        case .notInstalled: "Not installed"
        }
    }
}

struct AstraBrowserPermission: Identifiable, Codable, Hashable {
    var id: AstraBrowser { browser }
    var browser: AstraBrowser
    var status: AstraPermissionStatus
    var detail: String?

    init(browser: AstraBrowser, status: AstraPermissionStatus, detail: String? = nil) {
        self.browser = browser
        self.status = status
        self.detail = detail
    }
}

struct AstraEnforcementHealth: Codable, Hashable {
    var helperAvailable: Bool
    var browserPermissions: [AstraBrowserPermission]
    var issues: [String]

    init(
        helperAvailable: Bool,
        browserPermissions: [AstraBrowserPermission],
        issues: [String] = []
    ) {
        self.helperAvailable = helperAvailable
        self.browserPermissions = browserPermissions
        self.issues = issues
    }

    var readyBrowserCount: Int {
        browserPermissions.count(where: { $0.status == .ready })
    }

    var installedBrowserCount: Int {
        browserPermissions.count(where: { $0.status != .notInstalled })
    }

    var allInstalledBrowsersReady: Bool {
        installedBrowserCount > 0
            && browserPermissions.allSatisfy {
                $0.status == .notInstalled || $0.status == .ready
            }
    }
}

enum AstraInterruptionKind: Codable, Hashable {
    case breakFor(minutes: Int)
    case endSession
}

typealias AstraInterruptionChallenge = InterruptionChallenge

extension InterruptionChallenge {
    var readyAt: Date { availableAt }
}

enum AstraUIError: LocalizedError {
    case invalidDomain
    case lockedSession
    case challengeNotReady

    var errorDescription: String? {
        switch self {
        case .invalidDomain: "Enter a valid domain such as example.com."
        case .lockedSession: "Locked sessions cannot be interrupted."
        case .challengeNotReady: "The interruption countdown is still running."
        }
    }
}

enum AstraDomainNormalizer {
    static func normalize(_ rawValue: String) throws -> String {
        do {
            return try DomainRule.normalize(rawValue)
        } catch {
            throw AstraUIError.invalidDomain
        }
    }
}

enum AstraProtectedApplications {
    static let bundleIdentifiers: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.WindowManager",
        "com.apple.systemuiserver",
        "com.rohitsandadi.astra",
        "com.rohitsandadi.astra.enforcer"
    ]
}
