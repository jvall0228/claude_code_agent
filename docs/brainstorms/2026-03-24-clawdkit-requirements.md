---
date: 2026-03-24
topic: clawdkit
---

# ClawdKit — Persistent Claude Code Agent

## Problem Frame

Claude Code sessions are ephemeral — they lose context when closed and don't proactively act when idle. OpenClaw solves this with a custom agent framework, but that means leaving the Claude Code ecosystem entirely. ClawdKit makes a standard Claude Code session persistent and autonomous by wrapping it in tmux, adding OpenClaw-style prompt files (SOUL, IDENTITY, HEARTBEAT), and connecting it to messaging channels — all while staying native to Claude Code's tooling, memory system, and MCP servers.

## Requirements

- R1. **Prompt file architecture** — Mirror OpenClaw's file structure: SOUL.md, IDENTITY.md, USER.md, TOOLS.md, HEARTBEAT.md as standalone prompt files. CLAUDE.md loads/references all of them into the system prompt, replicating the OpenClaw bootstrap sequence within Claude Code's instruction system.
- R2. **HEARTBEAT.md** — A configurable checklist of proactive tasks the agent runs every 30 minutes (e.g., check GitHub notifications, review PR status, organize memory, surface items needing attention). The agent reads the checklist, reasons about what needs doing, and acts or notifies.
- R3. **Heartbeat scheduling** — A cron job or shell-based timer fires on schedule and pushes the heartbeat prompt to the Claude Code session via a channel MCP server (e.g., iMessage or Telegram plugin), rather than via `tmux send-keys`. The agent receives and processes the prompt through its existing message-handling flow.
- R4. **Messaging channels** — iMessage and Telegram channel plugins are configured and active at launch. Discord is deferred to a later phase.
- R5. **tmux session management** — The agent runs inside a named tmux session. Shell scripts handle starting, stopping, and monitoring the session. A Makefile provides the user-facing interface (`make start`, `make stop`, `make status`, etc.).
- R6. **Context window management** — Use `/compact` during active use to compress context. Use `/clear` via `tmux send-keys` when the context window needs a full reset. The agent reconstructs state from its prompt files and Claude Code's memory system after a clear.
- R7. **Hybrid assistant role** — The agent serves as both a dev assistant (repo monitoring, CI/CD, PR reviews) and personal assistant (tasks, reminders, surfacing items across channels). The specific behaviors are defined in HEARTBEAT.md and can be customized by the user.
- R8. **Bootstrap sequence** — On first start or after a `/clear`, CLAUDE.md loads the full OpenClaw-style file set: SOUL.md (personality/values), IDENTITY.md (role/expertise), USER.md (user context), and TOOLS.md (capabilities). The agent reconstructs its full identity from these files. HEARTBEAT.md is loaded when the heartbeat cron fires.

## Success Criteria

- The agent runs persistently in a tmux session and survives terminal closes, sleep, and network drops
- Messages sent via iMessage and Telegram reach the agent and get responses
- The heartbeat fires on schedule and the agent takes appropriate action based on HEARTBEAT.md
- After a `/clear`, the agent reconstructs its identity and context from prompt files without manual intervention
- The setup is reproducible from a fresh clone via `make setup && make start`

## Scope Boundaries

- **Not building a custom agent framework** — This uses Claude Code as-is with its native features (channels, memory, CLAUDE.md instructions)
- **No Discord at launch** — Deferred to a later phase
- **No custom UI** — Interaction happens through messaging channels and the terminal
- **No database** — All state is file-based (Markdown files, Claude Code's memory system)
- **No cloud hosting** — Runs on the user's local macOS machine

## Key Decisions

- **Mirror OpenClaw's file structure**: Replicate SOUL.md, IDENTITY.md, USER.md, TOOLS.md, HEARTBEAT.md as standalone files. CLAUDE.md orchestrates loading them, giving us the full OpenClaw bootstrap sequence while still running inside Claude Code.
- **Channel MCP server for heartbeat delivery**: The heartbeat prompt is pushed into the session via the channel MCP server (iMessage or Telegram), keeping the trigger path consistent with how users and external systems already interact with the agent. tmux send-keys is reserved for context resets (`/clear`), which channels can't invoke.
- **Makefile + shell scripts for orchestration**: Makefile provides the clean interface, shell scripts handle the complex tmux/cron logic.
- **iMessage + Telegram first**: Both have channel plugins available. Discord deferred.
- **Project name: ClawdKit**: Playful nod to OpenClaw, positions it as a toolkit/framework.

## Dependencies / Assumptions

- Running on macOS (required for iMessage channel plugin)
- Claude Code is installed and authenticated
- tmux is installed
- iMessage and Telegram channel plugins are available and functional
- Claude Code's `/compact` and `/clear` commands work reliably in tmux sessions

## Outstanding Questions

### Deferred to Planning

- [Affects R4][Needs research] Exact setup steps for iMessage and Telegram channel plugins — what configuration is needed?
- [Affects R6][Technical] Best strategy for detecting when context is too large and triggering a clear automatically vs. manually
- [Affects R8][Technical] What state (if any) should be persisted beyond Claude Code's native memory to ensure clean reconstruction after `/clear`?
- [Affects R3][Technical] Whether to use system cron, launchd, or a shell loop for the heartbeat timer — the trigger mechanism is resolved (channel MCP server), but the scheduler choice remains open
- [Affects R3][Technical] Which channel to use as the heartbeat delivery vehicle — iMessage or Telegram — and whether to use a dedicated "system" contact/channel vs. the user's own chat

## Next Steps

→ `/ce:plan` for structured implementation planning
