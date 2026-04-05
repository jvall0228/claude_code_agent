# Agent Brain Conventions

When working with an agent brain vault, follow these rules:

## Bootstrap First

Read the bootstrap sequence before any operation:
1. `brain/CONTEXT.md` (or vault root `CONTEXT.md` for standalone vaults)
2. `brain/prompts/SOUL.md`
3. `brain/prompts/IDENTITY.md`
4. `brain/prompts/USER.md`
5. `brain/prompts/TOOLS.md`

## Frontmatter Required

Every markdown note must have YAML frontmatter with `title`, `tags`, and `updated`. Tags use slash-delimited namespaces: `audience/*`, `type/*`, `topic/*`, `workflow/*`, `status/*`, `memory/*`.

## Direct-Write Model

Write files directly to the correct directory. There is no Inbox-first rule — the agent is both author and organizer. Use `02_Inbox/` only for genuinely unclassified content.

## Canonical Notes

Files tagged `workflow/canonical` define vault structure. Modify them only for deliberate structural changes. Log changes in `00_Meta/changelog.md`.

## Memory Classification

Tag notes with `memory/*` to classify by cognitive function:
- `memory/episodic` — derived from specific interactions or experiences
- `memory/semantic` — general knowledge, patterns, facts
- `memory/procedural` — how-to knowledge, step-by-step workflows

## Naming

Use kebab-case for filenames. Exceptions: root entrypoints (CONTEXT.md, CLAUDE.md, AGENTS.md, README.md) and persona files (SOUL.md, IDENTITY.md, USER.md, TOOLS.md).

## Honesty

Record failures alongside successes. Never fabricate logs or learnings. Rate lesson confidence honestly.
