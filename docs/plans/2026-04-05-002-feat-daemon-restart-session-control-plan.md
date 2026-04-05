---
title: "feat: Add daemon restart as a session control MCP tool"
type: feat
status: active
date: 2026-04-05
---

# feat: Add daemon restart as a session control MCP tool

## Overview

Add a `restart_daemon` tool to the session-control MCP server so the daemon agent can trigger its own restart programmatically — enabling self-healing, config reloads, and clean resets without manual shell intervention.

## Problem Frame

The daemon agent cannot restart itself. Restarts currently require `make restart` or `clawdkit restart` from an external shell. This prevents the agent from self-healing after config changes, applying updates, or recovering from degraded state.

## Requirements Trace

- R1. The agent can trigger a restart from within its own session via MCP tool call
- R2. The restart is graceful — the MCP tool returns success before the process dies
- R3. State is preserved across restart via `state.json` (agent reconstructs on boot)
- R4. Optional `reason` parameter for logging why the restart was triggered

## Scope Boundaries

- No changes to the restart logic itself (`do_stop; do_start` in clawdkit.sh stays as-is)
- No graceful shutdown handshake or drain period — the existing hard kill is acceptable for now
- No external-caller API — this is an MCP tool callable only from within the daemon session

## Context & Research

### Relevant Code and Patterns

- `daemon/mcp/session-control/server.ts` — existing `clear_context` and `compact_context` tools follow an identical pattern: register in `ListToolsRequestSchema`, handle in `CallToolRequestSchema` switch, call a helper, return text content
- `daemon/scripts/clawdkit.sh` lines 270-275 — `restart` subcommand does `do_stop; do_start`
- `daemon/templates/.mcp.json.template` — MCP server env config; currently only passes `CLAWDKIT_AGENT_NAME`

### Institutional Learnings

- No `docs/solutions/` directory exists yet — no prior art

## Key Technical Decisions

- **Fire-and-forget detached process**: The MCP server runs inside the tmux session that `restart` will kill. It cannot call restart synchronously without killing itself mid-response. Solution: spawn a detached shell process (`nohup ... &`) that sleeps briefly (2s), then runs `clawdkit.sh --instance $AGENT_NAME restart`. The MCP tool returns immediately.
- **Pass `CLAWDKIT_SCRIPTS_PATH` via MCP env config**: The session-control server needs to know where `clawdkit.sh` lives. `clawdkit.sh` already exports this env var into the tmux session, but the MCP server config (`.mcp.json`) doesn't pass it through. Adding it to the template and stamped configs is the clean fix.
- **Log restart reason to `state.json`**: Before spawning the restart process, write a `pending_restart` field with the reason to `state.json`. The new session can detect this on boot and log it.

## Open Questions

### Resolved During Planning

- **MCP tool, CLI subcommand, or both?** MCP tool only. The CLI already has `clawdkit restart`. The gap is agent-callable restart, which is the MCP tool's job.
- **Why not `tmux respawn-pane`?** It restarts only the pane process, not the full lifecycle (env vars, MCP servers, channel setup). `clawdkit.sh restart` is the correct entrypoint because it tears down and rebuilds everything.

### Deferred to Implementation

- Exact sleep duration before restart (2s seems safe but may need tuning)
- Whether `nohup` or `setsid` is more portable for the detached process

## Implementation Units

- [ ] **Unit 1: Pass `CLAWDKIT_SCRIPTS_PATH` to session-control MCP server**

  **Goal:** Make the scripts path available as an env var so the server can locate `clawdkit.sh`.

  **Requirements:** R1 (prerequisite)

  **Dependencies:** None

  **Files:**
  - Modify: `daemon/templates/.mcp.json.template`
  - Modify: `daemon/scripts/clawdkit.sh` (bootstrap `sed` replacements for the new placeholder)

  **Approach:**
  - Add `"CLAWDKIT_SCRIPTS_PATH": "{{CLAWDKIT_SCRIPTS_PATH}}"` to the `clawdkit-session-control` env block in the template
  - Add corresponding `sed` replacement in the bootstrap function of `clawdkit.sh`

  **Patterns to follow:**
  - Existing `CLAWDKIT_AGENT_NAME` env var pattern in `.mcp.json.template`
  - Existing `sed` replacement patterns in `clawdkit.sh` `do_bootstrap()` function

  **Test expectation:** none — pure config plumbing, verified by Unit 3's integration test

  **Verification:**
  - After bootstrap, the stamped `.mcp.json` contains the correct absolute path for `CLAWDKIT_SCRIPTS_PATH`
  - The session-control server can read `process.env.CLAWDKIT_SCRIPTS_PATH` at runtime

