---
name: scaffolding-agent-brain
description: Scaffolds an agent-owned knowledge vault with persistent memory, identity, and self-improvement loop. Use when asked to create or set up an agent brain. In ClawdKit projects, the brain lives at brain/ inside the monorepo.
---

# Scaffolding an Agent Brain

## Purpose

Create a Git-tracked, Markdown-first knowledge vault owned by a Claude agent. Unlike a shared brain (where a human owns the vault and agents assist), the agent brain inverts ownership — the agent is the primary author, organizer, and consumer. The vault provides persistent memory, identity, and a reflection-driven self-improvement loop across sessions.

In ClawdKit projects, the brain is not a standalone repo — it lives at `brain/` inside the ClawdKit monorepo. Read `brain/CONTEXT.md` as the bootstrap entrypoint.

## Outcomes

### Vault Initialization

In a ClawdKit project, the brain is scaffolded at `brain/` within the monorepo. For standalone use, the vault is created at the user's chosen location (default: `~/agent_brain`). Either way, the structure is:

```
brain/                        # or agent_brain/ for standalone
├── 00_Meta/
│   ├── README.md
│   ├── conventions.md
│   ├── index.md
│   └── changelog.md
├── prompts/
│   ├── SOUL.md               # Core values and guiding principles
│   ├── IDENTITY.md           # Who the agent is: purpose, capabilities, boundaries
│   ├── USER.md               # Who the agent serves and their preferences
│   └── TOOLS.md              # Available tools, MCP servers, and APIs
├── 02_Inbox/
│   └── README.md
├── 03_Memory/
│   ├── README.md
│   ├── interactions/
│   ├── reflections/
│   └── lessons/
├── 04_Goals/
│   └── README.md
├── 05_Domains/
│   └── README.md
├── 06_Knowledge/
│   ├── README.md
│   ├── patterns/
│   ├── facts/
│   └── procedures/
├── 07_Archives/
│   └── README.md
├── 08_Assets/
│   └── README.md
├── 09_Templates/
│   ├── README.md
│   ├── template-interaction-log.md
│   ├── template-reflection.md
│   ├── template-lesson.md
│   ├── template-decision-record.md
│   ├── template-goal.md
│   ├── template-domain.md
│   ├── template-knowledge.md
│   ├── template-pattern.md
│   └── template-procedure.md
├── 10_Integrations/
│   └── README.md
├── CONTEXT.md
└── README.md
```

For ClawdKit projects, `CONTEXT.md` and `README.md` live at `brain/CONTEXT.md` and `brain/README.md`. The root-level `CLAUDE.md` and `AGENTS.md` in the monorepo already point agents to the repo entrypoint; there are no symlinks needed inside `brain/`.

For standalone vaults, add symlinks at the vault root:
- `CLAUDE.md → CONTEXT.md`
- `AGENTS.md → CONTEXT.md`

Directories use numbered prefixes for deterministic sort order. Each directory has a README explaining its purpose.

### Key Differences from Human Shared Brain

| Aspect | Human Shared Brain | Agent Brain |
|--------|-------------------|-------------|
| Owner | Human (agent assists) | Agent (human oversees) |
| Write model | Inbox-first, human triages | Direct-write, agent self-organizes |
| Identity | Name, preferences, locale | SOUL, IDENTITY, USER, TOOLS |
| Memory | External (human remembers) | Vault IS the memory |
| Growth | Human adds knowledge | Agent accumulates via reflection cycle |
| Change control | PR for canonical notes | Agent self-modifies; human audits via git |

### Directory Semantics (PARA Adapted for Agent Cognition)

| Directory | Human Equivalent | Agent Purpose |
|-----------|-----------------|---------------|
| `prompts/` | `01_Profile/` | Agent persona: SOUL, IDENTITY, USER, TOOLS |
| `03_Memory/` | `03_Journal/` | Episodic memory: interaction logs, reflections, lessons |
| `04_Goals/` | `04_Projects/` | Working memory: active objectives with defined outcomes |
| `05_Domains/` | `05_Areas/` | Ongoing areas of competence and responsibility |
| `06_Knowledge/` | `06_Resources/` | Semantic memory: validated patterns, facts, procedures |
| `10_Integrations/` | `10_Agents/` | External system connections (MCP servers, APIs, tools) |

