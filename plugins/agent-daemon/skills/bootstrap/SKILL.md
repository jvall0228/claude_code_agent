---
name: bootstrap
description: Guided onboarding flow to initialize a new ClawdKit daemon instance at ~/.clawdcode/<agent_name>/. Creates instance directory, stamps config files, installs scheduler. Use when setting up a new persistent agent.
---

# Bootstrap a ClawdKit Daemon Instance

Guided onboarding that creates a complete, ready-to-run daemon instance.

## Outcomes

A fully initialized daemon instance at `~/.clawdcode/<agent_name>/`:

```
~/.clawdcode/<agent_name>/
├── .claude/
│   └── settings.json     # SessionStart hooks pointing to brain/prompts/
├── CLAUDE.md              # Daemon-specific instructions
├── .clawdkit/
│   ├── state.json         # Initial daemon state
│   └── progress.log       # Empty log file
└── prompts/
    └── HEARTBEAT.md       # Instance heartbeat task list
```

Plus platform scheduler config installed and loaded.

## Onboarding Flow

Ask the following questions in sequence using the interactive question tool. Validate each answer before proceeding.

### Step 1: Agent name

Ask: "What should this daemon be called? (e.g., `jarvis`, `scout`, `dev-agent`)"

- Must be alphanumeric + hyphens, no spaces
- Must not already exist at `~/.clawdcode/<name>/` (warn if it does, offer to overwrite)

### Step 2: Brain location

Ask: "Where is your ClawdKit brain? (default: `~/Developer/claude_code_agent/brain`)"

- Must exist as a directory
- Must contain `prompts/SOUL.md` (validates it's a real brain)
- If missing, warn: "Brain not found at <path>. Run `/agent-brain:scaffolding-agent-brain` first, or provide the correct path."

### Step 3: Notification channel

Ask: "Which notification channel? `telegram` (default) or `imessage` (macOS only)"

- Default: `telegram`
- `imessage` only on Darwin; warn if selected on Linux

### Step 4: ClawdKit scripts path

Resolve automatically from the brain path: `<brain_parent>/daemon/scripts`
Confirm with user: "Scripts found at `<path>`. Is this correct?"

## Implementation

After collecting all answers, perform these steps in order:

### Create instance directory structure

```sh
mkdir -p ~/.clawdcode/<agent_name>/.claude
mkdir -p ~/.clawdcode/<agent_name>/.clawdkit
mkdir -p ~/.clawdcode/<agent_name>/prompts
```

### Stamp CLAUDE.md from template

Read `<clawdkit_root>/daemon/templates/CLAUDE.md.template`.
Replace placeholders:
- `{{AGENT_NAME}}` → agent name
- `{{BRAIN_PATH}}` → brain path (absolute)
- `{{INSTANCE_DIR}}` → `~/.clawdcode/<agent_name>` (absolute)
- `{{NOTIFICATION_CHANNEL}}` → telegram or imessage

Write to `~/.clawdcode/<agent_name>/CLAUDE.md`.

### Stamp settings.json from template

Read `<clawdkit_root>/daemon/templates/settings.json.template`.
Replace placeholders:
- `{{CLAWDKIT_SCRIPTS_PATH}}` → scripts path (absolute)
- `{{BRAIN_PATH}}` → brain path (absolute)

Write to `~/.clawdcode/<agent_name>/.claude/settings.json`.

### Create initial state.json

Write to `~/.clawdcode/<agent_name>/.clawdkit/state.json`:
```json
{
  "last_heartbeat": null,
  "session_started": null,
  "heartbeat_in_progress": false,
  "notification_channel": "<telegram|imessage>"
}
```

### Create empty progress.log

Touch `~/.clawdcode/<agent_name>/.clawdkit/progress.log`.

### Copy HEARTBEAT.md

Copy `<clawdkit_root>/docs/HEARTBEAT.md` (if exists) or the default from brain to:
`~/.clawdcode/<agent_name>/prompts/HEARTBEAT.md`

If no source exists, create a minimal default:
```markdown
# Heartbeat Tasks

- Check GitHub notifications
- Review open PRs assigned to me
- Summarize recent activity from the last 30 minutes
```

### Stamp and install heartbeat MCP config

Copy `<clawdkit_root>/daemon/mcp/heartbeat/.mcp.json` to `~/.clawdcode/<agent_name>/.mcp-heartbeat.json`.
Replace `{{HEARTBEAT_MCP_PATH}}` with the absolute path to `daemon/mcp/heartbeat/`.

### Install scheduler

Run: `<clawdkit_root>/daemon/scripts/clawdkit.sh --instance <agent_name> install`

This installs launchd (macOS) or systemd timer (Linux).

## Print Next Steps

After bootstrap completes, print:

```
✓ Daemon instance <agent_name> created at ~/.clawdcode/<agent_name>/

Next steps:
1. Install channel plugins:
   - Telegram: /plugin install claude-telegram@claude-plugins-official
   - iMessage: /plugin install claude-imessage@claude-plugins-official  (macOS only)

2. Configure channel credentials (follow plugin setup instructions)

3. Copy the channel .mcp.json file to your instance dir:
   ~/.clawdcode/<agent_name>/.mcp-telegram.json   (Telegram)
   ~/.clawdcode/<agent_name>/.mcp-imessage.json   (iMessage)

4. Start the daemon:
   cd <clawdkit_root> && make start INSTANCE=<agent_name>

5. Verify in tmux:
   tmux attach -t clawdkit-<agent_name>
```

## Edge Cases

- **Instance already exists**: Warn and ask: "Instance `<name>` already exists. Overwrite? (y/N)"
- **Brain not found**: Halt with clear error. Provide link to scaffolding-agent-brain skill.
- **iMessage on Linux**: Warn and fall back to telegram.
- **Scripts path not found**: Warn and ask user to confirm manually.
- **Scheduler install fails**: Log the error, print manual instructions, continue.

## Verification

Bootstrap is complete when:
- [ ] `~/.clawdcode/<agent_name>/CLAUDE.md` exists with no `{{` placeholders
- [ ] `~/.clawdcode/<agent_name>/.claude/settings.json` has 4 hook commands pointing to real paths
- [ ] `~/.clawdcode/<agent_name>/.clawdkit/state.json` is valid JSON
- [ ] `~/.clawdcode/<agent_name>/prompts/HEARTBEAT.md` exists
- [ ] Scheduler is installed (`launchctl list | grep clawdkit` or `systemctl --user list-timers | grep clawdkit`)
- [ ] Next steps printed clearly
