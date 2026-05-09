# Codex Hook Cleanup Guide

This guide tracks the intended migration away from the previous cmux HUD hook setup described in the PRD.

## Goal

Keep Codex prompt submission and response flow independent from usage display work. Codex Whiplash should own usage polling and notifications as a standalone macOS menu bar app.

## Recommended Direction

1. Run Codex Whiplash as the primary usage monitor.
2. Disable the cmux split-pane HUD hook once the menu bar app provides the needed usage visibility.
3. If running/idle status is needed later, keep any Codex hook in a lightweight mode that only writes a small status file.

## Previous Hook Shape

The prior approach used Codex hook events such as:

- `SessionStart`
- `UserPromptSubmit`
- `Stop`

Those events called a shell script that managed cmux HUD state, fetched usage data, and updated workspace status. That combined several UI and network responsibilities with Codex execution events.

## Cleanup Checklist

- [ ] Confirm Codex Whiplash can read `~/.codex/auth.json`.
- [ ] Confirm usage data refreshes successfully in the menu bar app.
- [ ] Confirm stale/error states are visible when the usage API fails.
- [ ] Disable the cmux HUD hook path in local Codex config.
- [ ] Verify prompt submission no longer invokes HUD update work.
- [ ] Check there is only one long-running usage monitor process.

## Notes

Do not remove local hook files until the menu bar app has covered the user's daily usage visibility needs. The first cleanup should be disabling invocation, not deleting recoverable local scripts.
