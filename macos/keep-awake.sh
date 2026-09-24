#!/bin/sh
set -eu

_cleanup_done=0
_cleanup_status=0
_caffeinate_pid=""
_keepalive_pid=""
_sleep_modified=0

_usage() {
  _usage_prog="$1"
  cat <<EOF
Usage: $_usage_prog [-h|--help] [--] [command [args...]]

Prevent macOS from sleeping when idle or when the laptop lid is closed.

Arguments:
  command [args...]  Optional command to run. If provided, the command is
                     executed with caffeinate while sleep is disabled. When
                     the command exits, original sleep settings are restored
                     and the command's exit code is returned.
                     If omitted, the system stays awake interactively until
                     interrupted with Ctrl-C.

Options:
  -h, --help         Show this help message and exit.
  --                 Treat all following arguments as a command, even if
                     they begin with a dash.

Behavior:
  - Disables sleep via 'pmset -a disablesleep 1' and runs 'caffeinate'.
  - Runs a background sudo keep-alive to maintain credentials during
    long-running tasks.
  - Restores the previous sleep state on exit or signal (INT, TERM, HUP).
  - Requires macOS and sudo access for pmset.
EOF
}

_exit_usage() {
  _exit_usage_prog="$1"
  _exit_usage_code="$2"
  if [ "$_exit_usage_code" -eq 0 ]; then
    _usage "$_exit_usage_prog"
  else
    _usage "$_exit_usage_prog" >&2
  fi
  exit "$_exit_usage_code"
}

_check_platform() {
  _check_platform_prog="$1"
  if [ "$(uname -s)" != "Darwin" ]; then
    printf '%s: error: macOS (Darwin) required\n' "$_check_platform_prog" >&2
    exit 1
  fi
}

_check_sudo() {
  _check_sudo_prog="$1"
  if ! sudo -v; then
    printf '%s: error: sudo authentication failed\n' "$_check_sudo_prog" >&2
    exit 1
  fi
}

_get_sleep_disabled() {
  _get_sleep_disabled_state="$(pmset -g | awk '/^[[:space:]]*SleepDisabled/ {print $2}')"
  case "$_get_sleep_disabled_state" in
    1) echo 1 ;;
    *) echo 0 ;;
  esac
}

_start_keepalive() {
  (
    while kill -0 "$$" 2>/dev/null; do
      sudo -n -v >/dev/null 2>&1 || true
      sleep 60
    done
  ) >/dev/null 2>&1 &
  _keepalive_pid=$!
}

_stop_keepalive() {
  if [ -n "$_keepalive_pid" ]; then
    kill "$_keepalive_pid" 2>/dev/null || true
    wait "$_keepalive_pid" 2>/dev/null || true
    _keepalive_pid=""
  fi
}

_cleanup() {
  _cleanup_exit_code=$?
  if [ "$_cleanup_done" -ne 0 ]; then
    return 0
  fi
  _cleanup_done=1

  trap - EXIT INT TERM HUP

  _stop_keepalive

  if [ -n "$_caffeinate_pid" ]; then
    kill "$_caffeinate_pid" 2>/dev/null || true
    wait "$_caffeinate_pid" 2>/dev/null || true
    _caffeinate_pid=""
  fi

  if [ "$_sleep_modified" -eq 1 ]; then
    _sleep_modified=0
    printf 'Restoring sleep settings...\n' >&2
    sudo pmset -a disablesleep 0 >/dev/null 2>&1 || true
  fi

  if [ "$_cleanup_status" -eq 0 ] && [ "$_cleanup_exit_code" -ne 0 ]; then
    _cleanup_status="$_cleanup_exit_code"
  fi

  exit "$_cleanup_status"
}

_handle_signal() {
  _handle_signal_code="$2"
  trap - EXIT INT TERM HUP
  _cleanup_status="$_handle_signal_code"
  _cleanup
}

main() {
  _main_prog="$(basename "$0")"

  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        _exit_usage "$_main_prog" 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        _exit_usage "$_main_prog" 1
        ;;
      *)
        break
        ;;
    esac
  done

  _check_platform "$_main_prog"
  _check_sudo "$_main_prog"

  trap '_cleanup' EXIT
  trap '_handle_signal INT 130' INT
  trap '_handle_signal TERM 143' TERM
  trap '_handle_signal HUP 129' HUP

  _main_initial_sleep_disabled="$(_get_sleep_disabled)"
  if [ "$_main_initial_sleep_disabled" -eq 0 ]; then
    if ! sudo pmset -a disablesleep 1; then
      printf '%s: error: failed to disable sleep\n' "$_main_prog" >&2
      exit 1
    fi
    _sleep_modified=1
  fi

  _start_keepalive

  if [ $# -gt 0 ]; then
    set +e
    caffeinate "$@"
    _main_status=$?
    set -e
    exit "$_main_status"
  else
    printf 'Sleep disabled. Keeping system awake. Press Ctrl-C to restore sleep...\n' >&2
    caffeinate &
    _caffeinate_pid=$!
    wait "$_caffeinate_pid" || true
  fi
}

main "$@"