### Bootstrap Sequence

The agent reads these files in order to reconstitute its identity at session start:

1. **brain/CONTEXT.md** — Vault purpose, structure, rules. This is the entrypoint.
2. **brain/prompts/SOUL.md** — Core values, guiding principles, and what the agent stands for.
3. **brain/prompts/IDENTITY.md** — Who the agent is: mission, capabilities, and hard limits.
4. **brain/prompts/USER.md** — Who the agent serves and how to tailor communication to them.
5. **brain/prompts/TOOLS.md** — Available tools, MCP servers, APIs, and known limitations.

After reading all five, the agent has enough context to begin work. For richer context:

6. **00_Meta/conventions.md** — Naming, tagging, and file rules.
7. **00_Meta/index.md** — Full vault map.
8. Latest entries in `03_Memory/reflections/` — Recent learnings.
9. Active files in `04_Goals/` — Current objectives.

### Persona File Configuration

The `brain/prompts/` directory defines the agent's operational persona. During setup, configure:

**SOUL.md** — the agent's core values and what it stands for:
- Foundational principles (honesty, precision, compounding knowledge, etc.)
- What the agent cares about beyond task completion
- How it resolves ethical or priority conflicts

**IDENTITY.md** — who the agent is in operational terms:
- Mission statement
- Core functions (persistent memory, self-improvement, context provision, knowledge management, decision support)
- Capabilities: reasoning, code generation, synthesis, planning, pattern recognition
- Hard limits: never expose secrets, never fabricate logs, never push without instruction, never modify outside vault without instruction

**USER.md** — who the agent serves:
- Human owner name or identifier
- Link to human's shared brain bootstrap sequence (if it exists)
- Communication preferences and context about the human's work
- Relationship model: human is authority, agent operates within boundaries, human audits via git

**TOOLS.md** — what the agent can reach:
- Available MCP servers and their capabilities
- APIs and credentials (references only — never secrets in vault files)
- File system access scope
- Known limitations and gaps

### Memory System

The agent's memory is organized into three types:

| Type | Location | Purpose |
|------|----------|---------|
| Episodic | `03_Memory/` | Interaction logs, reflections, lessons learned |
| Semantic | `06_Knowledge/` | Accumulated facts, patterns, procedures |
| Working | `04_Goals/` | Current objectives and active task context |

### Reflection Cycle

The agent improves through a reflection loop:

```
Interaction → Log (03_Memory/interactions/)
    → Reflect (03_Memory/reflections/)
        → Extract Lesson (03_Memory/lessons/)
            → [If recurring] Promote to Pattern (06_Knowledge/patterns/)
                → [If repeatable] Promote to Procedure (06_Knowledge/procedures/)
```

Not every interaction triggers the full cycle. The agent judges significance:
- Routine, successful interactions: skip logging
- Notable outcomes (good or bad): log + reflect
- Repeated themes across reflections: extract lesson
- Validated lessons across contexts: promote to pattern
- Patterns that solidify into workflows: promote to procedure

### Self-Modification Rules

The agent brain uses direct-write (no Inbox-first rule):

**Write rules:**
- Write files directly to the correct directory
- Every file must have valid YAML frontmatter: `title`, `tags`, `updated`
- Follow conventions in `00_Meta/conventions.md`
- Use templates from `09_Templates/` for structured notes

**Protection rules:**
- Files tagged `workflow/canonical` define vault structure
- Modify canonical files only for deliberate structural changes
- Log structural changes in `00_Meta/changelog.md`
- Human owner audits all changes via `git log`

### Frontmatter Convention

Every markdown note must include:

```yaml
---
title: "Note Title"
tags:
  - namespace/value
updated: YYYY-MM-DD
---
```

Tag namespaces:

| Namespace | Purpose | Values |
|-----------|---------|--------|
| `audience/*` | Who the note is for | `agent`, `human` |
| `type/*` | Kind of content | `meta`, `interaction`, `reflection`, `lesson`, `pattern`, `procedure`, `decision`, `goal`, `domain`, `knowledge` |
| `topic/*` | Subject matter | Free-form |
| `workflow/*` | Lifecycle stage | `canonical`, `draft`, `validated` |
| `status/*` | Actionability | `active`, `completed`, `archived` |
| `memory/*` | Memory classification | `episodic`, `semantic`, `procedural` |

