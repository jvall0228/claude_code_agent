---
status: pending
priority: p1
issue_id: "013"
tags: [daemon, limits, oauth, scheduling, cost]
dependencies: []
assignee: jarvis
---

# Graceful usage limit management for daemon agents

## Problem Statement

Daemon agents run on the OAuth plan which has daily and weekly token limits. Currently there is no awareness of quota consumption — the daemon will happily burn through tokens on heartbeat tasks and background work, leaving nothing for interactive sessions where the human actually needs it.

Interactive sessions should always have priority over daemon background work. Extra use quota (beyond the plan baseline) is reserved exclusively for ephemeral interactive sessions — daemons should never trigger it.

## Expected Behavior

1. **Quota awareness** — Daemon knows how much of the daily/weekly budget has been consumed (or can estimate it)
2. **Budget allocation** — Daemon operates within a reserved slice of the total quota, leaving headroom for interactive use
3. **Graceful degradation** — When approaching limits, daemon reduces activity: skip non-critical heartbeat tasks, defer low-priority work, log what was skipped
4. **Hard stop before overage** — Daemon must never trigger extra use quota. If remaining budget is too low, daemon goes idle and logs why
5. **Interactive priority** — If interactive sessions are active, daemon should further throttle or pause

## Design Questions

- How do we track token consumption? Is there an API for current usage, or do we estimate from conversation length?
- Should budget allocation be configurable per-instance (e.g., daemon gets 30% of daily quota)?
- How does the daemon detect that an interactive session is running?
- Should the daemon expose remaining budget as a status field in `state.json`?

## Design Proposal (drafted 2026-04-05 by jarvis)

### What's available today

- Claude Code CLI has `--max-budget-usd` for `--print` mode (caps a single non-interactive run). Not usable for long-running daemon sessions.
- No `claude usage` command or API endpoint to query remaining quota.
- No token count exposed via env vars, files, or MCP after each turn.
- Rate limit headers from the Anthropic API are not surfaced to the Claude Code session.

### Viable approach: local estimation + session budgeting

Since upstream doesn't expose quota data, the daemon must self-regulate with heuristics:

1. **Per-heartbeat token budget** — Configure a max token estimate per heartbeat cycle (e.g., 20k tokens). The daemon tracks approximate consumption by counting message length (input + output chars / 4 as rough token estimate) and stops work when the budget is hit.

2. **Daily session cap** — `state.json` gains fields: `daily_token_estimate`, `daily_reset_date`, `max_daily_tokens`. On each heartbeat, compare accumulated estimate to cap. If within 80%, enter low-fuel mode (inbound messages only). At 100%, go idle.

3. **Low-fuel mode** — Daemon skips all proactive heartbeat tasks. Only processes direct inbound messages via channel. Logs: "low-fuel mode — skipping heartbeat tasks, {estimated_remaining} tokens left."

4. **Interactive session detection** — Check for other `claude` processes running outside the daemon tmux session (e.g., `pgrep -f "claude" | grep -v <daemon_pid>`). If found, further throttle daemon activity.

5. **Configuration** — New fields in instance config or CLAUDE.md:
   ```
   daemon_daily_budget_pct: 30        # % of estimated daily quota
   estimated_daily_quota: 500000      # rough token limit for the plan
   low_fuel_threshold_pct: 80         # enter low-fuel at this %
   ```

### What's blocked on upstream

- **Accurate usage tracking** — Without an API, all numbers are estimates. If Claude Code or Anthropic ever expose a usage endpoint, swap the heuristic for real data.
- **Cross-session awareness** — The daemon can't know how many tokens an interactive session used. The daily budget split is a guess, not a measurement.

### Recommended first implementation

Build the local estimation + daily cap system. It's imperfect but functional — better to throttle conservatively with estimates than to have no throttling at all. Can be refined when upstream provides better signals.

### Acceptance criteria (updated)

- [ ] `state.json` schema extended with usage estimation fields
- [ ] Heartbeat logic checks budget before processing tasks
- [ ] Low-fuel mode implemented (skip proactive work, allow inbound messages)
- [ ] Interactive session detection (basic process check)
- [ ] Configuration documented in instance config
- [ ] Estimation accuracy validated against at least 3 real heartbeat cycles

## Notes

- This is critical for sustainable daemon operation — without it, a chatty heartbeat cycle could lock out interactive use for the rest of the day
- Consider a "low fuel" mode where the daemon only handles inbound messages and skips proactive work entirely
