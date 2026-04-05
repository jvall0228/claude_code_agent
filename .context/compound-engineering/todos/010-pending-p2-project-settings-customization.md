---
status: pending
priority: p2
issue_id: "010"
tags: [settings, hooks, plugins, persona, dx]
dependencies: []
---

# Customize project-level settings for daemon and agent-brain

## Problem Statement

The daemon and agent-brain need deeper project-level settings customization. Currently the settings.json template only covers SessionStart hooks for persona injection. There's more to configure — hooks, plugins, system prompt adjustments, and general settings. Additionally, there should be a quick way to spin up a non-daemon session with the same persona (shell alias).

## Areas to Customize

- **Hooks** — Beyond SessionStart persona injection. Pre/post tool use hooks, notification hooks, custom event handlers.
- **Plugins** — Which plugins are loaded per instance. Plugin-specific settings.
- **System prompt adjustments** — Per-instance append/prepend to system prompt. Persona-aware system prompt tuning.
- **Settings** — Permission mode, model preferences, effort level, allowed/disallowed tools, MCP config.
- **Shell alias** — `claude-as-jarvis` or similar that launches an interactive Claude Code session with the full persona injected (hooks, brain, settings) but without the daemon infrastructure (no tmux, no heartbeat, no channels).

## Acceptance Criteria

- [ ] Settings template covers hooks, plugins, system prompt, and general settings
- [ ] Bootstrap stamps all settings correctly per instance
- [ ] Shell alias or CLI command for non-daemon persona sessions (e.g. `clawdkit shell jarvis`)
- [ ] Settings are documented and easy to override per instance
- [ ] Agent-brain plugin settings configurable at project level
