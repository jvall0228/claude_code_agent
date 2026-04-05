#!/bin/sh
# heartbeat.sh — Scheduler-triggered heartbeat for ClawdKit daemon.
# Called by launchd (macOS) or systemd timer (Linux) every 30 minutes.
#
# Usage: heartbeat.sh <agent_name>
# Environment: CLAWDKIT_AGENT_NAME overrides $1 if set

set -e

AGENT_NAME="${CLAWDKIT_AGENT_NAME:-${1:-clawdkit}}"
INSTANCE_DIR="${HOME}/.clawdcode/${AGENT_NAME}"
LOCK_FILE="${INSTANCE_DIR}/.clawdkit/heartbeat.lock"
LOG_FILE="${INSTANCE_DIR}/.clawdkit/progress.log"
SESSION_NAME="clawdkit-${AGENT_NAME}"
HEARTBEAT_URL="http://127.0.0.1:7749/heartbeat"
HEARTBEAT_FILE="${INSTANCE_DIR}/prompts/HEARTBEAT.md"
MAX_LOG_LINES=1000
LOCK_MAX_AGE=1500  # 25 minutes in seconds

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() {
  TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '[%s] [heartbeat:%s] %s\n' "$TS" "$AGENT_NAME" "$1" >> "$LOG_FILE" 2>/dev/null || true
  printf '[%s] [heartbeat:%s] %s\n' "$TS" "$AGENT_NAME" "$1"
}

# ---------------------------------------------------------------------------
# Lock file helpers (POSIX-compatible timestamp comparison)
# ---------------------------------------------------------------------------
lock_age_seconds() {
  LOCK_TS="$(cat "$LOCK_FILE" 2>/dev/null || echo 0)"
  NOW="$(date +%s 2>/dev/null || echo 0)"
  # Fallback: if date +%s not available, skip age check (proceed)
  if [ "$NOW" = "0" ] || [ "$LOCK_TS" = "0" ]; then
    echo 99999
    return
  fi
  echo $((NOW - LOCK_TS))
}

check_lock() {
  if [ ! -f "$LOCK_FILE" ]; then
    return 0  # No lock — proceed
  fi
  AGE="$(lock_age_seconds)"
  if [ "$AGE" -lt "$LOCK_MAX_AGE" ]; then
    log "lock held for ${AGE}s (< ${LOCK_MAX_AGE}s) — skipping"
    return 1  # Recent lock — skip
  fi
  log "stale lock (${AGE}s old) — proceeding"
  return 0  # Stale lock — proceed
}

create_lock() {
  mkdir -p "$(dirname "$LOCK_FILE")"
  date +%s > "$LOCK_FILE" 2>/dev/null || printf '0' > "$LOCK_FILE"
}

remove_lock() {
  rm -f "$LOCK_FILE"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
mkdir -p "${INSTANCE_DIR}/.clawdkit"

# 1. Check lock
check_lock || exit 0

# 2. Create lock
create_lock
log "heartbeat started"

# Ensure lock is removed on exit (even on error)
trap 'remove_lock; log "heartbeat finished"' EXIT

# 3. Check tmux session alive
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  log "ERROR: tmux session ${SESSION_NAME} not found — daemon not running"
  exit 0
fi

# 4. Read heartbeat prompt
if [ -f "$HEARTBEAT_FILE" ]; then
  PROMPT="$(cat "$HEARTBEAT_FILE")"
else
  PROMPT="Heartbeat: no HEARTBEAT.md found at ${HEARTBEAT_FILE}. Check status and log."
  log "WARNING: HEARTBEAT.md not found at ${HEARTBEAT_FILE}"
fi

# 5. POST to heartbeat MCP
HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' \
  -X POST \
  -H 'Content-Type: text/plain' \
  --data-raw "$PROMPT" \
  "$HEARTBEAT_URL" 2>/dev/null || echo "000")"

if [ "$HTTP_CODE" = "200" ]; then
  log "heartbeat sent (HTTP 200)"
else
  log "ERROR: heartbeat POST failed (HTTP ${HTTP_CODE}) — is the daemon running?"
fi

# 6. Truncate progress.log if > MAX_LOG_LINES
if [ -f "$LOG_FILE" ]; then
  LINE_COUNT="$(wc -l < "$LOG_FILE" | tr -d ' ')"
  if [ "$LINE_COUNT" -gt "$MAX_LOG_LINES" ]; then
    KEEP=$((MAX_LOG_LINES - 100))
    TEMP_FILE="${LOG_FILE}.tmp.$$"
    tail -n "$KEEP" "$LOG_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$LOG_FILE"
    log "truncated progress.log to ${KEEP} lines (was ${LINE_COUNT})"
  fi
fi
