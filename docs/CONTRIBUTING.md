# Contributing

## Requirements

- macOS 15 or newer on Apple silicon or Intel
- Xcode 26 or newer
- Swift 6

Run `swift test` before submitting a change. Build the application bundle with
`./scripts/build-app.sh` and create a local release artifact with
`./scripts/package-release.sh`.

Keep enforcement local, request the narrowest possible macOS permissions, and
never add analytics, accounts, or network services without an explicit project
decision. UI changes should use the single muted-indigo accent and remain
usable with Reduce Motion, Reduce Transparency, and Increase Contrast.
