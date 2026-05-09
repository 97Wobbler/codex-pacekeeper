# Agent Visualization Ideas

This document stores expansion ideas discovered during competitive research. These ideas are intentionally outside the first MVP unless they directly support the core usage HUD.

## Context

Recent Claude Code and Codex workflows are moving toward parallel agents, subagents, and long-running background sessions. Several tools now expose agent state through status lines, dashboards, floating widgets, or full control planes.

Codex Whiplash should not start as a general multi-agent orchestrator. The first product should remain a personal usage HUD: visible, lightweight, and focused on "am I using my quota at the right pace?"

## Ideas to Revisit Later

- Show active Codex or Claude sessions in the menu dropdown.
- Add a small status count to the menu bar, such as `3 running` or `1 blocked`.
- Detect stuck or waiting-for-input agents and send a notification.
- Add optional hooks that only write lightweight state files.
- Support Claude Code, Codex, Gemini CLI, and OpenCode as provider modules.
- Add a larger dashboard for active sessions, terminal links, recent prompts, and changed files.
- Visualize subagents as lanes, cards, or grouped workers.
- Track per-agent elapsed time, token samples, and last activity.

## Competitive Patterns

- Status line integrations surface context, token, cost, and subagent state inside the CLI.
- Menu bar apps focus on usage windows, reset timers, and notification thresholds.
- Floating widgets focus on "working / ready / needs input" without requiring terminal switching.
- Control-plane dashboards wrap multiple terminal sessions and add orchestration, git review, and task assignment.

## Product Boundary

For now, Codex Whiplash should keep these boundaries:

- Do not launch or orchestrate agents in the MVP.
- Do not replace Codex, Claude Code, or cmux.
- Do not add heavy hooks to the Codex critical path.
- Do keep the floating-on-screen idea, but use it first for actual usage versus recommended pace.

## Possible Future Positioning

If the core HUD works well, the product can expand from:

`quota pace HUD`

to:

`personal AI coding activity HUD`

The expansion should happen only after the basic 5h/week usage visibility is reliable.
