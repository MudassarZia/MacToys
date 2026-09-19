# Contributing

Build with Xcode 16+ / Swift 6 in Swift 5 language mode on macOS 14+.

```sh
swift test
bash scripts/build-app.sh
```

## Structure

- `Sources/MacToysCore`: deterministic transforms, CSV parsing, rename plans/execution, shell quoting, zone models.
- `Sources/MacToys`: SwiftUI screens and native OS integrations. Managers own long-lived services; individual screens own transient editing state.
- `Tests/MacToysCoreTests`: behavioral tests using isolated temporary files.
- `scripts`: app assembly, code-native icon generation, source packaging, optional zsh integration.

Keep native capabilities opt-in, report errors to users, use argument arrays instead of shell interpolation, never log clipboard or typed text, and add behavior tests for file mutations and parsers. Prefer documented APIs. Label narrower adaptations accurately. Do not add placeholder controls that imply a working feature.

When adding a tool, add a `Tool` entry, navigation destination, native implementation, and manual permission-denial checks. Do not request all permissions at launch. Test clean installs, denial, revocation, quit cleanup, and multiple displays where relevant.

For bug reports include macOS version, architecture, tool, reproduction steps, and non-sensitive sample data. Remove usernames, window titles, clipboard contents, environment variables, and credentials from screenshots/logs.
