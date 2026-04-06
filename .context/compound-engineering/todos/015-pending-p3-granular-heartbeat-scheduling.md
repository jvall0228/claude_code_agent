---
status: pending
priority: p3
issue_id: "015"
tags: [heartbeat, scheduler, architecture]
dependencies: []
assignee: jarvis
---

# Granular heartbeat scheduling

## Problem Statement

The heartbeat scheduler (launchd/systemd) fires every 30 minutes. The interval gate in `heartbeat.sh` can slow heartbeats down but can't speed them up. There's no way to trigger a heartbeat on demand or set sub-30-minute intervals.

## Options to Explore

- **Crank the scheduler tick** — Set launchd/systemd to 1-5 minute intervals, let `heartbeat.sh`'s interval gate do all throttling. No-ops are cheap (script exits in milliseconds). Simplest path.
- **On-demand trigger tool** — Add a `trigger_heartbeat` MCP tool that POSTs directly to the heartbeat HTTP endpoint. Agent can fire a heartbeat whenever it wants, independent of the scheduler.
- **Hybrid** — Slow background tick (e.g., 15min) as safety net + on-demand triggers for time-sensitive work.
- **Event-driven** — Replace polling with filesystem watchers or push-based wakeups. More complex, may be better suited to the post-#007 architecture.

## Considerations

- launchd/systemd support minute-level granularity — technical floor is 1 minute
- Frequent no-op ticks are cheap but noisy in logs (mitigated by interval gate skipping silently)
- On-demand triggers are orthogonal to the scheduler — both can coexist
- #007 (process management architecture) and #002 (multi-thread) may reshape how heartbeats work entirely

## Acceptance Criteria

- [ ] Agent can receive heartbeats at intervals shorter than 30 minutes
- [ ] Agent can trigger an immediate heartbeat on demand
- [ ] Scheduler tick rate is configurable per instance
- [ ] No regression in battery/resource usage for idle instances
