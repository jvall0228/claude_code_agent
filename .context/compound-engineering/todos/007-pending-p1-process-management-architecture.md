---
status: pending
priority: p1
issue_id: "007"
tags: [architecture, process-management, foundational]
dependencies: []
---

# Explore alternatives to tmux for process management

## Problem Statement

tmux is the current process host for daemon instances. It works but is a blunt tool — no structured lifecycle management, no fault tolerance, and it constrains the multi-thread architecture (#002). This is foundational infrastructure that everything else builds on, so the decision should be made early before more features cement the tmux dependency.

## Options to Explore

- **Elixir/OTP** — Supervision trees, process registry, fault tolerance out of the box. Natural fit for the multi-thread model. Adds a runtime dependency.
- **systemd/launchd native** — Already used for scheduling. Could manage the processes directly instead of tmux. Limited cross-platform story.
- **Custom process supervisor** — Lightweight wrapper in Go/Rust/Node. Full control, no runtime dependency. More to build and maintain.
- **Container-based** — Each thread is a container. Heavy but isolated. Overkill for local use.
- **Keep tmux** — Known quantity, works today. Accept the limitations and build around them.

## Key Evaluation Criteria

- Process lifecycle (start, stop, restart, crash recovery)
- Multi-thread support (multiple Claude Code instances per agent)
- Cross-platform (macOS + Linux)
- Observability (status, logs, health)
- Complexity budget (how much infrastructure are we willing to maintain)
- Integration with Claude Code's interactive model

## Acceptance Criteria

- [ ] Evaluated at least 3 alternatives with pros/cons
- [ ] Prototype of the top candidate managing a Claude Code instance
- [ ] Decision documented with rationale
- [ ] Migration path from tmux outlined

## Notes

- This blocks or heavily influences #002 (multi-thread), #008 (native app), #009 (menu bar)
- Should be decided before building more features on top of tmux
- Elixir is the leading candidate given the owner's interest, but should be validated against alternatives
