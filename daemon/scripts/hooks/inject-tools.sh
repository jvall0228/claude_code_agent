#!/bin/sh
# inject-tools.sh — SessionStart hook: inject TOOLS.md persona into context
# Usage: inject-tools.sh <brain_path>
# Outputs JSON to stdout per Claude Code hook spec; exits 0 always.

set -e

BRAIN_PATH="${1:-}"
PERSONA_FILE="${BRAIN_PATH}/prompts/TOOLS.md"

if [ -z "$BRAIN_PATH" ]; then
  printf 'inject-tools.sh: no brain_path argument supplied\n' >&2
fi

if [ -n "$BRAIN_PATH" ] && [ -f "$PERSONA_FILE" ]; then
  CONTENT="$(cat "$PERSONA_FILE")"
else
  printf 'inject-tools.sh: %s not found or unreadable — injecting empty context\n' "$PERSONA_FILE" >&2
  CONTENT=""
fi

if command -v jq >/dev/null 2>&1; then
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}' \
    "$(printf '%s' "$CONTENT" | jq -Rs .)"
else
  ESCAPED="$(printf '%s' "$CONTENT" \
    | sed 's/\\/\\\\/g' \
    | sed 's/"/\\"/g' \
    | sed 's/	/\\t/g' \
    | tr '\n' '\r' \
    | sed 's/\r/\\n/g')"
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}' "$ESCAPED"
fi
