#!/bin/sh
# inject-tools.sh — SessionStart hook: inject TOOLS.md persona into context
# Usage: inject-tools.sh <brain_path>
# Outputs JSON to stdout per Claude Code hook spec; exits 0 always.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "${SCRIPT_DIR}/inject-prompt.sh" TOOLS "${1:-}"
