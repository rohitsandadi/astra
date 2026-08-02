# Astra architecture

## Trust model

Astra is a self-control tool, not a security boundary. All rules, presets, and
session data stay on the Mac. A user with control of the account can disable
the background item, revoke browser Automation access, change the system clock,
or delete the application. The UI describes Locked sessions accordingly.

The only optional outbound request is an update check against GitHub Releases.
It is disabled until the user explicitly opts in, and then runs at most once a
day when Astra opens. A manual check is always a deliberate user action.

## Processes

- `Astra` is the SwiftUI application and menu-bar interface.
- `AstraEnforcer` is a per-user launch agent registered through
  `SMAppService`. It owns active-session state and enforcement.
- `AstraCore` contains versioned data models, domain matching, session rules,
  interruption challenges, and persistence primitives.

The application communicates with the agent over a per-user XPC Mach service.
The agent accepts connections only from the sibling Astra executable in its app
bundle. It persists enough state to recover after a crash, login, or restart,
and reconciles wall-clock session deadlines immediately after wake.

## Enforcement

Selected GUI applications are observed through `NSWorkspace`. Astra requests a
normal termination first and force-terminates the process after a short grace
period. Users receive a list of affected running apps and an explicit save-work
warning before the session begins.

Website enforcement uses each supported browser's AppleScript dictionary. While
Safari, Chrome, or Dia is foreground, Astra reads the active tab URL, matches
its parsed hostname against the active rules, and redirects a match to a local
block page served on loopback. Astra never reads page content or browsing
history.

An explicit permission request opens a closed target browser without activation
before asking macOS for Automation consent. Passive health checks never launch
apps or display prompts. Since macOS cannot passively query a closed target,
the UI stores the last verified grant locally as advisory readiness; the live
poller remains authoritative and reports an actual denial immediately.

## Distribution

GitHub Actions builds a universal Intel/Apple-silicon, ad-hoc-signed app and
DMG, publishes a SHA-256 checksum, and includes the complete GPLv3 text. The
project intentionally does not require a paid Apple Developer Program
membership. Consequently the build is not notarized and users must approve it
in macOS Privacy & Security on first launch. Automation consent may need to be
granted again after updates.
