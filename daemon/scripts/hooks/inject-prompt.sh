#!/bin/sh
# inject-prompt.sh — shared SessionStart hook helper for ClawdKit
# Usage: inject-prompt.sh <SOUL|IDENTITY|USER|TOOLS> <brain_path>
# Outputs JSON to stdout per Claude Code hook spec; exits 0 always.

PERSONA_NAME="${1:-}"
BRAIN_PATH="${2:-}"

if [ -z "$PERSONA_NAME" ] || [ -z "$BRAIN_PATH" ]; then
  printf 'inject-prompt.sh: usage: inject-prompt.sh <SOUL|IDENTITY|USER|TOOLS> <brain_path>\n' >&2
fi

PERSONA_FILE="${BRAIN_PATH}/prompts/${PERSONA_NAME}.md"

if [ -n "$BRAIN_PATH" ] && [ -f "$PERSONA_FILE" ]; then
  CONTENT="$(cat "$PERSONA_FILE")"
else
  printf 'inject-prompt.sh: %s not found or unreadable — injecting empty context\n' "$PERSONA_FILE" >&2
  CONTENT=""
fi

if command -v jq >/dev/null 2>&1; then
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}' \
    "$(printf '%s' "$CONTENT" | jq -Rs .)"
elif command -v python3 >/dev/null 2>&1; then
  ENCODED="$(printf '%s' "$CONTENT" | python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))')" || {
    printf 'inject-prompt.sh: python3 JSON encoding failed — injecting empty context\n' >&2
    ENCODED='""'
  }
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}' "$ENCODED"
else
  printf 'inject-prompt.sh: neither jq nor python3 available — injecting empty context\n' >&2
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":""}}'
fi
