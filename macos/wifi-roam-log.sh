#!/bin/sh
set -eu

readonly AGENT_LABEL="local.workstation-scripts.wifi-roam-log"
readonly AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
readonly AGENT_LOG="$HOME/Library/Logs/wifi-roam.log"
readonly AGENT_PATH_ENV="/usr/bin:/bin:/usr/sbin:/sbin"
readonly PREDICATE='process == "kernel" AND (eventMessage CONTAINS "handleBssTransEvent@402" OR eventMessage CONTAINS "Link down because assoc fail" OR eventMessage CONTAINS "handleRoam@977")'

_prog=""
_dry_run=0
_install_agent=0

_usage() {
  _usage_prog="$1"
  cat <<EOF
Usage: $_usage_prog [-h|--help] [-n|--dry-run] [--install-agent]

Stream the kernel Wi-Fi roam rows to stdout. The unified log keeps them for
about a day; a LaunchAgent running this script keeps them in a file.

Options:
  -h, --help     Show this help message and exit.
  -n, --dry-run  Print 'would run <command>' and change nothing.
      --install-agent
                 Install and load a LaunchAgent that runs this script at
                 login and restarts it if it exits, replacing a loaded one.
                 Appends to ~/Library/Logs/wifi-roam.log. With --dry-run,
                 print what would be written and run.

Behavior:
  - Runs 'log stream --style compact' with a predicate that matches kernel
    BSS transition, association failure and roam rows.
  - Requires macOS.
EOF
}

_exit_usage() {
  _exit_usage_code="$1"
  if [ "$_exit_usage_code" -eq 0 ]; then
    _usage "$_prog"
  else
    _usage "$_prog" >&2
  fi
  exit "$_exit_usage_code"
}

_check_platform() {
  if [ "$(uname -s)" != "Darwin" ]; then
    printf '%s: error: macOS (Darwin) required\n' "$_prog" >&2
    exit 1
  fi
}

_warn() {
  printf '%s: %s\n' "$_prog" "$1" >&2
}

# shellcheck source=lib/launch-agent.sh
. "$(cd "$(dirname "$0")" && pwd -P)/lib/launch-agent.sh"

_agent_plist_content() {
  _agent_plist_content_script="$(_xml_escape "$1")"
  _agent_plist_content_log="$(_xml_escape "$AGENT_LOG")"
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$AGENT_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$_agent_plist_content_script</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$_agent_plist_content_log</string>
  <key>StandardErrorPath</key>
  <string>$_agent_plist_content_log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$AGENT_PATH_ENV</string>
  </dict>
</dict>
</plist>
EOF
}

_stream_roam_rows() {
  if [ "$_dry_run" -eq 1 ]; then
    printf 'would run log stream --style compact --predicate %s\n' "$PREDICATE"
    return 0
  fi
  exec log stream --style compact --predicate "$PREDICATE"
}

main() {
  _prog="$(basename "$0")"

  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        _exit_usage 0
        ;;
      -n|--dry-run)
        _dry_run=1
        shift
        ;;
      --install-agent)
        _install_agent=1
        shift
        ;;
      *)
        _exit_usage 1
        ;;
    esac
  done

  _check_platform

  if [ "$_install_agent" -eq 1 ]; then
    _install_agent_main || exit 1
    exit 0
  fi

  _stream_roam_rows
}

main "$@"
