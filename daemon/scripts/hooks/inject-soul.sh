#!/bin/sh
# inject-soul.sh — SessionStart hook: inject SOUL.md persona into context
# Usage: inject-soul.sh <brain_path>
# Outputs JSON to stdout per Claude Code hook spec; exits 0 always.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "${SCRIPT_DIR}/inject-prompt.sh" SOUL "${1:-}"
