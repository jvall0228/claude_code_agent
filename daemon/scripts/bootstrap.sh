#!/bin/sh
# bootstrap.sh — Non-interactive ClawdKit daemon instance bootstrapper
#
# Usage:
#   bootstrap.sh --agent-name <name> --brain-path <path>
#                [--channel telegram|imessage]
#                [--scripts-path <path>]
#                [--overwrite]
#
# Exits 0 on success, non-zero on validation failure.
# All output goes to stderr; the final instance path is printed to stdout.

set -e

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
AGENT_NAME=""
BRAIN_PATH=""
CHANNEL="telegram"
SCRIPTS_PATH=""
OVERWRITE=""

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --agent-name)
      shift
      AGENT_NAME="${1:?--agent-name requires a value}"
      ;;
    --brain-path)
      shift
      BRAIN_PATH="${1:?--brain-path requires a value}"
      ;;
    --channel)
      shift
      CHANNEL="${1:?--channel requires a value}"
      ;;
    --scripts-path)
      shift
      SCRIPTS_PATH="${1:?--scripts-path requires a value}"
      ;;
    --overwrite)
      OVERWRITE=1
      ;;
    *)
      printf 'bootstrap.sh: unknown argument: %s\n' "$1" >&2
      printf 'Usage: bootstrap.sh --agent-name <name> --brain-path <path> [--channel telegram|imessage] [--scripts-path <path>] [--overwrite]\n' >&2
      exit 1
      ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Validate required args
# ---------------------------------------------------------------------------
if [ -z "$AGENT_NAME" ]; then
  printf 'bootstrap.sh: --agent-name is required\n' >&2
  exit 1
fi

if [ -z "$BRAIN_PATH" ]; then
  printf 'bootstrap.sh: --brain-path is required\n' >&2
  exit 1
fi

# Validate agent name: [a-zA-Z0-9][a-zA-Z0-9-]*
case "$AGENT_NAME" in
  *[!a-zA-Z0-9-]*) printf 'bootstrap.sh: invalid agent name "%s" — only alphanumeric and hyphens allowed\n' "$AGENT_NAME" >&2; exit 1 ;;
  [-]*) printf 'bootstrap.sh: invalid agent name "%s" — must not start with a hyphen\n' "$AGENT_NAME" >&2; exit 1 ;;
esac

# Validate channel
case "$CHANNEL" in
  telegram|imessage) ;;
  *) printf 'bootstrap.sh: invalid channel "%s" — must be telegram or imessage\n' "$CHANNEL" >&2; exit 1 ;;
esac

# Warn if iMessage selected on non-Darwin
if [ "$CHANNEL" = "imessage" ] && [ "$(uname -s)" != "Darwin" ]; then
  printf 'bootstrap.sh: WARNING: imessage is macOS only — falling back to telegram\n' >&2
  CHANNEL="telegram"
fi

