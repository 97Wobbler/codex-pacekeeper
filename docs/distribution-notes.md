# Distribution Notes

## v0.2.3 Release

`v0.2.3` makes Codex usage polling resilient to WHAM rate-limit schema changes
instead of requiring every response to contain a fixed five-hour and weekly pair.

Included in this release:

- accepts one or two usable Codex rate-limit windows
- derives window labels from the duration reported by WHAM
- keeps legacy five-hour plus weekly responses working
- renders and notifies only the windows actually returned by the service
- tolerates a missing or incomplete companion window without dropping valid usage data
- package defaults bumped to version `0.2.3` build `5`

## v0.2.2 Release

`v0.2.2` hardens Claude direct fallback credential handling so Pacekeeper does
not keep touching Claude Code's original Keychain item during background polling.

Included in this release:

- direct fallback imports Claude Code OAuth credentials into a Pacekeeper-owned Keychain item
- automatic fallback polling reads and refreshes only Pacekeeper's imported credential copy
- direct fallback can forget Pacekeeper's imported credential without deleting Claude Code credentials
- stale direct-access authorization is reset without showing a Keychain prompt
- package defaults bumped to version `0.2.2` build `4`

## v0.2.1 Release

`v0.2.1` adds an opt-in experimental direct fallback for Claude usage when the
statusline-backed cache is stale or missing.

Included in this release:

- Claude usage source menu with `Statusline Only` and `Statusline + Experimental Fallback`
- direct fallback reads Claude Code OAuth credentials from Keychain or legacy credentials file
- direct fallback requires explicit menu authorization before automatic polling
- direct fallback refreshes expired Claude OAuth access tokens when possible
- direct fallback throttled to avoid repeated calls to internal OAuth and usage endpoints
- fallback keeps stale cache values visible when direct lookup is unavailable
- package defaults bumped to version `0.2.1` build `3`

## v0.2.0 Release

`v0.2.0` adds the notch island HUD and keeps the original floating HUD available
as a switchable mode. It also adds optional Claude Code usage display through
Claude Code statusline `rate_limits`.

Included in this release:

- switchable notch island and floating HUD display modes
- drag docking from the notch island into floating mode
- drag docking from floating mode back into the notch island
- refined notch island width and hover expansion behavior
- compact notch provider selection for Codex or Claude
- optional Claude Code usage display from a statusline-backed cache
- stale Claude usage values remain visible with dimmed indicators
- expanded notch height fits its rendered content
- removal of the floating HUD opacity control

## v0.1.0 Baseline

`v0.1.0` is the first MVP release line for Codex Pacekeeper.

Included in this baseline:

- macOS menu bar app and floating HUD
- Codex auth token lookup from `~/.codex/auth.json`
- WHAM usage API polling
- 5-hour and weekly pace calculations
- HUD position persistence
- stale/error/paused states
- threshold/redline notifications when running as a bundled app
- local release packaging into `CodexPacekeeper.app.zip`
- curl-based installation from GitHub Releases

Not included in this baseline:

- App Store distribution
- Developer ID signing
- Apple notarization
- `.dmg` packaging
- automatic updates
- Homebrew cask

## Recommended MVP Distribution

Use GitHub Releases with a zipped macOS app bundle.

Target install command:

```sh
curl -fsSL https://raw.githubusercontent.com/97Wobbler/codex-pacekeeper/main/install.sh | bash
```

Recommended release asset URL shape:

```text
https://github.com/97Wobbler/codex-pacekeeper/releases/latest/download/CodexPacekeeper.app.zip
```

`install.sh` should:

1. Download the latest `CodexPacekeeper.app.zip` release asset.
2. Unzip it to a temporary directory.
3. Install to `~/Applications/CodexPacekeeper.app` or `/Applications/CodexPacekeeper.app`.
4. Open the app after installation.

Example installer outline:

```sh
curl -L -o /tmp/CodexPacekeeper.zip \
  https://github.com/97Wobbler/codex-pacekeeper/releases/latest/download/CodexPacekeeper.app.zip

unzip -q /tmp/CodexPacekeeper.zip -d /tmp
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/CodexPacekeeper.app"
mv /tmp/CodexPacekeeper.app "$HOME/Applications/"
open "$HOME/Applications/CodexPacekeeper.app"
```

## Avoid Raw Binary Files In The Repository

Do not commit compiled app bundles or zip files directly to the repository.

Reasons:

- Binary artifacts bloat Git history.
- GitHub Releases handle versioned downloads better.
- Release assets are easier to checksum, replace, and automate.
- Future update/install scripts can target `releases/latest/download/...`.

## Packaging Plan

Implemented near-term workflow:

1. Run `scripts/package-release.sh`.
2. Build the release binary with `swift build -c release`.
3. Create a minimal unsigned `.app` bundle around the executable.
4. Zip `CodexPacekeeper.app` into `dist/CodexPacekeeper.app.zip`.
5. Upload the zip to a GitHub Release tagged for the current version, such as `v0.2.3`.
6. Install with `install.sh`.

Release metadata defaults:

- Version: `0.2.3`
- Build number: `5`
- Bundle ID: `dev.whchoi.codex-pacekeeper`

These can be overridden for packaging:

```sh
VERSION=0.2.3 BUILD_NUMBER=5 BUNDLE_ID=dev.whchoi.codex-pacekeeper scripts/package-release.sh
```

Later:

- Teach `install.sh` to stop a running app, replace the installed bundle, and
  relaunch from a stable install path.
- Standardize the user install path as `~/Applications/CodexPacekeeper.app`.
- Add login item registration or repair so startup always points at the stable
  installed app instead of a repository-local `dist/CodexPacekeeper.app`.
- Add a documented manual update flow for personal use before automatic updates
  are implemented.
- Add Developer ID code signing.
- Add notarization.
- Consider a `.dmg` package.
- Consider a Homebrew cask after the app stabilizes.

## macOS Signing And Gatekeeper

Unsigned apps are acceptable for early personal use, but Gatekeeper warnings are expected for broader distribution.

Longer-term public distribution should use:

- Developer ID signing
- Apple notarization
- A release pipeline that signs and notarizes before uploading assets
