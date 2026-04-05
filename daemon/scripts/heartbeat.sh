#!/bin/sh
# heartbeat.sh — Scheduler-triggered heartbeat for ClawdKit daemon.
# Called by launchd (macOS) or systemd timer (Linux) every 30 minutes.
#
# Usage: heartbeat.sh <agent_name>
# Environment: CLAWDKIT_AGENT_NAME overrides $1 if set

set -e

AGENT_NAME="${CLAWDKIT_AGENT_NAME:-${1:-clawdkit}}"
INSTANCE_DIR="${HOME}/.clawdcode/${AGENT_NAME}"
LOCK_DIR="${INSTANCE_DIR}/.clawdkit/heartbeat.lock"
LOG_FILE="${INSTANCE_DIR}/.clawdkit/progress.log"
SESSION_NAME="clawdkit-${AGENT_NAME}"
HEARTBEAT_PORT="${CLAWDKIT_HEARTBEAT_PORT:-7749}"
HEARTBEAT_URL="http://127.0.0.1:${HEARTBEAT_PORT}/heartbeat"
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
# Atomic lock helpers (mkdir is POSIX-atomic on local filesystems; file locks are not)
# Note: mkdir atomicity is NOT guaranteed on NFS. If instance dir is on a
# network mount, concurrent heartbeats could both acquire the lock.
# Note: SIGKILL bypasses the EXIT trap, leaving the lock dir behind.
# The stale-lock pre-flight below handles that case on next invocation.
# ---------------------------------------------------------------------------
lock_age_seconds() {
  LOCK_TS="$(cat "${LOCK_DIR}/ts" 2>/dev/null || echo 0)"
  NOW="$(date +%s 2>/dev/null || echo 0)"
  # Fallback: if date +%s not available, skip age check (proceed)
  if [ "$NOW" = "0" ] || [ "$LOCK_TS" = "0" ]; then
    echo 99999
    return
  fi
  echo $((NOW - LOCK_TS))
}

acquire_lock() {
  mkdir "$LOCK_DIR" 2>/dev/null || return 1
  printf '%s' "$(date +%s 2>/dev/null || echo 0)" > "${LOCK_DIR}/ts"
  return 0
}

remove_lock() {
  rm -rf "$LOCK_DIR"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
mkdir -p "${INSTANCE_DIR}/.clawdkit"

# 1. Pre-flight: remove stale lock left by a prior SIGKILL or crash
if [ -d "$LOCK_DIR" ]; then
  AGE="$(lock_age_seconds)"
  if [ "$AGE" -lt "$LOCK_MAX_AGE" ]; then
    log "lock held for ${AGE}s (< ${LOCK_MAX_AGE}s) — skipping"
    exit 0
  fi
  log "stale lock (${AGE}s old) — removing"
  rm -rf "$LOCK_DIR"
fi

# 2. Acquire atomic lock (mkdir is POSIX-atomic)
if ! acquire_lock; then
  log "failed to acquire lock (race condition) — skipping"
  exit 0
fi
log "heartbeat started"

# Ensure lock is removed on clean exit (SIGKILL will bypass this)
trap 'remove_lock; log "heartbeat finished"' EXIT

# 3. Check tmux session alive
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  log "ERROR: tmux session ${SESSION_NAME} not found — daemon not running"
  exit 0
fi

# 4. Read heartbeat prompt — only send if the file exists
if [ ! -f "$HEARTBEAT_FILE" ]; then
  log "ERROR: HEARTBEAT.md not found at ${HEARTBEAT_FILE} — skipping"
  exit 0
fi
PROMPT="$(cat "$HEARTBEAT_FILE")"
if [ -z "$PROMPT" ]; then
  log "ERROR: HEARTBEAT.md is empty — skipping"
  exit 0
fi

# 5. POST to heartbeat MCP (pipe via stdin to safely handle special chars/newlines)
HTTP_CODE="$(printf '%s' "$PROMPT" | curl -s -o /dev/null -w '%{http_code}' \
  --max-time 5 \
  --connect-timeout 3 \
  -X POST \
  -H 'Content-Type: text/plain' \
  --data-binary @- \
  "$HEARTBEAT_URL" 2>/dev/null || echo "000")"

if [ "$HTTP_CODE" = "200" ]; then
  log "heartbeat sent (HTTP 200)"

  # Wait for the agent to process the heartbeat before clearing context.
  # This gives the agent time to read the prompt, execute tasks, and log progress.
  PROCESS_WAIT="${CLAWDKIT_HEARTBEAT_PROCESS_WAIT:-120}"
  log "waiting ${PROCESS_WAIT}s for agent to process heartbeat"
  sleep "$PROCESS_WAIT"

  # Clear context so the agent starts fresh for the next heartbeat cycle.
  # SessionStart hooks will re-inject persona automatically.
  tmux send-keys -t "$SESSION_NAME" "/clear" Enter 2>/dev/null && \
    log "context cleared after heartbeat" || \
    log "WARNING: failed to clear context after heartbeat"
else
  log "ERROR: heartbeat POST failed (HTTP ${HTTP_CODE}) — is the daemon running?"
fi

# 6. Truncate progress.log if > MAX_LOG_LINES
if [ -f "$LOG_FILE" ]; then
  LINE_COUNT="$(wc -l < "$LOG_FILE" | tr -d ' ')"
  if [ "$LINE_COUNT" -gt "$MAX_LOG_LINES" ]; then
    KEEP=$((MAX_LOG_LINES - 100))
    TEMP_FILE="${LOG_FILE}.tmp.$$"
    tail -n "$KEEP" "$LOG_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$LOG_FILE" || {
      rm -f "$TEMP_FILE"
      log "WARNING: log truncation failed"
    }
    log "truncated progress.log to ${KEEP} lines (was ${LINE_COUNT})"
  fi
fi