# Reject path traversal components before canonicalization
case "$BRAIN_PATH" in
  */../*|*/..|../*|..) printf 'bootstrap.sh: brain path must not contain ".." components: %s\n' "$BRAIN_PATH" >&2; exit 1 ;;
esac

# Resolve absolute brain path
BRAIN_PATH="$(cd "$BRAIN_PATH" 2>/dev/null && pwd)" || {
  printf 'bootstrap.sh: brain path not found: %s\n' "$BRAIN_PATH" >&2
  exit 1
}

# Validate brain has expected structure
if [ ! -f "${BRAIN_PATH}/prompts/SOUL.md" ]; then
  printf 'bootstrap.sh: brain path "%s" does not contain prompts/SOUL.md — run /agent-brain:scaffolding-agent-brain first\n' "$BRAIN_PATH" >&2
  exit 1
fi

# Resolve scripts path
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -z "$SCRIPTS_PATH" ]; then
  SCRIPTS_PATH="$SCRIPT_DIR"
fi
SCRIPTS_PATH="$(cd "$SCRIPTS_PATH" 2>/dev/null && pwd)" || {
  printf 'bootstrap.sh: scripts path not found: %s\n' "$SCRIPTS_PATH" >&2
  exit 1
}

# Resolve daemon root (parent of scripts/)
DAEMON_DIR="$(cd "${SCRIPTS_PATH}/.." && pwd)"

INSTANCE_DIR="${HOME}/.clawdcode/${AGENT_NAME}"

# ---------------------------------------------------------------------------
# Check for existing instance
# ---------------------------------------------------------------------------
if [ -d "$INSTANCE_DIR" ] && [ -z "$OVERWRITE" ]; then
  printf 'bootstrap.sh: instance "%s" already exists at %s — pass --overwrite to replace\n' "$AGENT_NAME" "$INSTANCE_DIR" >&2
  exit 1
fi

printf 'bootstrap.sh: initializing instance "%s" at %s\n' "$AGENT_NAME" "$INSTANCE_DIR" >&2

# ---------------------------------------------------------------------------
# Create directory structure
# ---------------------------------------------------------------------------
mkdir -p "${INSTANCE_DIR}/.claude"
mkdir -p "${INSTANCE_DIR}/.clawdkit"
mkdir -p "${INSTANCE_DIR}/prompts"

# ---------------------------------------------------------------------------
# Stamp CLAUDE.md from template
# ---------------------------------------------------------------------------
CLAUDE_TEMPLATE="${DAEMON_DIR}/templates/CLAUDE.md.template"
if [ ! -f "$CLAUDE_TEMPLATE" ]; then
  printf 'bootstrap.sh: CLAUDE.md template not found at %s\n' "$CLAUDE_TEMPLATE" >&2
  exit 1
fi

sed \
  -e "s|{{AGENT_NAME}}|${AGENT_NAME}|g" \
  -e "s|{{BRAIN_PATH}}|${BRAIN_PATH}|g" \
  -e "s|{{INSTANCE_DIR}}|${INSTANCE_DIR}|g" \
  -e "s|{{NOTIFICATION_CHANNEL}}|${CHANNEL}|g" \
  "$CLAUDE_TEMPLATE" > "${INSTANCE_DIR}/CLAUDE.md"

# ---------------------------------------------------------------------------
# Stamp settings.json from template
# ---------------------------------------------------------------------------
SETTINGS_TEMPLATE="${DAEMON_DIR}/templates/settings.json.template"
if [ ! -f "$SETTINGS_TEMPLATE" ]; then
  printf 'bootstrap.sh: settings.json template not found at %s\n' "$SETTINGS_TEMPLATE" >&2
  exit 1
fi

sed \
  -e "s|{{CLAWDKIT_SCRIPTS_PATH}}|${SCRIPTS_PATH}|g" \
  -e "s|{{BRAIN_PATH}}|${BRAIN_PATH}|g" \
  "$SETTINGS_TEMPLATE" > "${INSTANCE_DIR}/.claude/settings.json"

# ---------------------------------------------------------------------------
# Create initial state.json
# ---------------------------------------------------------------------------
cat > "${INSTANCE_DIR}/.clawdkit/state.json" <<EOF
{
  "last_heartbeat": null,
  "session_started": null,
  "heartbeat_in_progress": false,
  "notification_channel": "${CHANNEL}"
}
EOF

# ---------------------------------------------------------------------------
# Create empty progress.log
# ---------------------------------------------------------------------------
touch "${INSTANCE_DIR}/.clawdkit/progress.log"

# ---------------------------------------------------------------------------
# Copy or create HEARTBEAT.md
# ---------------------------------------------------------------------------
HEARTBEAT_SRC="${BRAIN_PATH}/prompts/HEARTBEAT.md"
HEARTBEAT_DEST="${INSTANCE_DIR}/prompts/HEARTBEAT.md"
if [ -f "$HEARTBEAT_SRC" ]; then
  cp "$HEARTBEAT_SRC" "$HEARTBEAT_DEST"
else
  cat > "$HEARTBEAT_DEST" <<'EOF'
# Heartbeat Tasks

- Check GitHub notifications
- Review open PRs assigned to me
- Summarize recent activity from the last 30 minutes
EOF
fi

# ---------------------------------------------------------------------------
# Stamp heartbeat MCP config
# ---------------------------------------------------------------------------
MCP_SRC="${DAEMON_DIR}/mcp/heartbeat/.mcp.json"
MCP_DEST="${INSTANCE_DIR}/.mcp-heartbeat.json"
if [ ! -f "$MCP_SRC" ]; then
  printf 'bootstrap.sh: heartbeat .mcp.json not found at %s\n' "$MCP_SRC" >&2
  exit 1
fi
MCP_DIR="${DAEMON_DIR}/mcp/heartbeat"
sed "s|{{HEARTBEAT_MCP_PATH}}|${MCP_DIR}|g" "$MCP_SRC" > "$MCP_DEST"

# ---------------------------------------------------------------------------
# Install scheduler
# ---------------------------------------------------------------------------
INSTALL_RC=0
"${SCRIPTS_PATH}/clawdkit.sh" --instance "$AGENT_NAME" install >&2 || INSTALL_RC=$?
if [ "$INSTALL_RC" -ne 0 ]; then
  printf 'bootstrap.sh: WARNING: scheduler install failed (exit %d) — install manually\n' "$INSTALL_RC" >&2
fi

# ---------------------------------------------------------------------------
# Print next steps to stderr; instance path to stdout (machine-readable)
# ---------------------------------------------------------------------------
printf '\n' >&2
printf '✓ Daemon instance %s created at %s\n' "$AGENT_NAME" "$INSTANCE_DIR" >&2
printf '\n' >&2
printf 'Next steps:\n' >&2
printf '1. Install channel plugins:\n' >&2
printf '   - Telegram: /plugin install claude-telegram@claude-plugins-official\n' >&2
printf '   - iMessage: /plugin install claude-imessage@claude-plugins-official  (macOS only)\n' >&2
printf '\n' >&2
printf '2. Configure channel credentials (follow plugin setup instructions)\n' >&2
printf '\n' >&2
printf '3. Copy the channel .mcp.json file to your instance dir:\n' >&2
printf '   %s/.mcp-telegram.json   (Telegram)\n' "$INSTANCE_DIR" >&2
printf '   %s/.mcp-imessage.json   (iMessage)\n' "$INSTANCE_DIR" >&2
printf '\n' >&2
printf '4. Start the daemon:\n' >&2
printf '   %s/clawdkit.sh --instance %s start\n' "$SCRIPTS_PATH" "$AGENT_NAME" >&2
printf '\n' >&2
printf '5. Verify in tmux:\n' >&2
printf '   tmux attach -t clawdkit-%s\n' "$AGENT_NAME" >&2

printf '%s\n' "$INSTANCE_DIR"
