# Codex Pacekeeper

Codex Pacekeeper is a macOS menu bar utility for tracking Codex usage against a recommended pace. It is intended to move usage display out of Codex hook critical paths and into a calm, glanceable native UI.

The product direction and MVP scope live in [docs/codex-pacekeeper-prd.md](docs/codex-pacekeeper-prd.md).

## Current Status

Functional SwiftUI scaffold:

- Swift Package Manager project
- macOS `MenuBarExtra` shell
- floating HUD shell using `NSPanel`
- `~/.codex/auth.json` access token reading
- ChatGPT WHAM usage API polling
- pace calculation model for actual usage, recommended pace, delta, and status
- loading, stale, error, and paused states
- Threshold/Redline notification logic for bundled app runs
- unit tests for the pace model

## Requirements

- macOS 13 or newer
- Swift 5.10 or newer

Full Xcode is recommended for app bundling and signing. The current repository can be built and tested with command line tools.

## Development

```sh
swift build
swift test
```

Run the app during development:

```sh
swift run CodexPacekeeper
```

## MVP Direction

Remaining MVP work:

- HUD drag/snap and position persistence
- settings for polling interval and notification behavior
- app bundle/signing workflow
