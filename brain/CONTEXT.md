---
title: "Brain Context"
type: meta
updated: 2026-04-05
---

# ClawdKit Agent Brain

The persistent identity and knowledge framework for ClawdKit daemon agents.

## Purpose

This brain provides continuity across sessions. It defines who the agent is (SOUL), how it operates (IDENTITY, TOOLS), and who it serves (USER). These files are injected into every daemon session via SessionStart hooks — the agent always wakes up with full context.

## Bootstrap Sequence

SessionStart hooks inject all four persona files automatically. For manual bootstrap or context restoration:

1. **`prompts/SOUL.md`** — Core purpose, values, character. The agent's "why".
2. **`prompts/IDENTITY.md`** — Role, capabilities, operational context, constraints.
3. **`prompts/USER.md`** — Owner profile, preferences, working style, active context.
4. **`prompts/TOOLS.md`** — Available tools, MCP servers, state file locations, key commands.

After reading all four, the agent has full operational context.

## Persona Files

| File | Injected Via | Size Budget |
|------|-------------|-------------|
| `prompts/SOUL.md` | `inject-soul.sh` hook | ~500 tokens |
| `prompts/IDENTITY.md` | `inject-identity.sh` hook | ~600 tokens |
| `prompts/USER.md` | `inject-user.sh` hook | ~500 tokens |
| `prompts/TOOLS.md` | `inject-tools.sh` hook | ~400 tokens |

Total budget: ~2,000 tokens (well under the 50K char / ~10K token hook limit).

## Knowledge Framework

`knowledge/` is a stub in v1 — directory structure only. See `knowledge/README.md` for future plans.

## Structure

```
brain/
├── prompts/
│   ├── SOUL.md          # Core character and purpose
│   ├── IDENTITY.md      # Role, capabilities, constraints
│   ├── USER.md          # Owner context and preferences
│   └── TOOLS.md         # Available tools and commands
├── knowledge/           # Stub — future knowledge framework
│   └── README.md
└── CONTEXT.md           # This file
```

## Usage

This brain is shared across all ClawdKit daemon instances. Each daemon instance's `settings.json` has four SessionStart hooks that read from this directory.

To update persona context:
1. Edit the relevant file in `brain/prompts/`
2. Changes take effect on the next session start (or after `/clear` + hook re-fire)

To configure for a specific agent:
- Replace `[PLACEHOLDER]` values in persona files during bootstrap
- Or maintain instance-specific overrides at the daemon instance level
