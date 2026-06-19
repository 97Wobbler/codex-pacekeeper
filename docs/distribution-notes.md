# Distribution Notes

## v0.2.0 Release

`v0.2.0` adds the notch island HUD line and keeps the original floating HUD
available as a switchable mode.

Included in this release:

- switchable notch island and floating HUD display modes
- drag docking from the notch island into floating mode
- drag docking from floating mode back into the notch island
- refined notch island width and hover expansion behavior
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
5. Upload the zip to a GitHub Release tagged for the current version, such as `v0.2.0`.
6. Install with `install.sh`.

Release metadata defaults:

- Version: `0.2.0`
- Build number: `2`
- Bundle ID: `dev.whchoi.codex-pacekeeper`

These can be overridden for packaging:

```sh
VERSION=0.2.0 BUILD_NUMBER=2 BUNDLE_ID=dev.whchoi.codex-pacekeeper scripts/package-release.sh
```

Later:

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
