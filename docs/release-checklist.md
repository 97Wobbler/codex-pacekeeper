# Release Checklist

## v0.1.0

Release type: unsigned MVP GitHub Release.

Tag:

```text
v0.1.0
```

Release asset:

```text
CodexPacekeeper.app.zip
```

## Local Checks

Run before creating the release:

```sh
swift build
swift test
scripts/package-release.sh
unzip -l dist/CodexPacekeeper.app.zip
```

If `swift test` reports `XCTest not available`, install/select full Xcode and rerun.
The release package can still be built with Command Line Tools, but tests require a
working XCTest toolchain.

Optional smoke test:

```sh
open dist/CodexPacekeeper.app
```

## GitHub Release Steps

1. Confirm the working tree only contains intended release changes.
2. Commit the release prep changes.
3. Create and push tag `v0.1.0`.
4. Create a GitHub Release for `v0.1.0`.
5. Upload `dist/CodexPacekeeper.app.zip` as the release asset.
6. Verify that this URL downloads the asset:

```text
https://github.com/97Wobbler/codex-pacekeeper/releases/latest/download/CodexPacekeeper.app.zip
```

7. Run the installer on a clean local path:

```sh
curl -fsSL https://raw.githubusercontent.com/97Wobbler/codex-pacekeeper/main/install.sh | bash
```

## Known v0.1.0 Distribution Limits

- The app is unsigned, so macOS Gatekeeper warnings are expected.
- The installer replaces `~/Applications/CodexPacekeeper.app`.
- There is no automatic update channel yet.
- Release assets are managed manually in GitHub Releases.
