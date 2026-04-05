#!/bin/sh
# inject-identity.sh — SessionStart hook: inject IDENTITY.md persona into context
# Usage: inject-identity.sh <brain_path>
# Outputs JSON to stdout per Claude Code hook spec; exits 0 always.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "${SCRIPT_DIR}/inject-prompt.sh" IDENTITY "${1:-}"
