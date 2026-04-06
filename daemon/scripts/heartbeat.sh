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

# 1. Pause check — exit early if paused
PAUSE_FILE="${INSTANCE_DIR}/.clawdkit/paused"
if [ -f "$PAUSE_FILE" ]; then
  log "heartbeats paused — skipping (remove ${PAUSE_FILE} or run clawdkit.sh resume)"
  exit 0
fi

# 2. Interval gate — skip if not enough time since last heartbeat
STATE_FILE="${INSTANCE_DIR}/.clawdkit/state.json"
if [ -f "$STATE_FILE" ]; then
  INTERVAL_MIN=""
  LAST_HB=""
  if command -v jq >/dev/null 2>&1; then
    INTERVAL_MIN="$(jq -r '.heartbeat_interval_minutes // empty' "$STATE_FILE" 2>/dev/null)" || INTERVAL_MIN=""
    LAST_HB="$(jq -r '.last_heartbeat // empty' "$STATE_FILE" 2>/dev/null)" || LAST_HB=""
  elif command -v python3 >/dev/null 2>&1; then
    INTERVAL_MIN="$(python3 -c "import json; d=json.load(open('$STATE_FILE')); v=d.get('heartbeat_interval_minutes'); print(v if v is not None else '')" 2>/dev/null)" || INTERVAL_MIN=""
    LAST_HB="$(python3 -c "import json; d=json.load(open('$STATE_FILE')); v=d.get('last_heartbeat',''); print(v if v else '')" 2>/dev/null)" || LAST_HB=""
  fi

  if [ -n "$INTERVAL_MIN" ] && [ "$INTERVAL_MIN" != "null" ] && [ -n "$LAST_HB" ] && [ "$LAST_HB" != "null" ]; then
    # Convert last_heartbeat ISO-8601 to epoch
    LAST_EPOCH=""
    if command -v date >/dev/null 2>&1; then
      # GNU date uses -d, BSD (macOS) date uses -jf
      LAST_EPOCH="$(date -jf '%Y-%m-%dT%H:%M:%SZ' "$LAST_HB" '+%s' 2>/dev/null)" || \
      LAST_EPOCH="$(date -d "$LAST_HB" '+%s' 2>/dev/null)" || LAST_EPOCH=""
    fi

    if [ -n "$LAST_EPOCH" ]; then
      NOW_EPOCH="$(date +%s 2>/dev/null || echo 0)"
      ELAPSED_MIN=$(( (NOW_EPOCH - LAST_EPOCH) / 60 ))
      INTERVAL_INT="${INTERVAL_MIN%%.*}"
      if [ -n "$INTERVAL_INT" ] && [ "$ELAPSED_MIN" -lt "$INTERVAL_INT" ] 2>/dev/null; then
        log "interval gate: ${ELAPSED_MIN}m since last heartbeat (interval: ${INTERVAL_INT}m) — skipping"
        exit 0
      fi
    fi
  fi
fi

# 4. Pre-flight: remove stale lock left by a prior SIGKILL or crash
if [ -d "$LOCK_DIR" ]; then
  AGE="$(lock_age_seconds)"
  if [ "$AGE" -lt "$LOCK_MAX_AGE" ]; then
    log "lock held for ${AGE}s (< ${LOCK_MAX_AGE}s) — skipping"
    exit 0
  fi
  log "stale lock (${AGE}s old) — removing"
  rm -rf "$LOCK_DIR"
fi

# 5. Acquire atomic lock (mkdir is POSIX-atomic)
if ! acquire_lock; then
  log "failed to acquire lock (race condition) — skipping"
  exit 0
fi
log "heartbeat started"

# Ensure lock is removed on clean exit (SIGKILL will bypass this)
trap 'remove_lock; log "heartbeat finished"' EXIT

# 6. Budget gate — skip heartbeat POST when rate limit usage is too high
BUDGET_SKIP=""
if [ -f "$STATE_FILE" ]; then
  # Extract budget fields via jq or python3 fallback
  if command -v jq >/dev/null 2>&1; then
    BUDGET_MODE="$(jq -r '.budget_mode // empty' "$STATE_FILE" 2>/dev/null)" || BUDGET_MODE=""
    FIVE_HOUR_PCT="$(jq -r '.five_hour_used_pct // empty' "$STATE_FILE" 2>/dev/null)" || FIVE_HOUR_PCT=""
    EXHAUSTED_PCT="$(jq -r '.exhausted_threshold_pct // empty' "$STATE_FILE" 2>/dev/null)" || EXHAUSTED_PCT=""
  elif command -v python3 >/dev/null 2>&1; then
    BUDGET_MODE="$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('budget_mode',''))" 2>/dev/null)" || BUDGET_MODE=""
    FIVE_HOUR_PCT="$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('five_hour_used_pct',''))" 2>/dev/null)" || FIVE_HOUR_PCT=""
    EXHAUSTED_PCT="$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('exhausted_threshold_pct',''))" 2>/dev/null)" || EXHAUSTED_PCT=""
  else
    log "WARNING: neither jq nor python3 available — skipping budget check (fail-open)"
  fi

  # Gate 1: budget_mode explicitly set to exhausted by the agent
  if [ "$BUDGET_MODE" = "exhausted" ]; then
    BUDGET_SKIP="budget_mode is exhausted"
  fi

  # Gate 2: 5-hour rate limit exceeds exhausted threshold (default 95%)
  if [ -z "$BUDGET_SKIP" ] && [ -n "$FIVE_HOUR_PCT" ] && [ "$FIVE_HOUR_PCT" != "null" ]; then
    THRESHOLD="${EXHAUSTED_PCT:-95}"
    # Compare as integers (truncate decimals)
    FIVE_HOUR_INT="${FIVE_HOUR_PCT%%.*}"
    if [ -n "$FIVE_HOUR_INT" ] && [ "$FIVE_HOUR_INT" -ge "$THRESHOLD" ] 2>/dev/null; then
      BUDGET_SKIP="5h rate limit at ${FIVE_HOUR_PCT}% (threshold: ${THRESHOLD}%)"
    fi
  fi
fi

if [ -n "$BUDGET_SKIP" ]; then
  log "budget gate — skipping heartbeat POST ($BUDGET_SKIP)"
  exit 0
fi

# 7. Check tmux session alive
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  log "ERROR: tmux session ${SESSION_NAME} not found — daemon not running"
  exit 0
fi

# 7. Read heartbeat prompt — only send if the file exists
if [ ! -f "$HEARTBEAT_FILE" ]; then
  log "ERROR: HEARTBEAT.md not found at ${HEARTBEAT_FILE} — skipping"
  exit 0
fi
PROMPT="$(cat "$HEARTBEAT_FILE")"
if [ -z "$PROMPT" ]; then
  log "ERROR: HEARTBEAT.md is empty — skipping"
  exit 0
fi

# 8. POST to heartbeat MCP (pipe via stdin to safely handle special chars/newlines)
HTTP_CODE="$(printf '%s' "$PROMPT" | curl -s -o /dev/null -w '%{http_code}' \
  --max-time 5 \
  --connect-timeout 3 \
  -X POST \
  -H 'Content-Type: text/plain' \
  --data-binary @- \
  "$HEARTBEAT_URL" 2>/dev/null || echo "000")"

if [ "$HTTP_CODE" = "200" ]; then
  log "heartbeat sent (HTTP 200)"
else
  log "ERROR: heartbeat POST failed (HTTP ${HTTP_CODE}) — is the daemon running?"
fi

# 9. Truncate progress.log if > MAX_LOG_LINES
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
