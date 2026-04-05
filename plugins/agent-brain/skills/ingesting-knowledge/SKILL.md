---
name: ingesting-knowledge
description: Processes episode notes from the agent brain Inbox into structured memory and knowledge. Use when the Inbox has accumulated episodes to review, or on a regular cadence.
---

# Ingesting Knowledge

## Purpose

Process raw episode notes from `02_Inbox/` into the agent brain's structured memory system. This is the second phase of the compounding loop — capture happens automatically during work, ingestion happens deliberately as a batch.

This skill works against any agent brain vault regardless of where it lives — standalone `~/agent_brain/`, or `brain/` inside a ClawdKit monorepo.

## Outcomes

### Inbox Processing

Every episode note in `02_Inbox/` is read, analyzed, and routed:

1. **Read** the episode note
2. **Decide** its disposition:
   - **Promote to interaction log** → Write to `03_Memory/interactions/` if the episode records a significant interaction worth preserving
   - **Extract a lesson** → Write to `03_Memory/lessons/` if a reusable insight emerges
   - **Promote to pattern** → Write to `06_Knowledge/patterns/` if the episode validates an existing lesson into a broader pattern
   - **Promote to procedure** → Write to `06_Knowledge/procedures/` if a pattern has solidified into a repeatable workflow
   - **Add to facts** → Write to `06_Knowledge/facts/` if new factual knowledge was discovered
   - **Discard** → Delete the episode if it contains no actionable signal
3. **Write a reflection** → For episodes with rich signals, write a reflection to `03_Memory/reflections/` before extracting lessons
4. **Remove from Inbox** → Delete or move the processed episode note
5. **Commit** with descriptive message: `ingest: <summary of what was learned>`

### Lesson Confidence Updates

When processing episodes, check existing lessons in `03_Memory/lessons/`:
- If a new episode reinforces an existing lesson, update its confidence level
- If a lesson appears across 3+ episodes, consider promoting to a pattern in `06_Knowledge/patterns/`
- If a lesson is contradicted by new evidence, update or archive it

### Pattern Detection

Look across multiple episodes for recurring themes:
- Similar mistakes repeated → Extract a lesson about the root cause
- Similar successful strategies → Extract a procedure
- Domain-specific knowledge accumulating → Create or update a knowledge note in `06_Knowledge/facts/`

### Pruning

During ingestion, also review existing knowledge for staleness:
- Lessons with `confidence: single observation` that are 30+ days old with no reinforcement → Archive
- Patterns that haven't been referenced or reinforced → Flag for review
- Procedures that have been superseded → Archive with a note about the replacement

## Context Gathering

Before processing, read:
- `00_Meta/conventions.md` — Tagging and naming rules
- All files in `02_Inbox/` — The episodes to process
- Recent files in `03_Memory/lessons/` — Existing lessons to cross-reference
- Recent files in `06_Knowledge/patterns/` — Existing patterns to check for promotion

## Edge Cases

- **Empty Inbox**: If no episodes to process, report "Inbox empty — nothing to ingest" and exit.
- **Ambiguous episodes**: If an episode's signal is unclear, leave it in the Inbox with a comment asking for clarification from the next capture.
- **Conflicting lessons**: If a new episode contradicts an existing lesson, don't delete the lesson. Instead, update it with the conflicting evidence and downgrade its confidence.
- **Bulk processing**: If the Inbox has 10+ episodes, process them chronologically to preserve the narrative arc.

## Quality Criteria

The ingestion is complete when:

- [ ] `02_Inbox/` contains no unprocessed episode notes
- [ ] Every promoted note has valid frontmatter with appropriate tags
- [ ] New lessons link back to their source episodes
- [ ] Existing lessons have updated confidence levels where reinforced
- [ ] Patterns promoted from lessons link to their evidence
- [ ] All changes are committed with descriptive messages
- [ ] `00_Meta/changelog.md` is updated if any structural changes were made
