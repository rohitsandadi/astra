# Astra

Astra is a local-first, open-source focus blocker for macOS. It provides timed
focus sessions, reusable app and website presets, three interruption
difficulties, and native browser automation for Safari, Google Chrome, and Dia.

## What is included

- Native SwiftUI interface with one muted-indigo accent. Liquid Glass is kept
  to navigation and floating controls; content uses quiet, high-contrast surfaces.
- A searchable installed-app catalog and a focused website picker with local
  suggestions and normalized domain entry.
- App blocking through a per-user background helper.
- Domain and subdomain blocking in the foreground tab of Safari, Chrome, and Dia.
- Flexible, Commitment, and Locked focus sessions, including 1–15 minute breaks.
- Local-only presets and active-session state. There are no accounts, analytics,
  telemetry, or cloud services.

## Build and test

Requirements: macOS 15 or newer, Xcode 26 or newer, and Swift 6.

```sh
swift test --disable-sandbox
./scripts/build-app.sh
./scripts/package-release.sh
```

The scripts create an ad-hoc-signed `build/Astra.app` and a GitHub-ready DMG in
`dist/`. No paid Apple Developer Program membership is required. These builds
are intentionally not notarized, so follow [the installation instructions](docs/INSTALL.md)
for the first launch.

See [the architecture](docs/ARCHITECTURE.md) for enforcement details and the
self-control threat model. Contributions are described in
[CONTRIBUTING.md](docs/CONTRIBUTING.md).

License: GPL-3.0-only.
