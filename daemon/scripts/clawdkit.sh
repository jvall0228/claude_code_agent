#!/bin/sh
# clawdkit.sh — ClawdKit daemon manager
# Subcommands: start | stop | restart | status | health | install | uninstall
# Flag: --instance <name>  (default: clawdkit)
#
# Usage:
#   clawdkit.sh [--instance <name>] <subcommand>
#   clawdkit.sh start
#   clawdkit.sh stop --instance myagent

set -e

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
INSTANCE="clawdkit"
CLAWDCODE_ROOT="${HOME}/.clawdcode"

# Resolve the directory this script lives in (POSIX-safe)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAWDKIT_SCRIPTS_PATH="$SCRIPT_DIR"

# The heartbeat MCP json lives at daemon/mcp/heartbeat/.mcp.json
# Walk up from scripts/ to find the daemon/ root
DAEMON_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MCP_HEARTBEAT="${DAEMON_DIR}/mcp/heartbeat/.mcp.json"

OS="$(uname -s)"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
SUBCOMMAND=""

while [ $# -gt 0 ]; do
  case "$1" in
    --instance)
      shift
      INSTANCE="${1:?--instance requires a value}"
      ;;
    start|stop|restart|status|health|install|uninstall)
      SUBCOMMAND="$1"
      ;;
    *)
      printf 'clawdkit: unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

if [ -z "$SUBCOMMAND" ]; then
  printf 'Usage: clawdkit.sh [--instance <name>] <start|stop|restart|status|health|install|uninstall>\n' >&2
  exit 1
fi

SESSION_NAME="clawdkit-${INSTANCE}"
INSTANCE_DIR="${CLAWDCODE_ROOT}/${INSTANCE}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
session_exists() {
  tmux has-session -t "$SESSION_NAME" 2>/dev/null
}

do_start() {
  if session_exists; then
    printf 'clawdkit: session %s already running\n' "$SESSION_NAME"
    return 0
  fi

  # Ensure instance directory exists
  mkdir -p "$INSTANCE_DIR"

  printf 'clawdkit: starting session %s\n' "$SESSION_NAME"

  # Export env for start-agent.sh
  export CLAWDKIT_AGENT_NAME="$INSTANCE"
  export CLAWDKIT_INSTANCE_DIR="$INSTANCE_DIR"
  export CLAWDKIT_SCRIPTS_PATH="$CLAWDKIT_SCRIPTS_PATH"
  export CLAWDKIT_MCP_HEARTBEAT="$MCP_HEARTBEAT"

  # Create detached tmux session; set remain-on-exit so pane stays after crash
  tmux new-session -d -s "$SESSION_NAME" \
    -x 220 -y 50 \
    "${CLAWDKIT_SCRIPTS_PATH}/start-agent.sh"

  # Keep the window around after the command exits (lets us inspect output)
  tmux set-option -t "$SESSION_NAME" remain-on-exit on

  printf 'clawdkit: session %s started\n' "$SESSION_NAME"
}

do_stop() {
  if ! session_exists; then
    printf 'clawdkit: no session named %s\n' "$SESSION_NAME"
    return 0
  fi
  printf 'clawdkit: stopping session %s\n' "$SESSION_NAME"
  tmux kill-session -t "$SESSION_NAME"
  printf 'clawdkit: session %s stopped\n' "$SESSION_NAME"
}

do_status() {
  if session_exists; then
    printf 'clawdkit: %s is RUNNING\n' "$SESSION_NAME"
  else
    printf 'clawdkit: %s is STOPPED\n' "$SESSION_NAME"
  fi
}

do_health() {
  if ! session_exists; then
    printf 'clawdkit: %s — no session found\n' "$SESSION_NAME" >&2
    exit 1
  fi
  tmux display-message -t "$SESSION_NAME" -p "#{session_name}: pane_pid=#{pane_pid} pane_dead=#{pane_dead} window_active=#{window_active}"
}

do_install() {
  printf 'clawdkit install: full scheduler integration coming in Unit 5.\n'
  printf 'Use: make install INSTANCE=%s\n' "$INSTANCE"
  printf 'OS detected: %s\n' "$OS"
  if [ "$OS" = "Darwin" ]; then
    printf 'Platform: launchd (macOS) — stub only\n'
  else
    printf 'Platform: systemd (Linux) — stub only\n'
  fi
}

do_uninstall() {
  printf 'clawdkit uninstall: full scheduler integration coming in Unit 5.\n'
  printf 'Use: make uninstall INSTANCE=%s\n' "$INSTANCE"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "$SUBCOMMAND" in
  start)   do_start ;;
  stop)    do_stop ;;
  restart) do_stop; do_start ;;
  status)  do_status ;;
  health)  do_health ;;
  install)   do_install ;;
  uninstall) do_uninstall ;;
esac
