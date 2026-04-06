#!/bin/sh
# setup.sh — One-command ClawdKit setup: deps → brain → bootstrap → start
#
# Usage:
#   ./setup.sh                           # Interactive prompts
#   ./setup.sh --agent-name jarvis       # Skip name prompt
#   ./setup.sh --agent-name jarvis \
#              --brain-path ~/.agent-brain/jarvis \
#              --channel telegram         # Fully non-interactive
#
# Defaults:
#   brain-path: ~/.agent-brain/<agent-name>  (scaffolded from repo templates)
#   channel:    fakechat                     (zero-config, swap to telegram later)

set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_PATH="${REPO_ROOT}/daemon/scripts"

# ---------------------------------------------------------------------------
# Argument parsing — pass-through unknown args to bootstrap.sh
# ---------------------------------------------------------------------------
AGENT_NAME=""
BRAIN_PATH=""
CHANNEL=""
NO_START=""
EXTRA_ARGS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --agent-name)
      shift; AGENT_NAME="${1:?--agent-name requires a value}" ;;
    --brain-path)
      shift; BRAIN_PATH="${1:?--brain-path requires a value}" ;;
    --channel)
      shift; CHANNEL="${1:?--channel requires a value}" ;;
    --no-start)
      NO_START=1 ;;
    --overwrite)
      EXTRA_ARGS="$EXTRA_ARGS --overwrite" ;;
    -h|--help)
      printf 'Usage: setup.sh [--agent-name <name>] [--brain-path <path>] [--channel telegram|imessage|fakechat] [--no-start] [--overwrite]\n'
      printf '\nDefaults: brain at ~/.agent-brain/<name>, channel=fakechat, starts daemon after bootstrap.\n'
      exit 0 ;;
    *)
      printf 'setup.sh: unknown argument: %s (try --help)\n' "$1" >&2
      exit 1 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Interactive prompts for missing args
# ---------------------------------------------------------------------------
if [ -z "$AGENT_NAME" ]; then
  printf 'Agent name (alphanumeric + hyphens, e.g. jarvis): '
  read -r AGENT_NAME
  if [ -z "$AGENT_NAME" ]; then
    printf 'setup.sh: agent name is required\n' >&2
    exit 1
  fi
fi

if [ -z "$BRAIN_PATH" ]; then
  DEFAULT_BRAIN="${HOME}/.agent-brain/${AGENT_NAME}"
  printf 'Brain path [%s]: ' "$DEFAULT_BRAIN"
  read -r BRAIN_PATH
  BRAIN_PATH="${BRAIN_PATH:-$DEFAULT_BRAIN}"
fi

if [ -z "$CHANNEL" ]; then
  printf 'Notification channel (telegram/imessage/fakechat) [fakechat]: '
  read -r CHANNEL
  CHANNEL="${CHANNEL:-fakechat}"
fi

# ---------------------------------------------------------------------------
# Run bootstrap with brain scaffolding
# ---------------------------------------------------------------------------
printf '\n--- Running bootstrap ---\n'

BOOTSTRAP_ARGS="--agent-name $AGENT_NAME --brain-path $BRAIN_PATH --channel $CHANNEL --scripts-path $SCRIPTS_PATH --scaffold-brain"

# shellcheck disable=SC2086
INSTANCE_DIR="$("${SCRIPTS_PATH}/bootstrap.sh" $BOOTSTRAP_ARGS $EXTRA_ARGS)"

printf '\nInstance created at: %s\n' "$INSTANCE_DIR"

# ---------------------------------------------------------------------------
# Install bun dependencies for MCP servers
# ---------------------------------------------------------------------------
printf '\n--- Installing MCP server dependencies ---\n'
for mcp_dir in "${REPO_ROOT}/daemon/mcp/heartbeat" "${REPO_ROOT}/daemon/mcp/session-control"; do
  if [ -f "${mcp_dir}/package.json" ]; then
    (cd "$mcp_dir" && bun install --frozen-lockfile 2>/dev/null || bun install)
  fi
done

# ---------------------------------------------------------------------------
# Start the daemon (unless --no-start)
# ---------------------------------------------------------------------------
if [ -z "$NO_START" ]; then
  printf '\n--- Starting daemon ---\n'
  START_FLAGS="--instance $AGENT_NAME"
  if [ "$CHANNEL" = "fakechat" ]; then
    START_FLAGS="$START_FLAGS --debug"
  fi
  # shellcheck disable=SC2086
  "${SCRIPTS_PATH}/clawdkit.sh" $START_FLAGS start

  printf '\n'
  printf '======================================\n'
  printf '  ClawdKit daemon "%s" is running!\n' "$AGENT_NAME"
  printf '======================================\n'
  printf '\n'
  printf 'Attach to session:  tmux attach -t clawdkit-%s\n' "$AGENT_NAME"
  printf 'Check status:       make status INSTANCE=%s\n' "$AGENT_NAME"
  printf 'Stop daemon:        make stop INSTANCE=%s\n' "$AGENT_NAME"
  printf '\n'
  printf 'Customize your agent:\n'
  printf '  Brain prompts:    %s/prompts/\n' "$BRAIN_PATH"
  printf '  Heartbeat tasks:  %s/prompts/HEARTBEAT.md\n' "$INSTANCE_DIR"
  printf '  Instance config:  %s/CLAUDE.md\n' "$INSTANCE_DIR"
  printf '\n'
  if [ "$CHANNEL" = "fakechat" ]; then
    printf 'Using fakechat (dev channel). To switch to Telegram later:\n'
    printf '  1. Install plugin: /plugin install claude-telegram@claude-plugins-official\n'
    printf '  2. Configure bot token via /telegram:configure\n'
    printf '  3. Copy config: cp ~/.claude/channels/telegram/.mcp.json %s/.mcp-telegram.json\n' "$INSTANCE_DIR"
    printf '  4. Restart: make restart INSTANCE=%s\n' "$AGENT_NAME"
  fi
else
  printf '\nSetup complete. Start with: make start INSTANCE=%s\n' "$AGENT_NAME"
fi
