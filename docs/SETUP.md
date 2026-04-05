# ClawdKit Setup Guide

Complete setup for a persistent Claude Code daemon agent on macOS or Linux.

## Overview

ClawdKit has two components:

1. **agent-brain plugin** — Persistent persona (SOUL, IDENTITY, USER, TOOLS) injected into every session
2. **agent-daemon plugin** — Daemon lifecycle: bootstrap, context reset/compact, tmux management + heartbeat scheduling

A daemon instance lives at `~/.clawdcode/<agent_name>/` and is created by the bootstrap skill.

---

## Prerequisites

| Requirement | macOS | Linux |
|-------------|-------|-------|
| [Bun](https://bun.sh) | `brew install bun` | `curl -fsSL https://bun.sh/install \| bash` |
| [tmux](https://github.com/tmux/tmux) | `brew install tmux` | `apt install tmux` or `dnf install tmux` |
| curl | Built-in | Usually built-in |
| jq (recommended) | `brew install jq` | `apt install jq` |
| Claude Code CLI | [claude.ai/code](https://claude.ai/code) | Same |
| Linux: systemd linger | — | `loginctl enable-linger $USER` |

---

## Step 1: Install Plugins

From within Claude Code:

```
/plugin install agent-brain@agent-library
/plugin install agent-daemon@agent-library
```

> **Note:** `agent-brain@agent-library` v2.0.0 replaces v1.0.0. If you have the old version installed, uninstall it first:
> ```
> /plugin uninstall agent-brain
> ```

---

## Step 2: Configure the Brain

The brain lives at `brain/` in this repo. Customize the persona files before bootstrapping:

| File | What to edit |
|------|-------------|
| `brain/prompts/SOUL.md` | Agent's core purpose, values, character |
| `brain/prompts/IDENTITY.md` | Replace `[OWNER_NAME]`, `[AGENT_NAME]`, `[BRAIN_PATH]` |
| `brain/prompts/USER.md` | Replace owner details, shared brain path |
| `brain/prompts/TOOLS.md` | Add MCP servers, update commands if needed |

---

## Step 3: Install Channel Plugins

### Telegram (cross-platform, recommended)

```
/plugin install claude-telegram@claude-plugins-official
```

Follow the plugin's setup to get a Telegram bot token and configure it. The plugin will create a `.mcp.json` config file.

Copy or symlink it to your future instance directory:
```sh
cp ~/.claude/channels/telegram/.mcp.json ~/.clawdcode/<agent_name>/.mcp-telegram.json
```

### iMessage (macOS only)

```
/plugin install claude-imessage@claude-plugins-official
```

Follow the plugin's macOS setup. Copy the config:
```sh
cp ~/.claude/channels/imessage/.mcp.json ~/.clawdcode/<agent_name>/.mcp-imessage.json
```

> You can do this step after bootstrap — channel config files are optional at start time.

---

## Step 4: Bootstrap the Daemon

Run the bootstrap skill:

```
/agent-daemon:bootstrap
```

The guided flow will ask:
1. **Agent name** — e.g., `jarvis`, `scout` (alphanumeric + hyphens)
2. **Brain location** — path to `brain/` in this repo
3. **Notification channel** — `telegram` (default) or `imessage`

Bootstrap creates `~/.clawdcode/<agent_name>/` with all config files and installs the scheduler.

---

## Step 5: Start the Daemon

```sh
cd /path/to/clawdkit
make start INSTANCE=<agent_name>
```

Verify it's running:
```sh
make status INSTANCE=<agent_name>
tmux attach -t clawdkit-<agent_name>
```

You should see Claude Code starting up with persona injected via hooks.

---

## Lifecycle Commands

```sh
make start INSTANCE=<name>      # Start daemon in tmux
make stop INSTANCE=<name>       # Stop daemon
make restart INSTANCE=<name>    # Restart
make status INSTANCE=<name>     # Check tmux session status
make health INSTANCE=<name>     # Show pane PID info
make install INSTANCE=<name>    # Install heartbeat scheduler
make uninstall INSTANCE=<name>  # Remove heartbeat scheduler
```

---

## Heartbeat

The heartbeat fires every 30 minutes via the platform scheduler:
- **macOS**: launchd plist at `~/Library/LaunchAgents/com.clawdkit.heartbeat.<name>.plist`
- **Linux**: systemd timer at `~/.config/systemd/user/clawdkit-heartbeat-<name>.timer`

The heartbeat reads `~/.clawdcode/<agent_name>/prompts/HEARTBEAT.md` and sends it to the daemon via HTTP POST to `localhost:7749`.

Customize heartbeat tasks by editing `HEARTBEAT.md` in the instance directory.

### Verify heartbeat scheduler

```sh
# macOS
launchctl list | grep clawdkit

# Linux
systemctl --user list-timers | grep clawdkit
```

### Manual heartbeat trigger (test)

```sh
curl -X POST -H 'Content-Type: text/plain' \
  --data 'Test heartbeat: check status and log a brief note.' \
  http://127.0.0.1:7749/heartbeat
```

---

## After /clear

When the daemon's context is cleared (manually or via `/agent-daemon:context-reset`):

1. SessionStart hooks fire automatically
2. All 4 persona files are re-injected via `additionalContext`
3. The daemon reconstructs state from `state.json` and `progress.log` per its CLAUDE.md

No manual re-initialization needed.

---

## Multiple Instances

Each instance gets a unique name and runs independently:

```sh
make start INSTANCE=jarvis
make start INSTANCE=scout
```

> **Note:** Each instance needs a unique heartbeat port if running simultaneously.
> Currently all instances use port 7749 — if running multiple, edit `daemon/mcp/heartbeat/server.ts`
> to support per-instance ports (set `PORT` from env or args).

---

## Troubleshooting

### Daemon won't start

```sh
make status INSTANCE=<name>          # Is tmux session running?
tmux attach -t clawdkit-<name>       # Check output
cat ~/.clawdcode/<name>/.clawdkit/progress.log  # Check logs
```

### Heartbeat not firing

```sh
# macOS
launchctl list com.clawdkit.heartbeat.<name>
cat ~/.clawdcode/<name>/.clawdkit/heartbeat-launchd.log

# Linux
systemctl --user status clawdkit-heartbeat-<name>.timer
journalctl --user -u clawdkit-heartbeat-<name>.service
```

### Hook output too large

If persona files exceed ~50K chars, Claude Code saves them to disk instead of direct injection. Check file sizes:

```sh
wc -c brain/prompts/*.md
```

Keep each file under ~10K characters (well under the 50K threshold).

### Linux: heartbeat stops after logout

```sh
loginctl enable-linger $USER
```

This keeps user-level systemd services running after logout.

---

## Migrating from agent-brain v1.0.0

The v2.0.0 plugin replaces the standalone `~/agent_brain` vault with `brain/` in this monorepo.

Key changes:
- Identity files moved from `01_Identity/` (5 files) to `brain/prompts/` (4 files: SOUL, IDENTITY, USER, TOOLS)
- Bootstrap sequence updated — 4 files instead of 5
- Plugin installs from `agent-library` as before, but bumped to v2.0.0

To migrate:
1. Copy content from your `~/agent_brain/01_Identity/` files into the new `brain/prompts/` structure
2. Uninstall old plugin: `/plugin uninstall agent-brain`
3. Install new: `/plugin install agent-brain@agent-library`
