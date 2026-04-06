---
title: "feat: Graceful usage limit management for daemon agents"
type: feat
status: active
date: 2026-04-05
---

# feat: Graceful usage limit management for daemon agents

## Overview

Add local token estimation and budget management to ClawdKit daemons so they self-regulate consumption, leaving headroom for interactive sessions and never triggering extra-use quota on the OAuth plan.

## Problem Frame

Daemon agents run on the OAuth plan with daily token limits. There is no upstream API to query remaining quota — `--max-budget-usd` only works for `--print` mode, no `claude usage` command exists, and rate limit headers aren't surfaced to sessions. Without any consumption awareness, the daemon burns through tokens on heartbeat tasks and background work, potentially locking out interactive use for the rest of the day.

The design proposal in the todo (#013) establishes local estimation + daily cap as the only viable approach today. This plan implements that approach with a shell-side coarse gate (prevent heartbeat POST when budget is exhausted) and agent-side fine-grained control (low-fuel mode when approaching the cap).

## Requirements Trace

- R1. Daemon tracks approximate daily token consumption via local estimation
- R2. Daemon operates within a configurable daily budget, leaving headroom for interactive use
- R3. Low-fuel mode: daemon skips proactive heartbeat tasks but still handles inbound messages when approaching the cap
- R4. Hard stop: daemon never triggers extra-use quota — heartbeat.sh gates POST when budget is exhausted
- R5. Daily reset: budget counter resets at the start of each local-timezone day
- R6. Budget state persists across restarts via state.json
- R7. Graceful handling of missing budget fields (backward compatibility with existing instances)

## Scope Boundaries

- **Not in scope:** Interactive session detection (deferred — the budget system works without it, and detection is underspecified)
- **Not in scope:** Accurate token counting (no upstream API exists — estimation via chars/4 is the best available)
- **Not in scope:** Cross-session awareness (daemon cannot know what an interactive session consumed)
- **Not in scope:** New config file format (configuration lives in state.json with defaults from bootstrap)
- **Not in scope:** Test infrastructure (todo #004 tracks this separately)

## Context & Research

### Relevant Code and Patterns

- `daemon/scripts/heartbeat.sh` — scheduler-triggered heartbeat; budget gate inserts between lock acquisition (line 79) and tmux check (line 84)
- `daemon/scripts/bootstrap.sh` — creates initial state.json (lines 170-178); needs new budget fields
- `daemon/templates/CLAUDE.md.template` — agent instructions; needs Usage Budget Protocol section
- `daemon/mcp/session-control/server.ts` — existing MCP tool pattern; add `get_budget_status` tool
- `daemon/scripts/inject-prompt.sh` — has jq-or-python3 fallback pattern (lines 23-33) to follow for JSON parsing
- `.clawdkit/state.json` — free-form JSON, single writer (agent), read by shell scripts

### Institutional Learnings

- **Over-engineering trap** — keep budget management minimal: a few fields in state.json, a check at heartbeat start, a mode flag. No separate services or databases.
- **Token-efficient file operations** — use cp/Edit over Write when possible to reduce daemon token consumption under budget.
- **macOS CLI gotchas** — `date` differences between BSD and GNU. Use POSIX-compatible date commands. Local timezone via `date +%Y-%m-%d` (no `-d` flag).

## Key Technical Decisions

- **Config in state.json, not a separate file**: Budget configuration (max_daily_tokens, low_fuel_threshold_pct) lives alongside budget state in state.json. Bootstrap.sh sets defaults. The agent reads them on startup. The shell script reads them for the coarse gate. This avoids adding a new file format and keeps the single-file pattern.
- **Two-layer gate (shell + agent)**: heartbeat.sh does a coarse binary check (budget exhausted? skip POST entirely). The agent does the fine-grained check (approaching cap? enter low-fuel mode). This prevents waking the agent at all when the budget is gone, saving the most tokens.
- **Fail-open on parse errors**: If heartbeat.sh can't read state.json (missing, corrupt, no jq), it proceeds with the POST. A missed budget check is better than a missed heartbeat — the budget is an estimate anyway.
- **Local timezone for daily reset**: `date +%Y-%m-%d` (system local time) defines when the budget resets. The daemon runs on the user's machine, so local midnight is the natural boundary.
- **jq with python3 fallback**: Follow the existing `inject-prompt.sh` pattern. If neither is available, fail-open (proceed with POST, log warning).
- **Inbound messages at budget cap**: When budget is exhausted via inbound messages in low-fuel mode, the agent should process the current message, then note in its response that the budget is exhausted and recommend using an interactive session. It should not refuse to respond mid-conversation.

## Open Questions

### Resolved During Planning

- **Where does config live?** In state.json. Bootstrap sets defaults, agent reads/maintains them. No new file.
- **Interactive session detection?** Deferred. The budget system is valuable without it. Detection has too many ambiguities (false positives from pgrep, unclear throttle semantics).
- **What happens when inbound messages push past 100%?** Agent processes current message, warns the user, then skips further proactive work. Inbound messages are never hard-refused — the daemon should always respond when spoken to.
- **jq hard dependency?** No. Follow existing jq-or-python3 fallback. Fail-open if neither available.
- **Timezone for daily reset?** Local timezone. The daemon runs on the user's machine.
- **Atomic writes to state.json?** Not enforced at the agent level (Claude Code's Write tool isn't atomic). heartbeat.sh treats jq parse failure as fail-open.

### Deferred to Implementation

- Exact chars-to-tokens ratio tuning (start with chars/4, may need adjustment after real-world validation)
- Whether `budget_mode` should be a derived value (computed from estimate vs threshold) or a stored field (written by agent) — stored is simpler for shell reads but can go stale
- Exact wording of low-fuel and exhausted log messages

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification.*

```
                     Heartbeat Cycle
                     ===============

  launchd/systemd timer
        |
        v
  heartbeat.sh
        |
        +-- acquire lock
        |
        +-- read state.json budget fields (jq/python3)
        |       |
        |       +-- budget_mode == "exhausted" OR
        |       |   daily_token_estimate >= max_daily_tokens?
        |       |       |
        |       |      YES --> log "budget exhausted, skipping" --> exit 0
        |       |       |
        |       |      NO --> continue
        |       |
        |       +-- jq/python3 unavailable? --> log warning, continue (fail-open)
        |
        +-- check tmux session alive
        |
        +-- POST heartbeat to MCP server
        |
        v
  Agent receives heartbeat
        |
        +-- read state.json
        |
        +-- is daily_reset_date != today?
        |       |
        |      YES --> reset daily_token_estimate = 0
        |       |      set budget_mode = "normal"
        |       |      update daily_reset_date
        |       |
        |      NO --> continue
        |
        +-- check budget_mode
        |       |
        |       +-- "normal" AND estimate >= 80% of max
        |       |       --> set budget_mode = "low-fuel"
        |       |       --> log "entering low-fuel mode"
        |       |
        |       +-- "low-fuel" AND estimate >= 100% of max
        |       |       --> set budget_mode = "exhausted"
        |       |       --> log "budget exhausted"
        |       |       --> compact context and stop
        |       |
        |       +-- "normal" --> process heartbeat tasks normally
        |       |
        |       +-- "low-fuel" --> skip proactive tasks, log what was skipped
        |
        +-- after work: estimate tokens used, add to daily_token_estimate
        |
        +-- write updated state.json
```

## Implementation Units

- [ ] **Unit 1: Extend state.json schema with budget fields**

  **Goal:** Add budget tracking and configuration fields to the initial state.json created by bootstrap, and ensure the agent handles missing fields gracefully on existing instances.

  **Requirements:** R1, R2, R5, R6, R7

  **Dependencies:** None

  **Files:**
  - Modify: `daemon/scripts/bootstrap.sh`

  **Approach:**
  - Extend the `cat > state.json` block (lines 170-178) to include new fields: `daily_token_estimate` (0), `daily_reset_date` (null), `max_daily_tokens` (150000), `low_fuel_threshold_pct` (80), `budget_mode` ("normal"), `estimated_daily_quota` (500000), `daemon_daily_budget_pct` (30)
  - `max_daily_tokens` = `estimated_daily_quota` * `daemon_daily_budget_pct` / 100, but since this is shell and the values are static defaults, hardcode 150000 directly
  - Existing instances won't have these fields — Unit 3 (CLAUDE.md) will instruct the agent to initialize missing fields on startup

  **Patterns to follow:**
  - Existing state.json creation pattern in `bootstrap.sh` lines 170-178

  **Test expectation:** none — pure config scaffolding, verified by running bootstrap and inspecting output

  **Verification:**
  - After `bootstrap.sh --agent-name test ...`, the generated `state.json` contains all budget fields with sensible defaults
  - `jq .max_daily_tokens state.json` returns 150000

- [ ] **Unit 2: Add shell-side budget gate to heartbeat.sh**

  **Goal:** heartbeat.sh reads budget fields from state.json and skips the heartbeat POST when the daily budget is exhausted, preventing the agent from waking up at all.

  **Requirements:** R4, R7

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `daemon/scripts/heartbeat.sh`

  **Approach:**
  - Add a JSON-reading helper function using the jq-or-python3 fallback pattern from `inject-prompt.sh`
  - After lock acquisition (line 79) and before tmux check (line 84), read `state.json` and extract `budget_mode` and `daily_token_estimate` and `max_daily_tokens`
  - If `budget_mode` == "exhausted" OR `daily_token_estimate` >= `max_daily_tokens`, log and exit 0
  - If JSON parsing fails (no jq, no python3, malformed file), log a warning and proceed with POST (fail-open)
  - If budget fields are missing (existing instance not yet upgraded), proceed with POST (fail-open)
  - Also check for daily reset at the shell level: if `daily_reset_date` != today's date (`date +%Y-%m-%d`), do NOT skip — let the agent handle the reset

  **Patterns to follow:**
  - `inject-prompt.sh` lines 23-33 for jq/python3 fallback
  - Existing pre-flight checks in `heartbeat.sh` (tmux session check, lock check)
  - POSIX shell conventions: `printf` not `echo`, quote all variables, `set -e`

  **Test scenarios:**
  - Happy path: state.json has budget_mode "normal" and estimate below max → heartbeat proceeds normally
  - Happy path: state.json has budget_mode "exhausted" → heartbeat skips POST, logs reason
  - Happy path: daily_token_estimate >= max_daily_tokens but budget_mode not yet updated → heartbeat skips POST
  - Edge case: state.json missing budget fields entirely (pre-upgrade instance) → heartbeat proceeds (fail-open)
  - Edge case: state.json is malformed/corrupt → heartbeat proceeds (fail-open), logs warning
  - Edge case: jq and python3 both unavailable → heartbeat proceeds (fail-open), logs warning
  - Edge case: daily_reset_date is yesterday but budget_mode is "exhausted" → heartbeat proceeds (agent will handle reset)
  - Error path: state.json file does not exist → heartbeat proceeds (fail-open)

  **Verification:**
  - With budget_mode "exhausted" in state.json, heartbeat.sh exits without making an HTTP request
  - With budget_mode "normal", heartbeat.sh behaves identically to current behavior
  - With no budget fields in state.json, heartbeat.sh behaves identically to current behavior

- [ ] **Unit 3: Add Usage Budget Protocol to CLAUDE.md template**

  **Goal:** Instruct the daemon agent on budget tracking, low-fuel mode behavior, daily reset, and token estimation.

  **Requirements:** R1, R2, R3, R5, R6, R7

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `daemon/templates/CLAUDE.md.template`

  **Approach:**
  - Add a "Usage Budget Protocol" section between "Heartbeat Protocol" and "Messaging Protocol"
  - Define the three budget modes: normal, low-fuel, exhausted
  - Instruct the agent to:
    - On each heartbeat, check `daily_reset_date` vs today — if different, reset `daily_token_estimate` to 0, set `budget_mode` to "normal", update `daily_reset_date`
    - On each heartbeat, check `daily_token_estimate` against thresholds — if >= `low_fuel_threshold_pct`% of `max_daily_tokens`, enter low-fuel mode
    - In low-fuel mode: skip proactive heartbeat tasks, log what was skipped, still process inbound messages
    - When budget_mode is "exhausted": log, compact context, and wait for daily reset
    - After each task/conversation: estimate tokens used (input + output chars / 4), add to `daily_token_estimate`, write state.json
    - On startup, if budget fields are missing in state.json, initialize them with defaults
  - Update the Heartbeat Protocol section to reference the budget check as a prerequisite step
  - Update the Messaging Protocol section to note that inbound messages are always processed regardless of budget mode, but the agent should warn the user when budget is exhausted

  **Patterns to follow:**
  - Existing protocol sections in CLAUDE.md.template (Heartbeat Protocol, Messaging Protocol)
  - Template variable style: `{{INSTANCE_DIR}}`, `{{AGENT_NAME}}`

  **Test scenarios:**
  - Happy path: agent on normal heartbeat reads budget < 80% → processes tasks normally, updates estimate after
  - Happy path: agent reads budget at 82% → enters low-fuel mode, skips proactive tasks, logs what was skipped
  - Happy path: agent reads budget at 100% → enters exhausted mode, compacts context
  - Happy path: new day detected → resets counter and mode, proceeds normally
  - Edge case: state.json missing budget fields on first heartbeat after upgrade → agent initializes defaults
  - Edge case: inbound message arrives during exhausted mode → agent responds, warns about budget, does not do additional work
  - Integration: agent writes updated daily_token_estimate → next heartbeat.sh invocation reads it correctly

  **Verification:**
  - Stamped CLAUDE.md contains Usage Budget Protocol section with all three modes documented
  - Agent behavior described is internally consistent with heartbeat.sh gate logic

- [ ] **Unit 4: Add get_budget_status tool to session-control MCP server**

  **Goal:** Let the agent (or external callers) query current budget status programmatically via MCP tool.

  **Requirements:** R1

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `daemon/mcp/session-control/server.ts`

  **Approach:**
  - Add a `get_budget_status` tool following the existing tool registration pattern (clear_context, compact_context, restart_daemon)
  - Tool reads state.json, extracts budget fields, returns them as formatted text
  - No parameters needed — it's a read-only status query
  - Returns: budget_mode, daily_token_estimate, max_daily_tokens, percentage used, low_fuel_threshold_pct, daily_reset_date
  - Uses the existing `INSTANCE_DIR` env var to locate state.json
  - If budget fields are missing, return a message indicating the instance hasn't been upgraded

  **Patterns to follow:**
  - `clear_context` / `compact_context` / `restart_daemon` tool registration in `server.ts`
  - `readFile` + `JSON.parse` pattern from `restart_daemon` handler
  - Error handling pattern: return `{ isError: true, content: [...] }` on failure

  **Test scenarios:**
  - Happy path: state.json has all budget fields → returns formatted budget status with mode, estimate, max, percentage
  - Edge case: state.json missing budget fields → returns "budget tracking not configured" message
  - Error path: state.json unreadable → returns error with descriptive message
  - Error path: INSTANCE_DIR not set → returns error (same pattern as restart_daemon)

  **Verification:**
  - Tool appears in MCP tool list
  - Calling the tool returns current budget information from state.json
  - Calling the tool does not modify state.json

- [ ] **Unit 5: Extend clawdkit.sh health check with budget status**

  **Goal:** Surface budget information in `clawdkit.sh status` / `do_health()` output so users can check budget from the command line.

  **Requirements:** R1

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `daemon/scripts/clawdkit.sh`

  **Approach:**
  - In `do_health()`, after reading state.json for existing fields, also extract and display budget fields
  - Show: budget_mode, daily_token_estimate / max_daily_tokens (percentage), daily_reset_date
  - Use the same jq-or-python3 fallback as heartbeat.sh (or share the helper)
  - If budget fields are absent, show "budget tracking: not configured"

  **Patterns to follow:**
  - Existing `do_health()` function in `clawdkit.sh`
  - JSON reading pattern from Unit 2

  **Test scenarios:**
  - Happy path: status command shows budget_mode "normal", usage at 45%, reset date today
  - Edge case: budget fields missing → shows "budget tracking: not configured"
  - Edge case: jq unavailable → shows budget status as "unknown (jq not available)"

  **Verification:**
  - `clawdkit.sh --instance jarvis status` displays budget information alongside existing health output

- [ ] **Unit 6: Update existing jarvis instance state.json**

  **Goal:** Add budget fields to the running jarvis instance so it starts tracking immediately without requiring a full re-bootstrap.

  **Requirements:** R6

  **Dependencies:** Units 1-3

  **Files:**
  - Modify: Instance file `~/.clawdcode/jarvis/.clawdkit/state.json` (not in repo — runtime only)
  - Modify: Instance file `~/.clawdcode/jarvis/CLAUDE.md` (stamp from updated template)

  **Approach:**
  - Read current state.json, merge in the new budget fields with defaults
  - Re-stamp CLAUDE.md from the updated template (re-run the sed pipeline from bootstrap.sh or manually apply the Usage Budget Protocol section)
  - Restart the daemon to pick up the new CLAUDE.md

  **Test expectation:** none — operational deployment step

  **Verification:**
  - `jq .budget_mode state.json` returns "normal"
  - Next heartbeat cycle, agent logs budget tracking activity
  - `clawdkit.sh --instance jarvis status` shows budget information

## System-Wide Impact

- **Interaction graph:** heartbeat.sh now reads state.json (new dependency). The agent writes budget fields to state.json on each task completion. The session-control MCP server reads state.json for the new get_budget_status tool. No new write-write contention — agent remains the single writer.
- **Error propagation:** All error paths fail-open. A broken budget gate means the heartbeat fires normally (pre-upgrade behavior). A broken token estimate means the daemon runs normally (wasteful but not dangerous).
- **State lifecycle risks:** state.json is read by heartbeat.sh and written by the agent. If the agent is mid-write when heartbeat.sh reads, jq may see corrupt JSON. Mitigation: heartbeat.sh treats parse failures as fail-open. The budget is an estimate — one missed gate check is not critical.
- **Unchanged invariants:** Heartbeat scheduling frequency unchanged. MCP server startup unchanged. Channel message handling unchanged (inbound messages always processed). Lock acquisition logic unchanged.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Token estimation drift (chars/4 is rough) | Conservative threshold (80% low-fuel). Estimation accuracy tracked over real heartbeat cycles. Easy to tune the ratio later. |
| jq not available on fresh macOS | Follow existing jq-or-python3 fallback pattern. Fail-open if neither available. |
| Existing instances lack budget fields | Agent initializes missing fields on first heartbeat. heartbeat.sh fails-open on missing fields. |
| state.json partial write during read | heartbeat.sh treats jq parse failure as fail-open. Budget is an estimate — one missed check is acceptable. |
| Budget too conservative, daemon goes idle prematurely | Defaults are tunable (daemon_daily_budget_pct, estimated_daily_quota). Can be adjusted per-instance by editing state.json. |

## Sources & References

- Related todo: `.context/compound-engineering/todos/013-pending-p1-usage-limit-management.md`
- Related code: `daemon/scripts/heartbeat.sh`, `daemon/templates/CLAUDE.md.template`, `daemon/scripts/bootstrap.sh`, `daemon/mcp/session-control/server.ts`
- Design proposal: todo #013 design section (drafted 2026-04-05)
