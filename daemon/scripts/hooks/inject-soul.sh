#!/bin/sh
# inject-soul.sh — SessionStart hook: inject SOUL.md persona into context
# Usage: inject-soul.sh <brain_path>
# Outputs JSON to stdout per Claude Code hook spec; exits 0 always.

set -e

BRAIN_PATH="${1:-}"
PERSONA_FILE="${BRAIN_PATH}/prompts/SOUL.md"

if [ -z "$BRAIN_PATH" ]; then
  printf 'inject-soul.sh: no brain_path argument supplied\n' >&2
fi

if [ -n "$BRAIN_PATH" ] && [ -f "$PERSONA_FILE" ]; then
  CONTENT="$(cat "$PERSONA_FILE")"
else
  printf 'inject-soul.sh: %s not found or unreadable — injecting empty context\n' "$PERSONA_FILE" >&2
  CONTENT=""
fi

if command -v jq >/dev/null 2>&1; then
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}' \
    "$(printf '%s' "$CONTENT" | jq -Rs .)"
else
  # Safety check: if file is large (>50K chars), output empty context with warning
  CONTENT_LEN="${#CONTENT}"
  if [ "$CONTENT_LEN" -gt 50000 ]; then
    printf 'inject-soul.sh: file exceeds 50K chars (%d), skipping injection to avoid hook limit\n' "$CONTENT_LEN" >&2
    CONTENT=""
  fi
  # Manual JSON escaping: backslash first, then double-quote, tab, newlines
  ESCAPED="$(printf '%s' "$CONTENT" \
    | sed 's/\\/\\\\/g' \
    | sed 's/"/\\"/g' \
    | sed 's/	/\\t/g' \
    | tr '\n' '\r' \
    | sed 's/\r/\\n/g')" || {
    printf 'inject-soul.sh: JSON escaping failed — injecting empty context\n' >&2
    ESCAPED=""
  }
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}' "$ESCAPED"
fi
