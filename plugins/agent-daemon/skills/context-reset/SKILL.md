---
name: context-reset
description: Sends /clear to the daemon's own tmux session via tmux send-keys. Use when the daemon's context window needs resetting. SessionStart hooks will automatically re-inject persona after /clear.
---

# Context Reset

Sends `/clear` to this daemon's tmux session, triggering a context window reset. SessionStart hooks re-inject persona automatically after the clear.

## Why This Skill Exists

Claude Code agents cannot invoke `/clear` on themselves through normal means. This skill bridges that gap by using `tmux send-keys` to send the command to the daemon's own session from the outside.

## Usage

Run `/agent-daemon:context-reset` from within the daemon session.

## Implementation

```sh
#!/bin/sh
# Read the instance name from state.json or environment
AGENT_NAME="${CLAWDKIT_AGENT_NAME:-$(cat ~/.clawdcode/.current-instance 2>/dev/null || echo 'clawdkit')}"
SESSION_NAME="clawdkit-${AGENT_NAME}"

# Verify session exists
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  echo "ERROR: tmux session ${SESSION_NAME} not found"
  exit 1
fi

# Send /clear to the daemon's pane
tmux send-keys -t "${SESSION_NAME}" "/clear" Enter

echo "Sent /clear to ${SESSION_NAME}. Persona will re-inject via SessionStart hooks."
```

## What Happens After /clear

1. Claude Code clears the context window
2. SessionStart hooks fire automatically (configured in `.claude/settings.json`)
3. All 4 persona files (SOUL, IDENTITY, USER, TOOLS) are re-injected via `additionalContext`
4. The daemon reconstructs its state from `state.json` and `progress.log` per CLAUDE.md instructions

## Notes

- This skill is most useful when called by the daemon itself (via heartbeat or message) when context is degraded
- After `/clear`, the persona is restored mechanically — the agent does not need to re-read the brain manually
- State reconstruction (reading state.json, progress.log) is the agent's responsibility per CLAUDE.md
