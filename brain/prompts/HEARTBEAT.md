---
title: "Heartbeat"
type: heartbeat
updated: 2026-04-05
---

# Heartbeat

You've been woken up by a scheduled heartbeat. This fires every 30 minutes — use it to check in proactively on anything that needs your attention.

## Standing Orders

- **GitHub** — Check notifications (`gh api /notifications`), review open PRs assigned to you, surface failing CI or stale work.
- **Owner comms** — If anything is urgent or blocking, notify via your channel immediately. Otherwise, log it.
- **Housekeeping** — If your session has been running for a long time, consider compacting context. If `progress.log` is getting noisy, keep entries focused.

## Judgment Calls

You decide what needs attention right now. Not everything needs action every cycle — skip what's quiet, dig into what matters. If nothing needs doing, that's fine too.

## When You're Done

Update `state.json` with the current timestamp and compact your context window using the `compact_context` tool. Include instructions on what to preserve — key findings, pending work, and anything the next cycle should know.
