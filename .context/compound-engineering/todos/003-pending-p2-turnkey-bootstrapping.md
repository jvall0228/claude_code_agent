---
status: pending
priority: p2
issue_id: "003"
tags: [dx, bootstrap, onboarding]
dependencies: []
assignee: jarvis
---

# Make bootstrapping more turnkey

## Problem Statement

The bootstrap process requires multiple manual steps — running the script, copying channel configs, installing plugins, editing persona files. Should be a single command or guided flow that gets you from zero to running daemon.

## Findings

- `bootstrap.sh` handles most of the heavy lifting but still needs manual pre-steps
- Channel plugin installation is a separate step
- Persona files need manual customization
- Scheduler install is automated but sometimes fails silently

## Acceptance Criteria

- [ ] Single command gets a new user from clone to running daemon
- [ ] All dependencies checked and installed automatically
- [ ] Channel setup integrated into bootstrap flow
- [ ] Sensible defaults that work without customization

## Notes

- Related to #005 (Telegram in bootstrap) and #006 (guided persona onboarding)
