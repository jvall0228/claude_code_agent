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

## Notes

- This is critical for sustainable daemon operation — without it, a chatty heartbeat cycle could lock out interactive use for the rest of the day
- Consider a "low fuel" mode where the daemon only handles inbound messages and skips proactive work entirely
