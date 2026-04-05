#!/bin/sh
# inject-user.sh — SessionStart hook: inject USER.md persona into context
# Usage: inject-user.sh <brain_path>
# Outputs JSON to stdout per Claude Code hook spec; exits 0 always.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "${SCRIPT_DIR}/inject-prompt.sh" USER "${1:-}"
