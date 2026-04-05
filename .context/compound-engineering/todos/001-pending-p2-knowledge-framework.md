---
status: pending
priority: p2
issue_id: "001"
tags: [brain, knowledge, architecture]
dependencies: []
assignee: jaeson
---

# Flesh out the knowledge framework

## Problem Statement

The brain's knowledge system (`brain/knowledge/`) is scaffolded but not implemented. Owner has an architecture in mind but it needs a longer design discussion to scope out.

## Findings

- `brain/knowledge/README.md` exists as a stub
- The agent-brain plugin has `ingesting-knowledge` and `scaffolding-agent-brain` skills
- The scaffolding skill creates a PARA-adapted directory structure (Memory, Goals, Domains, Knowledge, etc.)
- No actual knowledge ingestion, retrieval, or compounding is wired up yet

## Technical Details

**Affected files:**
- `brain/knowledge/` — empty framework
- `plugins/agent-brain/skills/ingesting-knowledge/SKILL.md` — skill exists but no backing implementation
- `plugins/agent-brain/rules/compounding-knowledge.md` — reflection cycle rules defined but not enforced

## Acceptance Criteria

- [ ] Knowledge framework architecture documented
- [ ] Ingestion pipeline functional (interactions → reflections → lessons)
- [ ] Retrieval mechanism for relevant knowledge during tasks
- [ ] Integration with heartbeat cycle for periodic reflection

## Notes

- Owner has an architecture sketched out — needs a dedicated design session
- This is a longer discussion, not a quick implementation task
