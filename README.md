# ClawdKit

A toolkit for running persistent, autonomous Claude Code agents with scheduled tasks, messaging channels, and persona injection.

ClawdKit hosts Claude Code sessions inside tmux, fires a heartbeat every 30 minutes via launchd (macOS) or systemd (Linux), and re-injects the agent's identity on every context reset so the agent always wakes up knowing who it is and what to do.

## Architecture

```
daemon/           Infrastructure — scripts, MCP servers, templates, scheduler configs
brain/            Persona — SOUL, IDENTITY, USER, TOOLS, HEARTBEAT prompts
plugins/          Claude Code plugins — bootstrap skill, brain management
docs/             Setup guide, plans, brainstorms
```

Each daemon instance lives at `~/.clawdcode/<agent_name>/` with its own config, state, and logs.

## Prerequisites

- [Bun](https://bun.sh) (MCP servers)
- [tmux](https://github.com/tmux/tmux) (session hosting)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
- curl, jq (heartbeat, hooks)
- Pro, Max, Team, or Enterprise subscription (for remote control)

## Quick Start

### 1. Bootstrap a daemon instance

```sh
# From within Claude Code:
/agent-daemon:bootstrap

# Or directly:
./daemon/scripts/bootstrap.sh \
  --agent-name jarvis \
  --brain-path ./brain \
  --channel fakechat
```

### 2. Customize the brain

Edit the persona files in `brain/prompts/`:

| File | Purpose |
|------|---------|
| `SOUL.md` | Core values and character |
| `IDENTITY.md` | Role, capabilities, constraints |
| `USER.md` | Owner profile and preferences |
| `TOOLS.md` | Available tools and MCP servers |
| `HEARTBEAT.md` | Proactive tasks (run every 30 min) |

### 3. Start the daemon

```sh
make start INSTANCE=jarvis

# With debug channels (fakechat):
./daemon/scripts/clawdkit.sh --instance jarvis --debug start
```

### 4. Verify

```sh
# Check status
make status INSTANCE=jarvis

# Attach to session
tmux attach -t clawdkit-jarvis

# Health check (JSON)
./daemon/scripts/clawdkit.sh --instance jarvis --json health
```

## Lifecycle Commands

```sh
make start   INSTANCE=<name>    # Start daemon in tmux
make stop    INSTANCE=<name>    # Stop daemon
make restart INSTANCE=<name>    # Stop + start
make status  INSTANCE=<name>    # Check if running
make health  INSTANCE=<name>    # Session health details
make install INSTANCE=<name>    # Install 30-min scheduler (launchd/systemd)
make uninstall INSTANCE=<name>  # Remove scheduler
```

Additional clawdkit.sh commands:

```sh
clawdkit.sh --instance <name> clear    # Clear the agent's context window
clawdkit.sh --instance <name> --debug start  # Enable fakechat for debugging
```

## Features

### Remote Control

Every daemon instance starts with `--remote-control`, making it pilotable from [claude.ai/code](https://claude.ai/code) or the Claude mobile app. The session URL is printed at startup.

### Channels

Agents receive messages via Claude Code channels:

| Channel | Type | Flag |
|---------|------|------|
| Heartbeat | Custom dev channel | Always enabled |
| Telegram | Approved plugin | Enabled if `.mcp-telegram.json` exists |
| iMessage | Approved plugin | macOS only, if `.mcp-imessage.json` exists |
| Fakechat | Approved plugin | Debug mode only (`--debug`) |

### MCP Servers

| Server | Purpose |
|--------|---------|
| `clawdkit-heartbeat` | Receives heartbeat POSTs, pushes channel notifications |
| `clawdkit-session-control` | Tools for the agent to clear/compact its own context |

### Persona Injection

SessionStart hooks automatically inject brain prompts into every new context window. After `/clear` or `/compact`, the agent reconstructs its state from `state.json` and `progress.log`.

### Scheduled Heartbeat

The scheduler (launchd on macOS, systemd on Linux) runs `heartbeat.sh` every 30 minutes:

1. Acquires an atomic lock
2. Reads `prompts/HEARTBEAT.md`
3. POSTs the prompt to the heartbeat MCP server
4. The MCP server pushes a channel notification to the running Claude session
5. The agent processes the tasks and logs progress

## Instance Directory Layout

```
~/.clawdcode/<agent_name>/
  .claude/settings.json       SessionStart hooks
  CLAUDE.md                   Daemon instructions
  .mcp.json                   MCP server declarations
  .clawdkit/
    state.json                Session state
    progress.log              Activity log (truncated at ~1000 lines)
  prompts/
    HEARTBEAT.md              Instance-specific task list
```

## Documentation

- [Setup Guide](docs/SETUP.md) — Full setup walkthrough with troubleshooting
- [Feature Plan](docs/plans/2026-04-05-001-feat-clawdkit-persistent-agent-plan.md) — Architecture decisions and design rationale

## License

Apache-2.0
