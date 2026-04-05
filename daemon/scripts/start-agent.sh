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

set -e

AGENT_NAME="${CLAWDKIT_AGENT_NAME:-clawdkit}"
INSTANCE_DIR="${CLAWDKIT_INSTANCE_DIR:-${HOME}/.clawdcode/${AGENT_NAME}}"
MCP_HEARTBEAT="${CLAWDKIT_MCP_HEARTBEAT:-}"

OS="$(uname -s)"

MAX_RETRIES=3
RETRY_DELAY=5

# Build channel flags
CHANNEL_FLAGS="--dangerously-load-development-channels"

# Heartbeat MCP channel (always)
if [ -n "$MCP_HEARTBEAT" ] && [ -f "$MCP_HEARTBEAT" ]; then
  CHANNEL_FLAGS="${CHANNEL_FLAGS} ${MCP_HEARTBEAT}"
fi

# Telegram channel config (instance dir)
TELEGRAM_MCP="${INSTANCE_DIR}/.mcp-telegram.json"
if [ -f "$TELEGRAM_MCP" ]; then
  CHANNEL_FLAGS="${CHANNEL_FLAGS} ${TELEGRAM_MCP}"
fi

# iMessage channel — macOS only
if [ "$OS" = "Darwin" ]; then
  IMESSAGE_MCP="${INSTANCE_DIR}/.mcp-imessage.json"
  if [ -f "$IMESSAGE_MCP" ]; then
    CHANNEL_FLAGS="${CHANNEL_FLAGS} ${IMESSAGE_MCP}"
  fi
fi

attempt=0
while [ "$attempt" -lt "$MAX_RETRIES" ]; do
  attempt=$((attempt + 1))
  printf '[clawdkit] start-agent: attempt %d/%d — launching claude in %s\n' \
    "$attempt" "$MAX_RETRIES" "$INSTANCE_DIR"

  # Run claude from the instance directory so it picks up .claude/settings.json there
  (cd "$INSTANCE_DIR" && eval claude $CHANNEL_FLAGS) && {
    printf '[clawdkit] start-agent: claude exited cleanly\n'
    exit 0
  }

  EXIT_CODE=$?
  printf '[clawdkit] start-agent: claude exited with code %d\n' "$EXIT_CODE" >&2

  if [ "$attempt" -lt "$MAX_RETRIES" ]; then
    printf '[clawdkit] start-agent: retrying in %ds...\n' "$RETRY_DELAY" >&2
    sleep "$RETRY_DELAY"
  fi
done

printf '[clawdkit] start-agent: max retries (%d) reached — giving up\n' "$MAX_RETRIES" >&2
exit 1
