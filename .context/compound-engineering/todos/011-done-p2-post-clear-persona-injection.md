---
status: done
priority: p2
issue_id: "011"
tags: [daemon, persona, hooks, clear]
dependencies: []
assignee: jarvis
---

# Handle post-/clear persona file injection

## Problem Statement

When a daemon agent session hits `/clear`, the SessionStart hook re-fires and injects persona files (SOUL.md, IDENTITY.md, USER.md, TOOLS.md) into context via system reminders. However, there is no explicit handling to ensure these injections actually land correctly after a `/clear` — the agent relies on the hook firing but doesn't verify or re-request injection if it fails.

## Expected Behavior

After `/clear`, persona files should be reliably re-injected into the conversation context so the agent can reconstruct state with its full identity intact.

## Notes

- Currently the CLAUDE.md instructs the agent to reconstruct state from `.clawdkit/state.json` and `progress.log`, but persona continuity depends on the hook firing correctly.
- Need to determine: is this a hook-side fix (ensure hook always fires post-clear) or an agent-side fix (agent detects missing persona and re-reads files manually), or both.
