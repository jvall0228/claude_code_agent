---
title: "Tools"
type: tools
updated: 2026-04-05
---

# Tools

Available tools and how to use them effectively.

## Claude Code Built-ins

| Tool | Use For |
|------|---------|
| Read | Read any file — prefer over Bash cat/head |
| Write | Create new files or full rewrites |
| Edit | Modify existing files — prefer over Write for changes |
| Bash | Shell commands, git, system operations |
| Grep | Search file contents — prefer over bash grep |
| Glob | Find files by pattern — prefer over bash find |
| WebSearch | Current information, recent docs |
| WebFetch | Fetch a specific URL |

## MCP Servers

*[List active MCP servers configured in this daemon instance.]*

| Server | Purpose | Access |
|--------|---------|--------|
| heartbeat | Receive heartbeat triggers | Channel: `localhost:7749` |
| [telegram] | Send/receive Telegram messages | Channel (if enabled) |
| [iMessage] | Send/receive iMessages (macOS) | Channel (if enabled) |

## Channel Protocol

Incoming messages arrive as:
```xml
<channel source="[channel_name]" ...>message content</channel>
```

Outgoing responses use channel-specific reply tools (e.g., `telegram_reply`).

## State Files

| File | Purpose |
|------|---------|
| `.clawdkit/state.json` | Session state — last heartbeat, notification channel |
| `.clawdkit/progress.log` | Free-form activity log, truncated at 1000 lines |
| `.clawdkit/heartbeat.lock` | Prevents concurrent heartbeat runs |
| `prompts/HEARTBEAT.md` | Proactive task checklist, read on each heartbeat |

## Key Commands (via Makefile)

```sh
make start         # Start daemon in tmux
make stop          # Stop daemon
make restart       # Restart
make status        # Check tmux session status
make install       # Install scheduler (launchd/systemd)
make uninstall     # Remove scheduler
```

---

*Update MCP server list and add tool-specific notes during bootstrap.*
