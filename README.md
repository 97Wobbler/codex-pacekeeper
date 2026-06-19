# Codex Pacekeeper

Codex Pacekeeper is a macOS menu bar utility for tracking Codex usage against a recommended pace. It is intended to move usage display out of Codex hook critical paths and into a calm, glanceable native UI.

The product direction and MVP scope live in [docs/codex-pacekeeper-prd.md](docs/codex-pacekeeper-prd.md).

## Current Status

Current release target: `v0.2.0`.

Functional SwiftUI app:

- Swift Package Manager project
- macOS `MenuBarExtra` shell
- switchable notch island and floating HUD shells using `NSPanel`
- drag docking between notch island and floating HUD modes
- `~/.codex/auth.json` access token reading
- ChatGPT WHAM usage API polling
- pace calculation model for actual usage, recommended pace, delta, and status
- loading, stale, error, and paused states
- Threshold/Redline notification logic for bundled app runs
- unit tests for the pace model
- release packaging script for a zipped macOS `.app` bundle
- curl-based installer for GitHub Release assets

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

Run fixed visual QA scenarios without auth/API polling:

```sh
swift run CodexPacekeeper -- --demo-huds
```

## MVP Direction

Remaining MVP work:

- settings for polling interval and notification behavior
- Developer ID signing and notarization workflow

## Distribution

Codex Pacekeeper should be distributed through GitHub Releases as
`CodexPacekeeper.app.zip`.

Create the release archive locally:

```sh
scripts/package-release.sh
```

Install from the latest GitHub Release:

```sh
curl -fsSL https://raw.githubusercontent.com/97Wobbler/codex-pacekeeper/main/install.sh | bash
```

Distribution details and release checks live in
[docs/distribution-notes.md](docs/distribution-notes.md) and
[docs/release-checklist.md](docs/release-checklist.md).
