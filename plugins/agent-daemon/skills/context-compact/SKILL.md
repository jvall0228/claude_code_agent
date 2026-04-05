---
name: context-compact
description: Sends /compact to the daemon's own tmux session via tmux send-keys. Use when the context window is large but state should be preserved. Lighter than /clear — summarizes rather than resets.
---

# Context Compact

Sends `/compact` to this daemon's tmux session. Unlike `/clear`, compact summarizes the conversation history and retains a condensed version, preserving continuity while freeing context space.

## When to Use

- Context window is getting large (approaching limits) but session continuity matters
- Long-running sessions where resetting via `/clear` would lose too much in-flight context
- Prefer `/clear` when persona re-injection is needed (e.g., after a long drift)
- Prefer `/compact` when work is actively in progress and state should not be interrupted

## Implementation

```sh
#!/bin/sh
AGENT_NAME="${CLAWDKIT_AGENT_NAME:-$(cat ~/.clawdcode/.current-instance 2>/dev/null || echo 'clawdkit')}"
SESSION_NAME="clawdkit-${AGENT_NAME}"

if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  echo "ERROR: tmux session ${SESSION_NAME} not found"
  exit 1
fi

# Send /compact to the daemon's pane
tmux send-keys -t "${SESSION_NAME}" "/compact" Enter

echo "Sent /compact to ${SESSION_NAME}."
```

## Notes

- `/compact` does NOT re-trigger SessionStart hooks (that only happens on `/clear`)
- If persona files need refreshing, use `/agent-daemon:context-reset` instead
- The agent may call this skill proactively when progress.log shows session has been long-running
