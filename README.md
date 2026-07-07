# Codex Pacekeeper

Codex Pacekeeper is a macOS menu bar utility for tracking Codex usage against a recommended pace. It is intended to move usage display out of Codex hook critical paths and into a calm, glanceable native UI.

The product direction and MVP scope live in [docs/codex-pacekeeper-prd.md](docs/codex-pacekeeper-prd.md).

## Current Status

Current release target: `v0.2.1`.

Functional SwiftUI app:

- Swift Package Manager project
- macOS `MenuBarExtra` shell
- switchable notch island and floating HUD shells using `NSPanel`
- drag docking between notch island and floating HUD modes
- `~/.codex/auth.json` access token reading
- ChatGPT WHAM usage API polling
- optional Claude Code usage display from statusline `rate_limits`
- opt-in experimental Claude direct usage fallback for stale/missing cache data
- pace calculation model for actual usage, recommended pace, delta, and status
- loading, stale, error, and paused states
- Threshold/Redline notification logic for bundled app runs
- unit tests for the pace model
- release packaging script for a zipped macOS `.app` bundle
- curl-based installer for GitHub Release assets

## Requirements

- macOS 13 or newer
- Swift 5.10 or newer

Full Xcode is recommended for tests, app bundling, and signing. The app can be
built with Command Line Tools, but `swift test` requires a working XCTest
toolchain.

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

## Claude Code Usage

Claude usage is cache-first. Claude Code 2.1.80 or newer can pass `rate_limits`
to a custom statusline script, and the bridge script stores only usage
percentages and reset times:

```sh
scripts/claude-statusline-bridge.sh
```

The active Claude statusline should pipe its stdin JSON to that script. The
cache is written to:

```text
~/Library/Application Support/Codex Pacekeeper/claude-rate-limits.json
```

Claude appears in the HUD when that cache exists. Old or post-reset cache data
is shown as stale with dimmed indicators.

By default, Pacekeeper does not read Claude OAuth credentials or call Anthropic's
internal usage endpoint. The menu includes an opt-in `Statusline + Experimental
Fallback` mode that can try a direct lookup when the statusline cache is stale or
missing. Direct access must be explicitly authorized from the menu before
automatic fallback polling starts. Authorization imports only the Claude OAuth
fields from Claude Code credentials into a Pacekeeper-owned Keychain item. After
that, automatic fallback polling reads and refreshes only the Pacekeeper-owned
copy; it does not keep touching or updating Claude Code's original Keychain
credential. The menu can forget the imported credential without deleting Claude
Code's credential. The fallback is off by default and may stop working without
notice. Direct fallback results do not overwrite the statusline cache.

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
