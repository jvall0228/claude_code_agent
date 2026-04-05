#!/bin/sh
# inject-identity.sh — SessionStart hook: inject IDENTITY.md persona into context
# Usage: inject-identity.sh <brain_path>
# Outputs JSON to stdout per Claude Code hook spec; exits 0 always.

set -e

BRAIN_PATH="${1:-}"
PERSONA_FILE="${BRAIN_PATH}/prompts/IDENTITY.md"

if [ -z "$BRAIN_PATH" ]; then
  printf 'inject-identity.sh: no brain_path argument supplied\n' >&2
fi

if [ -n "$BRAIN_PATH" ] && [ -f "$PERSONA_FILE" ]; then
  CONTENT="$(cat "$PERSONA_FILE")"
else
  printf 'inject-identity.sh: %s not found or unreadable — injecting empty context\n' "$PERSONA_FILE" >&2
  CONTENT=""
fi

if command -v jq >/dev/null 2>&1; then
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}' \
    "$(printf '%s' "$CONTENT" | jq -Rs .)"
else
  CONTENT_LEN="${#CONTENT}"
  if [ "$CONTENT_LEN" -gt 50000 ]; then
    printf 'inject-identity.sh: file exceeds 50K chars (%d), skipping injection to avoid hook limit\n' "$CONTENT_LEN" >&2
    CONTENT=""
  fi
  ESCAPED="$(printf '%s' "$CONTENT" \
    | sed 's/\\/\\\\/g' \
    | sed 's/"/\\"/g' \
    | sed 's/	/\\t/g' \
    | tr '\n' '\r' \
    | sed 's/\r/\\n/g')" || {
    printf 'inject-identity.sh: JSON escaping failed — injecting empty context\n' >&2
    ESCAPED=""
  }
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}' "$ESCAPED"
fi
