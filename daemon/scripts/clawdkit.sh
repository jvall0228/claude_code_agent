#!/bin/sh
# clawdkit.sh — ClawdKit daemon manager
# Subcommands: start | stop | restart | status | health | pause | resume | install | uninstall
# Flag: --instance <name>  (default: clawdkit)
# Flag: --json             (machine-readable output for health)
# Flag: --debug            (enable debug channels like fakechat)
#
# Usage:
#   clawdkit.sh [--instance <name>] [--json] [--debug] <subcommand>
#   clawdkit.sh start
#   clawdkit.sh --debug start
#   clawdkit.sh stop --instance myagent
#   clawdkit.sh health --json

set -e

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
INSTANCE="clawdkit"
JSON_OUTPUT=""
DEBUG_MODE=""
CLAWDCODE_ROOT="${HOME}/.clawdcode"
HEARTBEAT_PORT="${CLAWDKIT_HEARTBEAT_PORT:-7749}"

# Resolve the directory this script lives in (POSIX-safe)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAWDKIT_SCRIPTS_PATH="$SCRIPT_DIR"

# Walk up from scripts/ to find the daemon/ root
DAEMON_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# MCP_HEARTBEAT is set per-instance after the instance name is known (see do_start)

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
    --json)
      JSON_OUTPUT=1
      ;;
    --debug)
      DEBUG_MODE=1
      ;;
    start|stop|restart|status|health|clear|pause|resume|install|uninstall)
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
  printf 'Usage: clawdkit.sh [--instance <name>] [--json] [--debug] <start|stop|restart|status|health|clear|pause|resume|install|uninstall>\n' >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Validate instance name: must match [a-zA-Z0-9][a-zA-Z0-9-]*
# ---------------------------------------------------------------------------
case "$INSTANCE" in
  '') printf 'clawdkit: instance name cannot be empty\n' >&2; exit 1 ;;
  *[!a-zA-Z0-9-]*) printf 'clawdkit: invalid instance name "%s" — only alphanumeric and hyphens allowed\n' "$INSTANCE" >&2; exit 1 ;;
  [-]*) printf 'clawdkit: invalid instance name "%s" — must not start with a hyphen\n' "$INSTANCE" >&2; exit 1 ;;
esac

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
  # Use the per-instance stamped MCP config (created by bootstrap.sh), not the raw template
  MCP_HEARTBEAT="${INSTANCE_DIR}/.mcp-heartbeat.json"
  export CLAWDKIT_AGENT_NAME="$INSTANCE"
  export CLAWDKIT_INSTANCE_DIR="$INSTANCE_DIR"
  export CLAWDKIT_SCRIPTS_PATH="$CLAWDKIT_SCRIPTS_PATH"
  export CLAWDKIT_MCP_HEARTBEAT="$MCP_HEARTBEAT"
  export CLAWDKIT_HEARTBEAT_PORT="$HEARTBEAT_PORT"
  export CLAWDKIT_DEBUG="${DEBUG_MODE:-0}"

  # Create detached tmux session; set remain-on-exit so pane stays after crash
  tmux new-session -d -s "$SESSION_NAME" \
    -x 220 -y 50 \
    "${CLAWDKIT_SCRIPTS_PATH}/start-agent.sh"

  # Keep the window around after the command exits (lets us inspect output)
  tmux set-option -t "$SESSION_NAME" remain-on-exit on

  # Auto-confirm the dev channels prompt after claude starts
  # Claude Code uses raw tty input, so we send Enter via tmux after a delay
  (sleep 20 && tmux send-keys -t "$SESSION_NAME" Enter) &

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
  PAUSE_FILE="${INSTANCE_DIR}/.clawdkit/paused"
  if session_exists; then
    if [ -f "$PAUSE_FILE" ]; then
      printf 'clawdkit: %s is RUNNING (heartbeats paused)\n' "$SESSION_NAME"
    else
      printf 'clawdkit: %s is RUNNING\n' "$SESSION_NAME"
    fi
    exit 0
  else
    printf 'clawdkit: %s is STOPPED\n' "$SESSION_NAME"
    exit 1
  fi
}

