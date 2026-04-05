---
status: pending
priority: p3
issue_id: "005"
tags: [bootstrap, telegram, channels]
dependencies: ["003"]
---

# Add Telegram to bootstrap step

## Problem Statement

Telegram channel setup is a manual post-bootstrap task. It should be part of the bootstrap flow so the agent is immediately reachable.

## Acceptance Criteria

- [ ] Bootstrap prompts for Telegram bot token
- [ ] `.mcp-telegram.json` generated automatically
- [ ] Plugin installation handled or verified during bootstrap
