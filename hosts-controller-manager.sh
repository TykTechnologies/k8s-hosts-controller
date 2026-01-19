#!/usr/bin/env bash
set -euo pipefail

CONTROLLER_PID=""

###############
# configuration
###############
CONTROLLER_BINARY="${CONTROLLER_BINARY:-k8s-hosts-controller}"
HOSTS_MARKER="${HOSTS_MARKER:-TYK-K8S-HOSTS}"
LOG_FILE="${LOG_FILE:-/tmp/k8s-hosts-controller.log}"
NAMESPACES="${NAMESPACES:-}"
GRACEFUL_SHUTDOWN_TIMEOUT=30
STARTUP_WAIT_TIME=2

log() { echo "[INFO] $*" >&2; }
warning() { echo "[WARNING] $*" >&2; }
err() { echo "[ERROR] $*" >&2; }

check_sudo() {
  if ! sudo -n true 2> /dev/null; then
    log "Sudo access required to modify /etc/hosts"

    if ! sudo -v; then
      err "Failed to acquire sudo access"

      return 1
    fi

    log "Sudo access granted"
  fi
}

# is_controller_running checks if controller is already running (system-wide)
is_controller_running() {
  pgrep -f "k8s-hosts-controller" > /dev/null 2>&1
}

# get_controller_pid returns space-separated PIDs of running controller or empty string
get_controller_pid() {
  pgrep -f "k8s-hosts-controller" 2> /dev/null | tr '\n' ' ' || echo ""
}

# any_process_alive checks if ANY of the given space-separated PIDs is still alive
any_process_alive() {
  local pids="$1"
  for pid in $pids; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2> /dev/null; then
      return 0  # At least one process is alive
    fi
  done
  return 1  # All processes are dead
}

# start_controller starts the controller in background
start_controller() {
  local namespaces="$1"

  # Check if already running
  if is_controller_running; then
    local existing_pid
    existing_pid=$(get_controller_pid)
    log "Controller already running (PID: ${existing_pid})"
    log "Skipping startup, using existing instance"
    CONTROLLER_PID="$existing_pid"
    return 0
  fi

  # Build command as array to prevent word splitting
  local cmd=("$CONTROLLER_BINARY")
  if [[ -n "$namespaces" ]]; then
    cmd+=("--namespaces" "$namespaces")
  else
    cmd+=("--all-namespaces")
  fi

  log "Starting controller in background..."
  log "  Command: ${cmd[*]}"
  log "  Log file: $LOG_FILE"

  # Determine kubeconfig path to pass to sudo
  # When running with sudo, HOME changes, so we need to explicitly pass KUBECONFIG
  local kubeconfig_path="${KUBECONFIG:-${HOME}/.kube/config}"

  # Pass KUBECONFIG to sudo so the controller can access the kubeconfig
  sudo KUBECONFIG="$kubeconfig_path" nohup "${cmd[@]}" > "$LOG_FILE" 2>&1 &
  CONTROLLER_PID=$!

  sleep "$STARTUP_WAIT_TIME"

  if ! kill -0 "$CONTROLLER_PID" 2> /dev/null; then
    err "Controller failed to start (PID: $CONTROLLER_PID)"
    err "Check log file: $LOG_FILE"
    return 1
  fi

  log "Controller started successfully (PID: $CONTROLLER_PID)"
  return 0
}

# stop_controller gracefully stops the controller
stop_controller() {
  local pid="${1:-}"

  if [[ -z "$pid" ]]; then
    pid=$(get_controller_pid)
  fi

  pid=$(echo "$pid" | sed 's/[[:space:]]*$//')

  if [[ -z "$pid" ]]; then
    log "No controller running, nothing to stop"
    return 0
  fi

  log "Stopping controller (PID: $pid)..."

  if any_process_alive "$pid"; then
    if ! sudo kill $pid 2> /dev/null; then
      err "Failed to send SIGTERM to process(es): $pid"
      err "=== MANUAL CLEANUP REQUIRED ==="
      err "Run: sudo kill -9 $pid"
      err "================================"
      return 1
    fi

    local count=0
    log "Waiting $GRACEFUL_SHUTDOWN_TIMEOUT seconds until processes are gracefully shutdown"
    while any_process_alive "$pid" && [[ $count -lt "$GRACEFUL_SHUTDOWN_TIMEOUT" ]]; do
      sleep 1
      count=$((count + 1))
    done

    if any_process_alive "$pid"; then
      warning "Controller did not stop gracefully, forcing..."
      if ! sudo kill -9 $pid 2> /dev/null; then
        err "Failed to force kill process(es): $pid"
        err "=== MANUAL CLEANUP REQUIRED ==="
        err "Run: sudo kill -9 $pid"
        err "================================"
        return 1
      fi
    fi
  fi

  log "Controller stopped"
  return 0
}

# cleanup_hosts removes all controller-managed entries from /etc/hosts
cleanup_hosts() {
  log "Cleaning up /etc/hosts entries..."

  # Determine kubeconfig path to pass to sudo
  local kubeconfig_path="${KUBECONFIG:-${HOME}/.kube/config}"

  if ! sudo KUBECONFIG="$kubeconfig_path" "$CONTROLLER_BINARY" --cleanup; then
    err "Failed to cleanup /etc/hosts"
    return 1
  fi
  log "Hosts entries cleaned up"
}

# show_status displays current controller status
show_status() {
  if is_controller_running; then
    local pid
    pid=$(get_controller_pid)
    log "Controller status: RUNNING (PID: $pid)"
    log "Log file: $LOG_FILE"
  else
    log "Controller status: NOT RUNNING"
  fi
}

# cleanup trap handler
cleanup_handler() {
  log "Cleanup handler called"
  if [[ -n "${CONTROLLER_PID:-}" ]] && kill -0 "$CONTROLLER_PID" 2> /dev/null; then
    log "Stopping controller (PID: $CONTROLLER_PID)..."
    stop_controller "$CONTROLLER_PID"
  fi
}

# register_cleanup sets up exit traps
register_cleanup() {
  trap cleanup_handler EXIT INT TERM
}

main() {
  local action="${1:-start}"
  local namespaces="${2:-$NAMESPACES}"

  # Validate controller binary exists (checks both file paths and PATH)
  if [[ ! -f "$CONTROLLER_BINARY" ]] && ! command -v "$CONTROLLER_BINARY" &> /dev/null; then
    err "Controller binary not found: $CONTROLLER_BINARY"
    exit 1
  fi

  case "$action" in
    start)
      check_sudo
      start_controller "$namespaces"
      log "Controller is ready"
      ;;
    stop)
      check_sudo
      stop_controller || exit 1
      ;;
    restart)
      check_sudo
      log "Restarting controller..."
      stop_controller
      start_controller "$namespaces"
      log "Controller restarted successfully"
      ;;
    cleanup)
      check_sudo || exit 1
      cleanup_hosts
      ;;
    status)
      show_status
      ;;
    *)
      echo "Usage: $0 {start|stop|restart|cleanup|status} [namespaces]"
      echo ""
      echo "Examples:"
      echo "  $0 start tyk,tyk-dp-1,tyk-dp-2"
      echo "  $0 start"
      echo "  $0 stop"
      echo "  $0 restart"
      echo "  $0 cleanup"
      echo "  $0 status"
      exit 1
      ;;
  esac
}

main "$@"
