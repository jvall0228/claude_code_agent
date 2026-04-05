# CLAUDE.md

## Project

ClawdKit — persistent, autonomous Claude Code agent toolkit. Hosts agents in tmux with scheduled heartbeats, messaging channels, and persona injection.

## Repository Layout

- `daemon/scripts/` — Shell scripts: `clawdkit.sh` (lifecycle), `start-agent.sh` (tmux launcher), `bootstrap.sh` (instance creation), `heartbeat.sh` (scheduler task)
- `daemon/scripts/hooks/` — SessionStart hooks that inject brain prompts
- `daemon/mcp/heartbeat/` — Bun/TS MCP server, channel type, receives heartbeat POSTs on port 7749
- `daemon/mcp/session-control/` — Bun/TS MCP server, tools for clearing/compacting the agent's own context via tmux send-keys
- `daemon/templates/` — `CLAUDE.md.template`, `settings.json.template`, `.mcp.json.template` — stamped by bootstrap.sh with placeholders like `{{AGENT_NAME}}`, `{{BRAIN_PATH}}`
- `daemon/config/` — Platform scheduler templates (launchd plist, systemd service/timer)
- `brain/prompts/` — Persona files: `SOUL.md`, `IDENTITY.md`, `USER.md`, `TOOLS.md`, `HEARTBEAT.md`
- `plugins/agent-daemon/` — Claude Code plugin with bootstrap, context-reset, context-compact skills
- `plugins/agent-brain/` — Claude Code plugin for brain scaffolding and knowledge ingestion
- `docs/` — Setup guide, plans, brainstorms

## Key Patterns

- **POSIX shell only** in `daemon/scripts/`. No bashisms. Scripts must work on macOS and Linux.
- **Bun + TypeScript** for MCP servers. Use `@modelcontextprotocol/sdk`.
- **MCP config workaround**: The `cwd` field in `.mcp.json` is broken (anthropics/claude-code#17565). Use `"command": "bash", "args": ["-c", "cd /path && bun server.ts"]` instead.
- **MCP stdio**: Never print to stdout from MCP servers except MCP protocol messages. Use `process.stderr.write()` for logging. Don't run `bun install` in the start command — it pollutes stdout and breaks the handshake.
- **Channel MCP servers** must be declared in `.mcp.json` (not `--mcp-config`). The `--dangerously-load-development-channels server:<name>` flag references servers by name from `.mcp.json`.
- **Approved channel plugins** use `--channels plugin:<name>@<marketplace>`, not `--dangerously-load-development-channels`.
- **Template placeholders**: `{{DOUBLE_BRACES}}` — stamped by `sed` in bootstrap.sh. Available: `AGENT_NAME`, `BRAIN_PATH`, `INSTANCE_DIR`, `NOTIFICATION_CHANNEL`, `CLAWDKIT_SCRIPTS_PATH`, `HEARTBEAT_MCP_PATH`, `SESSION_CONTROL_MCP_PATH`, `HOME`.
- **Atomic locking** in heartbeat.sh uses `mkdir` (atomic on local FS). Not NFS-safe.
- **Fakechat** is debug-only. Gated behind `--debug` flag in clawdkit.sh / `CLAWDKIT_DEBUG` env var in start-agent.sh.

## Instance Directories

Daemon instances live at `~/.clawdcode/<agent_name>/`. Created by `bootstrap.sh`. Key files:
- `.mcp.json` — MCP server declarations (heartbeat + session-control)
- `.claude/settings.json` — SessionStart hooks for persona injection
- `CLAUDE.md` — Agent-specific instructions (stamped from template)
- `.clawdkit/state.json` — Runtime state
- `.clawdkit/progress.log` — Append-only activity log
- `prompts/HEARTBEAT.md` — Instance task list

## Commands

```sh
make start INSTANCE=<name>     # Start daemon
make stop INSTANCE=<name>      # Stop daemon
make restart INSTANCE=<name>   # Restart
make status INSTANCE=<name>    # Check if running
make health INSTANCE=<name>    # Health details
make install INSTANCE=<name>   # Install scheduler
make uninstall INSTANCE=<name> # Remove scheduler
```

`clawdkit.sh` also accepts `clear` (send `/clear` to agent) and `--debug` (enable fakechat).

## Testing MCP Servers

```sh
# Heartbeat
cd daemon/mcp/heartbeat && bun server.ts
# Then POST: curl -X POST http://127.0.0.1:7749/heartbeat -d "test prompt"

# Session control
cd daemon/mcp/session-control && CLAWDKIT_AGENT_NAME=jarvis bun server.ts
# Connects via stdio — use with Claude Code's MCP inspector
```

## Conventions

- Commit messages: imperative mood, concise, `feat:`/`fix:`/`chore:` prefix
- Scripts: quote all variables, use `printf` not `echo`, exit non-zero on failure
- No secrets in repo — credentials go in instance env vars or channel plugin config