The `memory/*` namespace is unique to the agent brain — it classifies notes by cognitive function.

### Templates

The `09_Templates/` directory contains 9 agent-specific templates:

- **template-interaction-log.md** — Record of a significant interaction (context, key exchanges, outcome, signals)
- **template-reflection.md** — Post-interaction analysis (what happened, what worked, what to improve, patterns noticed)
- **template-lesson.md** — Extracted reusable learning (insight, evidence, application, confidence level)
- **template-decision-record.md** — Decision with reasoning (context, options, decision, consequences)
- **template-goal.md** — Active objective (outcome, context, tasks, related domain)
- **template-domain.md** — Area of competence (scope, standard, current state, related goals)
- **template-knowledge.md** — Reference knowledge (summary, key points, sources)
- **template-pattern.md** — Recognized pattern (description, when to apply, when NOT to apply, evidence)
- **template-procedure.md** — Step-by-step workflow (purpose, steps, prerequisites, notes)

### Git Initialization

For standalone vaults, the vault is a Git repository for full audit trail:
- Initialize with `git init`
- Create `.gitignore` excluding `.DS_Store`, `TEMP_WORKING_DIR/`, `.obsidian/`, `.claude/`
- Make an initial commit with all scaffolded files

For ClawdKit projects, the brain lives inside an existing git repo — no separate init needed.

## Context Gathering

Before building, understand:

- **Location**: ClawdKit project (use `brain/`) or standalone (default: `~/agent_brain`)?
- **Agent purpose**: What the agent's primary role is (general assistant, domain specialist, daemon, etc.)
- **Human owner**: Username or identifier for the human who oversees this agent
- **Human shared brain**: Path to the human's shared brain (if one exists) for cross-referencing in USER.md
- **Tools available**: Which MCP servers, APIs, or tools the agent will have access to (for TOOLS.md)
- **Existing content**: Whether there are existing notes, auto-memory files, or knowledge to migrate

## Edge Cases

- **Existing directory**: If the target path already exists, confirm before overwriting. Offer to merge or backup.
- **No human shared brain**: If the owner has no shared brain, `USER.md` still documents the relationship but omits the cross-reference paths.
- **Minimal setup**: The minimum viable agent brain is: `CONTEXT.md`, `prompts/` (SOUL.md + IDENTITY.md), and `00_Meta/conventions.md`. Everything else can be added incrementally.
- **Multiple agents**: Each agent should have its own brain vault or brain/ directory. They can reference each other via `10_Integrations/`.
- **Migration from v1.0.0**: The old `01_Identity/` five-file structure (purpose.md, capabilities.md, boundaries.md, voice.md, owner.md) maps to the new four-file `prompts/` structure as follows: purpose + boundaries → IDENTITY.md; voice → SOUL.md; owner → USER.md; capabilities + tools → TOOLS.md.
- **Migration from auto-memory**: If the agent has existing Claude Code auto-memory (`~/.claude/projects/*/memory/`), migrate relevant content into `06_Knowledge/` or `03_Memory/lessons/`.

## Quality Criteria

The finished vault satisfies all of the following:

- [ ] Every directory has a README.md explaining its purpose
- [ ] `brain/CONTEXT.md` contains the bootstrap sequence with links to all four persona files
- [ ] All templates have valid frontmatter with `{{PLACEHOLDER}}` tokens
- [ ] `conventions.md` documents all tag namespaces including `memory/*`
- [ ] Persona files in `prompts/` are populated with real agent configuration (not placeholders)
- [ ] `USER.md` references the human owner and their shared brain (if it exists)
- [ ] Git is initialized (or brain is inside an existing git repo) with a clean initial commit
- [ ] For standalone vaults: `CLAUDE.md` and `AGENTS.md` symlinks point to `CONTEXT.md`
- [ ] `index.md` references all directories and key files
- [ ] No broken wikilinks in non-template files