do_health() {
  if ! session_exists; then
    if [ -n "$JSON_OUTPUT" ]; then
      printf '{"running":false,"session":"%s"}\n' "$SESSION_NAME"
    else
      printf 'clawdkit: %s — no session found\n' "$SESSION_NAME" >&2
    fi
    exit 1
  fi
  # Read budget status from state.json
  STATE_FILE="${INSTANCE_DIR}/.clawdkit/state.json"
  BUDGET_MODE=""
  FIVE_HOUR_PCT=""
  SEVEN_DAY_PCT=""
  USAGE_UPDATED=""
  if [ -f "$STATE_FILE" ]; then
    if command -v jq >/dev/null 2>&1; then
      BUDGET_MODE="$(jq -r '.budget_mode // empty' "$STATE_FILE" 2>/dev/null)" || BUDGET_MODE=""
      FIVE_HOUR_PCT="$(jq -r '.five_hour_used_pct // empty' "$STATE_FILE" 2>/dev/null)" || FIVE_HOUR_PCT=""
      SEVEN_DAY_PCT="$(jq -r '.seven_day_used_pct // empty' "$STATE_FILE" 2>/dev/null)" || SEVEN_DAY_PCT=""
      USAGE_UPDATED="$(jq -r '.usage_updated_at // empty' "$STATE_FILE" 2>/dev/null)" || USAGE_UPDATED=""
    elif command -v python3 >/dev/null 2>&1; then
      BUDGET_MODE="$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('budget_mode',''))" 2>/dev/null)" || BUDGET_MODE=""
      FIVE_HOUR_PCT="$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('five_hour_used_pct',''))" 2>/dev/null)" || FIVE_HOUR_PCT=""
      SEVEN_DAY_PCT="$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('seven_day_used_pct',''))" 2>/dev/null)" || SEVEN_DAY_PCT=""
      USAGE_UPDATED="$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('usage_updated_at',''))" 2>/dev/null)" || USAGE_UPDATED=""
    fi
  fi

  if [ -n "$JSON_OUTPUT" ]; then
    PANE_PID="$(tmux display-message -t "$SESSION_NAME" -p '#{pane_pid}')"
    PANE_DEAD="$(tmux display-message -t "$SESSION_NAME" -p '#{pane_dead}')"
    WINDOW_ACTIVE="$(tmux display-message -t "$SESSION_NAME" -p '#{window_active}')"
    # Default to 0 if tmux returns empty to keep JSON valid
    PANE_PID="${PANE_PID:-0}"
    PANE_DEAD="${PANE_DEAD:-0}"
    WINDOW_ACTIVE="${WINDOW_ACTIVE:-0}"
    if [ -n "$BUDGET_MODE" ]; then
      printf '{"running":true,"session":"%s","pane_pid":%s,"pane_dead":%s,"window_active":%s,"budget_mode":"%s","five_hour_used_pct":%s,"seven_day_used_pct":%s}\n' \
        "$SESSION_NAME" "$PANE_PID" "$PANE_DEAD" "$WINDOW_ACTIVE" \
        "$BUDGET_MODE" "${FIVE_HOUR_PCT:-null}" "${SEVEN_DAY_PCT:-null}"
    else
      printf '{"running":true,"session":"%s","pane_pid":%s,"pane_dead":%s,"window_active":%s}\n' \
        "$SESSION_NAME" "$PANE_PID" "$PANE_DEAD" "$WINDOW_ACTIVE"
    fi
  else
    tmux display-message -t "$SESSION_NAME" -p "#{session_name}: pane_pid=#{pane_pid} pane_dead=#{pane_dead} window_active=#{window_active}"
    if [ -n "$FIVE_HOUR_PCT" ] && [ "$FIVE_HOUR_PCT" != "null" ]; then
      printf '  budget: %s | 5h: %s%%' "${BUDGET_MODE:-normal}" "$FIVE_HOUR_PCT"
      if [ -n "$SEVEN_DAY_PCT" ] && [ "$SEVEN_DAY_PCT" != "null" ]; then
        printf ' | 7d: %s%%' "$SEVEN_DAY_PCT"
      fi
      printf '\n'
      if [ -n "$USAGE_UPDATED" ]; then
        printf '  last update: %s\n' "$USAGE_UPDATED"
      fi
    elif [ -n "$BUDGET_MODE" ]; then
      printf '  budget: %s (rate limit data not yet available)\n' "$BUDGET_MODE"
    else
      printf '  budget tracking: not configured\n'
    fi
  fi
  exit 0
}

do_clear() {
  if ! session_exists; then
    printf 'clawdkit: no session named %s\n' "$SESSION_NAME" >&2
    exit 1
  fi
  printf 'clawdkit: sending /clear to %s\n' "$SESSION_NAME"
  tmux send-keys -t "$SESSION_NAME" "/clear" Enter
  printf 'clawdkit: context window cleared for %s\n' "$SESSION_NAME"
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

do_pause() {
  PAUSE_FILE="${INSTANCE_DIR}/.clawdkit/paused"
  if [ -f "$PAUSE_FILE" ]; then
    printf 'clawdkit: heartbeats already paused for %s\n' "$SESSION_NAME"
    return 0
  fi
  mkdir -p "${INSTANCE_DIR}/.clawdkit"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$PAUSE_FILE"
  printf 'clawdkit: heartbeats paused for %s\n' "$SESSION_NAME"
}

do_resume() {
  PAUSE_FILE="${INSTANCE_DIR}/.clawdkit/paused"
  if [ ! -f "$PAUSE_FILE" ]; then
    printf 'clawdkit: heartbeats not paused for %s\n' "$SESSION_NAME"
    return 0
  fi
  rm -f "$PAUSE_FILE"
  printf 'clawdkit: heartbeats resumed for %s\n' "$SESSION_NAME"
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
  clear)   do_clear ;;
  pause)   do_pause ;;
  resume)  do_resume ;;
  install)   do_install ;;
  uninstall) do_uninstall ;;
esac
