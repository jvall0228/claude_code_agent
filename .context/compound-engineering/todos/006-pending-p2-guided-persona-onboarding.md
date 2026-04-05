---
status: pending
priority: p2
issue_id: "006"
tags: [onboarding, brain, persona, dx]
dependencies: ["003"]
assignee: jarvis
---

# Guided persona onboarding conversation

## Problem Statement

Setting up an agent's persona (SOUL, IDENTITY, USER, TOOLS) requires manually editing markdown files. Should be a guided interactive conversation that asks questions and generates the persona files.

## Acceptance Criteria

- [ ] Interactive flow asks about agent purpose, character, owner preferences
- [ ] Generates SOUL.md, IDENTITY.md, USER.md, TOOLS.md from responses
- [ ] Integrates with bootstrap or available as standalone skill
- [ ] Produces good defaults that can be refined later
