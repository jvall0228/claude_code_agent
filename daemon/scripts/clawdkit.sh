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
  TEMPLATES_DIR="$(cd "${DAEMON_DIR}/config" && pwd)"

  if [ "$OS" = "Darwin" ]; then
    # macOS: launchd plist
    PLIST_LABEL="com.clawdkit.heartbeat.${INSTANCE}"
    PLIST_DEST="${HOME}/Library/LaunchAgents/${PLIST_LABEL}.plist"
    PLIST_SRC="${TEMPLATES_DIR}/com.clawdkit.heartbeat.plist"

    if [ ! -f "$PLIST_SRC" ]; then
      printf 'clawdkit install: plist template not found at %s\n' "$PLIST_SRC" >&2
      exit 1
    fi

    # Stamp placeholders
    mkdir -p "${HOME}/Library/LaunchAgents"
    sed \
      -e "s|{{AGENT_NAME}}|${INSTANCE}|g" \
      -e "s|{{CLAWDKIT_SCRIPTS_PATH}}|${CLAWDKIT_SCRIPTS_PATH}|g" \
      -e "s|{{INSTANCE_DIR}}|${INSTANCE_DIR}|g" \
      -e "s|{{HOME}}|${HOME}|g" \
      "$PLIST_SRC" > "$PLIST_DEST"
    chmod 644 "$PLIST_DEST"

    # Validate
    plutil -lint "$PLIST_DEST" || { printf 'clawdkit install: plist validation failed\n' >&2; exit 1; }

    # Load via launchctl bootstrap (current macOS API)
    launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST"
    printf 'clawdkit install: launchd job %s installed and loaded\n' "$PLIST_LABEL"

  else
    # Linux: systemd user timer
    SYSTEMD_DIR="${HOME}/.config/systemd/user"
    SERVICE_NAME="clawdkit-heartbeat-${INSTANCE}"
    SERVICE_SRC="${TEMPLATES_DIR}/clawdkit-heartbeat.service"
    TIMER_SRC="${TEMPLATES_DIR}/clawdkit-heartbeat.timer"
    SERVICE_DEST="${SYSTEMD_DIR}/${SERVICE_NAME}.service"
    TIMER_DEST="${SYSTEMD_DIR}/${SERVICE_NAME}.timer"

    if [ ! -f "$SERVICE_SRC" ] || [ ! -f "$TIMER_SRC" ]; then
      printf 'clawdkit install: systemd templates not found in %s\n' "$TEMPLATES_DIR" >&2
      exit 1
    fi

    mkdir -p "$SYSTEMD_DIR"

    # Stamp placeholders
    sed \
      -e "s|{{AGENT_NAME}}|${INSTANCE}|g" \
      -e "s|{{CLAWDKIT_SCRIPTS_PATH}}|${CLAWDKIT_SCRIPTS_PATH}|g" \
      -e "s|{{INSTANCE_DIR}}|${INSTANCE_DIR}|g" \
      -e "s|{{HOME}}|${HOME}|g" \
      "$SERVICE_SRC" > "$SERVICE_DEST"

    sed \
      -e "s|{{AGENT_NAME}}|${INSTANCE}|g" \
      "$TIMER_SRC" > "$TIMER_DEST"

    systemctl --user daemon-reload
    systemctl --user enable --now "${SERVICE_NAME}.timer"
    printf 'clawdkit install: systemd timer %s.timer enabled\n' "$SERVICE_NAME"
    printf 'clawdkit install: run `loginctl enable-linger` to keep timer active when logged out\n'
  fi
}

do_uninstall() {
  if [ "$OS" = "Darwin" ]; then
    PLIST_LABEL="com.clawdkit.heartbeat.${INSTANCE}"
    PLIST_DEST="${HOME}/Library/LaunchAgents/${PLIST_LABEL}.plist"

    if launchctl list "$PLIST_LABEL" >/dev/null 2>&1; then
      launchctl bootout "gui/$(id -u)" "$PLIST_DEST" 2>/dev/null || \
        launchctl remove "$PLIST_LABEL" 2>/dev/null || true
    fi

    rm -f "$PLIST_DEST"
    printf 'clawdkit uninstall: launchd job %s removed\n' "$PLIST_LABEL"

  else
    SERVICE_NAME="clawdkit-heartbeat-${INSTANCE}"
    SYSTEMD_DIR="${HOME}/.config/systemd/user"

    systemctl --user disable --now "${SERVICE_NAME}.timer" 2>/dev/null || true
    rm -f "${SYSTEMD_DIR}/${SERVICE_NAME}.service" "${SYSTEMD_DIR}/${SERVICE_NAME}.timer"
    systemctl --user daemon-reload
    printf 'clawdkit uninstall: systemd timer %s.timer removed\n' "$SERVICE_NAME"
  fi
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
