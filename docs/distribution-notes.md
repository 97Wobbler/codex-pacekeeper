# Distribution Notes

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

Near-term:

1. Add `scripts/package-release.sh`.
2. Build the release binary with `swift build -c release`.
3. Create a minimal `.app` bundle around the executable.
4. Zip `CodexPacekeeper.app` into `dist/CodexPacekeeper.app.zip`.
5. Upload the zip to a GitHub Release.
6. Add `install.sh` for curl-based installation.

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