- [ ] **Unit 2: Add `restart_daemon` tool to session-control MCP server**

  **Goal:** Register and implement the restart tool that spawns a detached restart process and returns immediately.

  **Requirements:** R1, R2, R3, R4

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `daemon/mcp/session-control/server.ts`

  **Approach:**
  - Read `CLAWDKIT_SCRIPTS_PATH` and `CLAWDKIT_AGENT_NAME` from env
  - Add `restart_daemon` to the tools array with optional `reason` string parameter
  - In the handler: write `pending_restart` + reason to `state.json` (read path from `CLAWDKIT_INSTANCE_DIR` or derive from convention), then spawn detached `sh -c "sleep 2 && $SCRIPTS_PATH/clawdkit.sh --instance $AGENT_NAME restart"` via `Bun.spawn` with `stdio: 'ignore'` and `detached: true` (or `nohup`), then return success text
  - Also pass `CLAWDKIT_INSTANCE_DIR` through env (same pattern as Unit 1) so the server knows where `state.json` lives

  **Patterns to follow:**
  - `clear_context` and `compact_context` tool registration pattern
  - `tmuxSendKeys` error handling pattern (but here we fire-and-forget)

  **Test scenarios:**
  - Happy path: calling `restart_daemon` with a reason returns success text and spawns a background process
  - Happy path: calling `restart_daemon` without a reason returns success text
  - Edge case: `CLAWDKIT_SCRIPTS_PATH` not set — tool returns a clear error message
  - Integration: after the tool fires, `state.json` contains `pending_restart` field with the reason

  **Verification:**
  - Tool appears in MCP tool list
  - Calling the tool returns success immediately (does not hang or crash)
  - `state.json` is updated with restart reason before the process spawns
  - The daemon actually restarts after the delay

- [ ] **Unit 3: Update template env config for `CLAWDKIT_INSTANCE_DIR`**

  **Goal:** Pass instance directory to session-control server so it can write to `state.json`.

  **Requirements:** R3 (prerequisite for state preservation)

  **Dependencies:** None (can be done in parallel with Unit 1)

  **Files:**
  - Modify: `daemon/templates/.mcp.json.template`
  - Modify: `daemon/scripts/clawdkit.sh` (bootstrap `sed` for new placeholder)

  **Approach:**
  - Add `"CLAWDKIT_INSTANCE_DIR": "{{CLAWDKIT_INSTANCE_DIR}}"` to session-control env block
  - Add `sed` replacement in bootstrap

  **Patterns to follow:**
  - Same as Unit 1

  **Test expectation:** none — config plumbing verified by Unit 2's integration

  **Verification:**
  - Stamped `.mcp.json` contains correct instance dir path

## System-Wide Impact

- **Interaction graph:** The restart tool spawns an external process that calls `clawdkit.sh restart`, which kills the tmux session (and all child processes including the MCP server itself). This is intentional and expected.
- **Error propagation:** If the detached restart process fails, there is no feedback channel — the old session is already dead. The new session's state reconstruction will detect `pending_restart` in `state.json` and can log whether the restart completed.
- **State lifecycle risks:** The 2s delay between MCP response and session kill gives the MCP protocol time to deliver the response. If the delay is too short, the caller may not receive confirmation.
- **Unchanged invariants:** `clear_context` and `compact_context` tools are unaffected. The existing `clawdkit restart` CLI command continues to work as before.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Detached process orphaned if spawn fails silently | Log spawn attempt to stderr; `state.json` `pending_restart` field serves as evidence the tool fired |
| Sleep too short — response not delivered before kill | Start with 2s; easy to tune. The MCP response is small and fast. |
| `CLAWDKIT_SCRIPTS_PATH` not available in env | Validate at tool call time, return clear error |

## Sources & References

- Related todo: `.context/compound-engineering/todos/012-pending-p2-daemon-restart-session-control.md`
- Related code: `daemon/mcp/session-control/server.ts`, `daemon/scripts/clawdkit.sh`
