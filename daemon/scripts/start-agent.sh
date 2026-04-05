#!/bin/sh
# start-agent.sh — Launched inside tmux by clawdkit.sh.
# Runs claude from the daemon instance directory with channel flags.
# Retries up to 3 times with 5s delay on crash.
#
# Environment variables set by clawdkit.sh before calling this script:
#   CLAWDKIT_AGENT_NAME   — name of the daemon instance
#   CLAWDKIT_INSTANCE_DIR — path to ~/.clawdcode/<agent_name>/
#   CLAWDKIT_SCRIPTS_PATH — path to daemon/scripts/
#   CLAWDKIT_MCP_HEARTBEAT — path to daemon/mcp/heartbeat/.mcp.json
#   CLAWDKIT_DEBUG         — set to 1 to enable debug channels (fakechat)

set -e

AGENT_NAME="${CLAWDKIT_AGENT_NAME:-clawdkit}"
INSTANCE_DIR="${CLAWDKIT_INSTANCE_DIR:-${HOME}/.clawdcode/${AGENT_NAME}}"
MCP_HEARTBEAT="${CLAWDKIT_MCP_HEARTBEAT:-}"

OS="$(uname -s)"

MAX_RETRIES=3
RETRY_DELAY_BASE=5
RETRY_DELAY_JITTER=5

# Pre-flight: ensure instance directory exists before entering retry loop
if [ ! -d "$INSTANCE_DIR" ]; then
  printf '[clawdkit] start-agent: INSTANCE_DIR does not exist: %s\n' "$INSTANCE_DIR" >&2
  exit 1
fi

# Build argument list safely — no eval, handles paths with spaces
# Channel servers are defined in $INSTANCE_DIR/.mcp.json (Claude picks them up automatically).
# --dangerously-load-development-channels tags custom dev channels by name from .mcp.json.
# --channels enables approved plugin channels.
DEV_CHANNELS=""
APPROVED_CHANNELS=""

# Heartbeat — custom dev channel, defined in .mcp.json
DEV_CHANNELS="$DEV_CHANNELS server:clawdkit-heartbeat"

# Telegram — approved plugin channel
TELEGRAM_MCP="${INSTANCE_DIR}/.mcp-telegram.json"
if [ -f "$TELEGRAM_MCP" ]; then
  APPROVED_CHANNELS="$APPROVED_CHANNELS plugin:telegram@claude-plugins-official"
fi

# Fakechat — debug-only channel, gated behind CLAWDKIT_DEBUG
if [ "${CLAWDKIT_DEBUG:-0}" = "1" ]; then
  FAKECHAT_MCP="${INSTANCE_DIR}/.mcp-fakechat.json"
  if [ -f "$FAKECHAT_MCP" ]; then
    APPROVED_CHANNELS="$APPROVED_CHANNELS plugin:fakechat@claude-plugins-official"
  fi
fi

# iMessage — macOS only, approved plugin channel
if [ "$OS" = "Darwin" ]; then
  IMESSAGE_MCP="${INSTANCE_DIR}/.mcp-imessage.json"
  if [ -f "$IMESSAGE_MCP" ]; then
    APPROVED_CHANNELS="$APPROVED_CHANNELS plugin:imessage@claude-plugins-official"
  fi
fi

# Assemble final argument list
set -- --dangerously-skip-permissions --remote-control "$AGENT_NAME"
if [ -n "$DEV_CHANNELS" ]; then
  set -- "$@" --dangerously-load-development-channels $DEV_CHANNELS
fi
if [ -n "$APPROVED_CHANNELS" ]; then
  set -- "$@" --channels $APPROVED_CHANNELS
fi

# Wait for daemon health endpoint to be ready before launching claude
HEALTH_URL="http://127.0.0.1:${CLAWDKIT_HEARTBEAT_PORT:-7749}/heartbeat"
READY_TIMEOUT=15
READY_WAIT=0
while [ "$READY_WAIT" -lt "$READY_TIMEOUT" ]; do
  if curl -s -o /dev/null --max-time 2 --connect-timeout 1 "$HEALTH_URL" 2>/dev/null; then
    printf '[clawdkit] start-agent: health endpoint ready\n'
    break
  fi
  READY_WAIT=$((READY_WAIT + 1))
  sleep 1
done
if [ "$READY_WAIT" -ge "$READY_TIMEOUT" ]; then
  printf '[clawdkit] start-agent: WARNING: health endpoint not ready after %ds — proceeding anyway\n' "$READY_TIMEOUT" >&2
fi

attempt=0
while [ "$attempt" -lt "$MAX_RETRIES" ]; do
  attempt=$((attempt + 1))
  printf '[clawdkit] start-agent: attempt %d/%d — launching claude in %s\n' \
    "$attempt" "$MAX_RETRIES" "$INSTANCE_DIR"

  # Run claude from the instance directory so it picks up .claude/settings.json there
  (cd "$INSTANCE_DIR" && claude "$@") && {
    printf '[clawdkit] start-agent: claude exited cleanly\n'
    exit 0
  }

  EXIT_CODE=$?
  printf '[clawdkit] start-agent: claude exited with code %d\n' "$EXIT_CODE" >&2

  if [ "$attempt" -lt "$MAX_RETRIES" ]; then
    # Add jitter to prevent thundering herd when multiple agents retry simultaneously
    JITTER=$((RANDOM % RETRY_DELAY_JITTER))
    DELAY=$((RETRY_DELAY_BASE + JITTER))
    printf '[clawdkit] start-agent: retrying in %ds...\n' "$DELAY" >&2
    sleep "$DELAY"
  fi
done

printf '[clawdkit] start-agent: max retries (%d) reached — giving up\n' "$MAX_RETRIES" >&2
exit 1
