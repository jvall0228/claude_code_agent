---
status: done
priority: p2
issue_id: "012"
tags: [daemon, session-control, mcp, tools]
dependencies: []
assignee: jarvis
---

# Add daemon restart as a session control tool

## Problem Statement

There is no way for the daemon agent (or an external caller) to trigger a daemon restart through a session control tool. Currently restarts require manual `make restart` from the shell. A restart tool would allow the agent to self-heal, apply config changes, or reset cleanly without human intervention.

## Expected Behavior

A session control tool (MCP tool or similar) that triggers a graceful daemon restart — stopping the current session and starting a fresh one with state reconstruction.

## Notes

- Should be safe to call from within the daemon itself (graceful shutdown before restart, not a hard kill)
- Consider whether this is an MCP tool, a ClawdKit CLI subcommand, or both
- State should be preserved across the restart via `.clawdkit/state.json`
