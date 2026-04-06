#!/bin/sh
# statusline.sh — Claude Code status line hook for ClawdKit daemon.
# Receives JSON payload via stdin after every assistant message.
# Writes rate limit and token usage data to state.json.
#
# Usage: Configured in .claude/settings.json as:
#   "statusLine": { "type": "command", "command": "/path/to/statusline.sh <instance_dir>" }

set -e

INSTANCE_DIR="${1:-${CLAWDKIT_INSTANCE_DIR:-}}"
if [ -z "$INSTANCE_DIR" ]; then
  exit 0
fi

STATE_FILE="${INSTANCE_DIR}/.clawdkit/state.json"
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Read JSON payload from stdin
PAYLOAD="$(cat)"
if [ -z "$PAYLOAD" ]; then
  exit 0
fi

# Extract fields — prefer jq, fall back to python3
if command -v jq >/dev/null 2>&1; then
  FIVE_HOUR_PCT="$(printf '%s' "$PAYLOAD" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)" || FIVE_HOUR_PCT=""
  FIVE_HOUR_RESETS="$(printf '%s' "$PAYLOAD" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)" || FIVE_HOUR_RESETS=""
  SEVEN_DAY_PCT="$(printf '%s' "$PAYLOAD" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)" || SEVEN_DAY_PCT=""
  SEVEN_DAY_RESETS="$(printf '%s' "$PAYLOAD" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)" || SEVEN_DAY_RESETS=""
  TOTAL_INPUT="$(printf '%s' "$PAYLOAD" | jq -r '.context_window.total_input_tokens // empty' 2>/dev/null)" || TOTAL_INPUT=""
  TOTAL_OUTPUT="$(printf '%s' "$PAYLOAD" | jq -r '.context_window.total_output_tokens // empty' 2>/dev/null)" || TOTAL_OUTPUT=""
  COST_USD="$(printf '%s' "$PAYLOAD" | jq -r '.cost.total_cost_usd // empty' 2>/dev/null)" || COST_USD=""
elif command -v python3 >/dev/null 2>&1; then
  eval "$(printf '%s' "$PAYLOAD" | python3 -c "
import json, sys
d = json.load(sys.stdin)
rl = d.get('rate_limits', {})
fh = rl.get('five_hour', {})
sd = rl.get('seven_day', {})
cw = d.get('context_window', {})
cost = d.get('cost', {})
print(f'FIVE_HOUR_PCT={fh.get(\"used_percentage\", \"\")}')
print(f'FIVE_HOUR_RESETS={fh.get(\"resets_at\", \"\")}')
print(f'SEVEN_DAY_PCT={sd.get(\"used_percentage\", \"\")}')
print(f'SEVEN_DAY_RESETS={sd.get(\"resets_at\", \"\")}')
print(f'TOTAL_INPUT={cw.get(\"total_input_tokens\", \"\")}')
print(f'TOTAL_OUTPUT={cw.get(\"total_output_tokens\", \"\")}')
print(f'COST_USD={cost.get(\"total_cost_usd\", \"\")}')
" 2>/dev/null)" || exit 0
else
  exit 0
fi

# Skip if no rate limit data available (non-subscriber or first turn)
if [ -z "$FIVE_HOUR_PCT" ] && [ -z "$TOTAL_INPUT" ]; then
  exit 0
fi

# Update state.json — merge rate limit fields into existing state
# Use jq if available for atomic JSON merge; fall back to python3
if command -v jq >/dev/null 2>&1; then
  TEMP_FILE="${STATE_FILE}.statusline.$$"
  jq \
    --argjson fh_pct "${FIVE_HOUR_PCT:-null}" \
    --argjson fh_resets "${FIVE_HOUR_RESETS:-null}" \
    --argjson sd_pct "${SEVEN_DAY_PCT:-null}" \
    --argjson sd_resets "${SEVEN_DAY_RESETS:-null}" \
    --argjson input "${TOTAL_INPUT:-null}" \
    --argjson output "${TOTAL_OUTPUT:-null}" \
    --argjson cost "${COST_USD:-null}" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.five_hour_used_pct = $fh_pct |
     .five_hour_resets_at = $fh_resets |
     .seven_day_used_pct = $sd_pct |
     .seven_day_resets_at = $sd_resets |
     .session_input_tokens = $input |
     .session_output_tokens = $output |
     .session_cost_usd = $cost |
     .usage_updated_at = $updated' \
    "$STATE_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$STATE_FILE" || rm -f "$TEMP_FILE"
elif command -v python3 >/dev/null 2>&1; then
  python3 -c "
import json, sys, os, datetime
state_path = '$STATE_FILE'
with open(state_path) as f:
    state = json.load(f)
def maybe_num(v):
    if v == '': return None
    try: return float(v)
    except: return None
state['five_hour_used_pct'] = maybe_num('$FIVE_HOUR_PCT')
state['five_hour_resets_at'] = maybe_num('$FIVE_HOUR_RESETS')
state['seven_day_used_pct'] = maybe_num('$SEVEN_DAY_PCT')
state['seven_day_resets_at'] = maybe_num('$SEVEN_DAY_RESETS')
state['session_input_tokens'] = maybe_num('$TOTAL_INPUT')
state['session_output_tokens'] = maybe_num('$TOTAL_OUTPUT')
state['session_cost_usd'] = maybe_num('$COST_USD')
state['usage_updated_at'] = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
tmp = state_path + '.statusline.' + str(os.getpid())
with open(tmp, 'w') as f:
    json.dump(state, f, indent=2)
os.rename(tmp, state_path)
" 2>/dev/null || true
fi

# Output for status line display (shown in Claude Code UI)
if [ -n "$FIVE_HOUR_PCT" ]; then
  printf '5h: %s%%' "$FIVE_HOUR_PCT"
  if [ -n "$SEVEN_DAY_PCT" ]; then
    printf ' | 7d: %s%%' "$SEVEN_DAY_PCT"
  fi
else
  printf 'tokens: %s in / %s out' "${TOTAL_INPUT:-0}" "${TOTAL_OUTPUT:-0}"
fi
