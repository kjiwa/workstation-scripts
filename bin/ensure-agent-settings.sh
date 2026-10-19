#!/bin/sh
set -eu

readonly DEFAULT_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/workstation-scripts"
readonly DEFAULT_CONFIG_FILE="$DEFAULT_CONFIG_DIR/ensure-agent-settings.conf"
readonly DEFAULT_AGENT_DIR="$HOME/src/github/kjiwa/agent-settings"
readonly LAUNCHD_LABEL="com.kjiwa.agent-settings"
readonly LAUNCHD_PLIST_DIR="$HOME/Library/LaunchAgents"
readonly LAUNCHD_PLIST="$LAUNCHD_PLIST_DIR/$LAUNCHD_LABEL.plist"
readonly SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
readonly SYSTEMD_PATH_UNIT="$SYSTEMD_USER_DIR/agent-settings.path"
readonly SYSTEMD_SERVICE_UNIT="$SYSTEMD_USER_DIR/agent-settings.service"

_usage() {
  _usage_prog="$1"
  cat <<EOF
Usage: $_usage_prog [options]

Monitor and ensure agent-settings symlinks and build artifacts remain intact.

Options:
  -c, --check            Check symlinks and build artifacts without modifying anything.
                         Exits 0 if intact, 1 if broken.
  -r, --repair           Inspect and repair missing build artifacts or broken symlinks.
  -m, --mode MODE        Set execution mode for this run: 'notify' or 'auto-restore'.
      --set-mode MODE    Persist default mode ('notify' or 'auto-restore') to config file.
  -n, --notify           Enable desktop notifications.
      --no-notify        Disable desktop notifications.
  -i, --install-service  Install and activate background event-driven service.
  -u, --uninstall-service Disable and remove background event-driven service.
  -s, --status           Report service status, active configuration, and health.
  -d, --dir DIR          Path to agent-settings repository (default: ~/src/github/kjiwa/agent-settings).
  -q, --quiet            Suppress non-essential output.
  -h, --help             Show this help message and exit.

Configuration:
  Settings are loaded from ${XDG_CONFIG_HOME:-~/.config}/workstation-scripts/ensure-agent-settings.conf.
  Supported keys:
    mode=notify|auto-restore
    notifications=true|false
    agent_settings_dir=<path>

Behavior:
  - In 'notify' mode (default), detecting broken links or missing build artifacts triggers
    a desktop notification with remediation instructions and exits 1.
  - In 'auto-restore' mode, detecting broken links automatically runs install.sh in the
    agent-settings repo to restore artifacts and symlinks, then notifies on completion.
  - Background services use OS-native file monitoring (macOS launchd WatchPaths, Linux
    systemd .path units) to detect changes immediately with zero idle polling or battery drain.

Examples:
  $_usage_prog --check
  $_usage_prog --repair
  $_usage_prog --set-mode auto-restore
  $_usage_prog --install-service
  $_usage_prog --status
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

_load_config() {
  _load_config_file="$1"
  [ -f "$_load_config_file" ] || return 0
  while IFS= read -r _load_line || [ -n "$_load_line" ]; do
    case "$_load_line" in
      "" | \#*) continue ;;
    esac
    _load_key="${_load_line%%=*}"
    _load_val="${_load_line#*=}"
    _load_key=$(printf '%s' "$_load_key" | tr -d ' \t')
    _load_val=$(printf '%s' "$_load_val" | tr -d ' \t\r')
    _load_val="${_load_val#\"}"
    _load_val="${_load_val%\"}"
    _load_val="${_load_val#\'}"
    _load_val="${_load_val%\'}"
    case "$_load_key" in
      mode) CONFIG_MODE="$_load_val" ;;
      notifications)
        case "$_load_val" in
          true | 1 | yes) CONFIG_NOTIFY=1 ;;
          false | 0 | no) CONFIG_NOTIFY=0 ;;
        esac
        ;;
      agent_settings_dir) CONFIG_AGENT_DIR="$_load_val" ;;
    esac
  done <"$_load_config_file"
}

_save_config_mode() {
  _save_config_file="$1"
  _save_mode="$2"
  case "$_save_mode" in
    notify | auto-restore) ;;
    *)
      printf 'error: invalid mode "%s" (must be "notify" or "auto-restore")\n' "$_save_mode" >&2
      return 1
      ;;
  esac
  _save_config_dir=$(dirname "$_save_config_file")
  mkdir -p "$_save_config_dir"
  if [ -f "$_save_config_file" ] && grep -q '^mode=' "$_save_config_file" 2>/dev/null; then
    _save_tmp="$_save_config_file.tmp.$$"
    sed "s/^mode=.*/mode=$_save_mode/" "$_save_config_file" >"$_save_tmp"
    mv -f "$_save_tmp" "$_save_config_file"
  else
    printf 'mode=%s\n' "$_save_mode" >>"$_save_config_file"
  fi
  printf 'Saved mode=%s to %s\n' "$_save_mode" "$_save_config_file"
}

_notify() {
  _notify_enabled="$1"
  _notify_title="$2"
  _notify_msg="$3"
  [ "$_notify_enabled" -eq 1 ] || return 0
  if [ "$(uname -s)" = "Darwin" ]; then
    _notify_esc_title=$(printf '%s' "$_notify_title" | sed 's/"/\\"/g')
    _notify_esc_msg=$(printf '%s' "$_notify_msg" | sed 's/"/\\"/g')
    osascript -e "display notification \"$_notify_esc_msg\" with title \"$_notify_esc_title\"" >/dev/null 2>&1 || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "$_notify_title" "$_notify_msg" >/dev/null 2>&1 || true
  fi
}

_resolve_link_full() {
  _rlf_path="$1"
  _rlf_path="${_rlf_path#\~/}"
  _rlf_path="${_rlf_path#/}"
  printf '%s/%s' "$HOME" "$_rlf_path"
}

_check_integrity() {
  _ci_agent_dir="$1"
  _ci_quiet="$2"
  _ci_status=0

  if [ ! -d "$_ci_agent_dir" ]; then
    [ "$_ci_quiet" -eq 1 ] || printf 'agent-settings: directory not found: %s\n' "$_ci_agent_dir" >&2
    return 1
  fi

  if [ ! -r "$_ci_agent_dir/links" ]; then
    [ "$_ci_quiet" -eq 1 ] || printf 'agent-settings: links file missing: %s/links\n' "$_ci_agent_dir" >&2
    return 1
  fi

  if [ ! -r "$_ci_agent_dir/harnesses" ]; then
    [ "$_ci_quiet" -eq 1 ] || printf 'agent-settings: harnesses file missing: %s/harnesses\n' "$_ci_agent_dir" >&2
    return 1
  fi

  # Check harnesses and build artifacts
  while IFS=' ' read -r _ci_overlay _ci_build || [ -n "$_ci_overlay" ]; do
    case "$_ci_overlay" in
      "" | \#*) continue ;;
    esac
    [ -n "$_ci_build" ] || continue
    _ci_build_path="$_ci_agent_dir/$_ci_build"
    if [ ! -f "$_ci_build_path" ]; then
      [ "$_ci_quiet" -eq 1 ] || printf 'missing build artifact: %s\n' "$_ci_build_path" >&2
      _ci_status=1
      continue
    fi
    if [ -x "$_ci_agent_dir/bin/build-rules.sh" ]; then
      if ! "$_ci_agent_dir/bin/build-rules.sh" "$_ci_overlay" | cmp -s - "$_ci_build_path"; then
        [ "$_ci_quiet" -eq 1 ] || printf 'stale build artifact: %s\n' "$_ci_build_path" >&2
        _ci_status=1
      fi
    fi
  done <"$_ci_agent_dir/harnesses"

  # Check symlinks
  while IFS=' ' read -r _ci_target _ci_path || [ -n "$_ci_target" ]; do
    case "$_ci_target" in
      "" | \#*) continue ;;
    esac
    [ -n "$_ci_path" ] || continue
    _ci_full="$(_resolve_link_full "$_ci_path")"
    _ci_want="$_ci_agent_dir/$_ci_target"

    if [ ! -L "$_ci_full" ]; then
      [ "$_ci_quiet" -eq 1 ] || printf 'not a symlink: %s\n' "$_ci_full" >&2
      _ci_status=1
      continue
    fi

    if [ ! -e "$_ci_full" ]; then
      [ "$_ci_quiet" -eq 1 ] || printf 'dangling symlink: %s -> %s\n' "$_ci_full" "$(readlink "$_ci_full" 2>/dev/null || echo unknown)" >&2
      _ci_status=1
      continue
    fi

    _ci_actual="$(readlink "$_ci_full")"
    if [ "$_ci_actual" != "$_ci_want" ]; then
      [ "$_ci_quiet" -eq 1 ] || printf 'incorrect symlink target: %s -> %s (expected %s)\n' "$_ci_full" "$_ci_actual" "$_ci_want" >&2
      _ci_status=1
      continue
    fi
  done <"$_ci_agent_dir/links"

  return "$_ci_status"
}

_repair() {
  _repair_agent_dir="$1"
  _repair_installer="$_repair_agent_dir/install.sh"
  if [ ! -x "$_repair_installer" ]; then
    printf 'repair error: installer not executable at %s\n' "$_repair_installer" >&2
    return 1
  fi
  printf 'Running %s...\n' "$_repair_installer"
  "$_repair_installer"
  _check_integrity "$_repair_agent_dir" 0
}

_generate_launchd_plist() {
  _glp_agent_dir="$1"
  _glp_script_path="$2"
  _glp_plist="$3"
  _glp_log_file="$HOME/Library/Logs/com.kjiwa.agent-settings.log"

  mkdir -p "$(dirname "$_glp_plist")" "$(dirname "$_glp_log_file")"

  cat <<EOF >"$_glp_plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCHD_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$_glp_script_path</string>
        <string>--quiet</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>$_glp_log_file</string>
    <key>StandardErrorPath</key>
    <string>$_glp_log_file</string>
    <key>WatchPaths</key>
    <array>
        <string>$_glp_agent_dir/build</string>
        <string>$_glp_agent_dir/links</string>
        <string>$_glp_agent_dir/harnesses</string>
        <string>$_glp_agent_dir/core</string>
        <string>$_glp_agent_dir/overlays</string>
EOF

  if [ -r "$_glp_agent_dir/links" ]; then
    while IFS=' ' read -r _glp_target _glp_path || [ -n "$_glp_target" ]; do
      case "$_glp_target" in
        "" | \#*) continue ;;
      esac
      [ -n "$_glp_path" ] || continue
      _glp_dest="$(_resolve_link_full "$_glp_path")"
      cat <<EOF >>"$_glp_plist"
        <string>$_glp_dest</string>
EOF
    done <"$_glp_agent_dir/links"
  fi

  cat <<EOF >>"$_glp_plist"
    </array>
</dict>
</plist>
EOF
}

_install_launchd_service() {
  _ils_agent_dir="$1"
  _ils_script="$2"
  _ils_plist="$3"
  _ils_uid="$(id -u)"

  _generate_launchd_plist "$_ils_agent_dir" "$_ils_script" "$_ils_plist"

  # Boot out any prior instance
  launchctl bootout "gui/$_ils_uid/$LAUNCHD_LABEL" 2>/dev/null || launchctl unload "$_ils_plist" 2>/dev/null || true

  if launchctl bootstrap "gui/$_ils_uid" "$_ils_plist" 2>/dev/null; then
    printf 'Installed and bootstrapped %s\n' "$_ils_plist"
  elif launchctl load -w "$_ils_plist" 2>/dev/null; then
    printf 'Installed and loaded %s\n' "$_ils_plist"
  else
    printf 'Installed plist to %s (manual launchctl bootstrap required)\n' "$_ils_plist"
  fi
}

_uninstall_launchd_service() {
  _uls_plist="$1"
  _uls_uid="$(id -u)"
  launchctl bootout "gui/$_uls_uid/$LAUNCHD_LABEL" 2>/dev/null || launchctl unload "$_uls_plist" 2>/dev/null || true
  rm -f "$_uls_plist"
  printf 'Removed %s\n' "$_uls_plist"
}

_install_systemd_service() {
  _iss_agent_dir="$1"
  _iss_script="$2"
  _iss_path_unit="$3"
  _iss_service_unit="$4"

  mkdir -p "$(dirname "$_iss_path_unit")"

  cat <<EOF >"$_iss_service_unit"
[Unit]
Description=Ensure agent-settings symlinks and build files

[Service]
Type=oneshot
ExecStart=$_iss_script --quiet
EOF

  cat <<EOF >"$_iss_path_unit"
[Unit]
Description=Watch agent-settings symlinks and build files

[Path]
PathModified=$_iss_agent_dir/build
PathModified=$_iss_agent_dir/links
PathModified=$_iss_agent_dir/harnesses
PathModified=$_iss_agent_dir/core
PathModified=$_iss_agent_dir/overlays
EOF

  if [ -r "$_iss_agent_dir/links" ]; then
    while IFS=' ' read -r _iss_target _iss_path || [ -n "$_iss_target" ]; do
      case "$_iss_target" in
        "" | \#*) continue ;;
      esac
      [ -n "$_iss_path" ] || continue
      _iss_dest="$(_resolve_link_full "$_iss_path")"
      printf 'PathModified=%s\n' "$_iss_dest" >>"$_iss_path_unit"
    done <"$_iss_agent_dir/links"
  fi

  cat <<EOF >>"$_iss_path_unit"
Unit=agent-settings.service

[Install]
WantedBy=paths.target
EOF

  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now agent-settings.path 2>/dev/null || true
    printf 'Installed and activated systemd path unit at %s\n' "$_iss_path_unit"
  else
    printf 'Installed systemd units to %s and %s\n' "$_iss_path_unit" "$_iss_service_unit"
  fi
}

_uninstall_systemd_service() {
  _uss_path_unit="$1"
  _uss_service_unit="$2"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable --now agent-settings.path 2>/dev/null || true
  fi
  rm -f "$_uss_path_unit" "$_uss_service_unit"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload 2>/dev/null || true
  fi
  printf 'Removed %s and %s\n' "$_uss_path_unit" "$_uss_service_unit"
}

_install_service() {
  _is_agent_dir="$1"
  _is_script="$2"
  if [ "$(uname -s)" = "Darwin" ]; then
    _install_launchd_service "$_is_agent_dir" "$_is_script" "$LAUNCHD_PLIST"
  else
    _install_systemd_service "$_is_agent_dir" "$_is_script" "$SYSTEMD_PATH_UNIT" "$SYSTEMD_SERVICE_UNIT"
  fi
}

_uninstall_service() {
  if [ "$(uname -s)" = "Darwin" ]; then
    _uninstall_launchd_service "$LAUNCHD_PLIST"
  else
    _uninstall_systemd_service "$SYSTEMD_PATH_UNIT" "$SYSTEMD_SERVICE_UNIT"
  fi
}

_show_status() {
  _ss_agent_dir="$1"
  _ss_mode="$2"
  _ss_notify="$3"
  _ss_config_file="$4"

  printf 'Configuration:\n'
  printf '  Config file:        %s (%s)\n' "$_ss_config_file" "$([ -f "$_ss_config_file" ] && echo "present" || echo "not present")"
  printf '  Mode:               %s\n' "$_ss_mode"
  printf '  Notifications:      %s\n' "$([ "$_ss_notify" -eq 1 ] && echo "enabled" || echo "disabled")"
  printf '  agent-settings dir: %s\n\n' "$_ss_agent_dir"

  printf 'Background Service:\n'
  if [ "$(uname -s)" = "Darwin" ]; then
    printf '  Type:               macOS launchd\n'
    printf '  Plist:              %s (%s)\n' "$LAUNCHD_PLIST" "$([ -f "$LAUNCHD_PLIST" ] && echo "installed" || echo "not installed")"
    _ss_loaded="no"
    if launchctl print "gui/$(id -u)/$LAUNCHD_LABEL" >/dev/null 2>&1; then
      _ss_loaded="yes"
    elif launchctl list "$LAUNCHD_LABEL" >/dev/null 2>&1; then
      _ss_loaded="yes"
    fi
    printf '  Service loaded:     %s\n\n' "$_ss_loaded"
  else
    printf '  Type:               Linux systemd (user)\n'
    printf '  Path unit:          %s (%s)\n' "$SYSTEMD_PATH_UNIT" "$([ -f "$SYSTEMD_PATH_UNIT" ] && echo "installed" || echo "not installed")"
    _ss_loaded="no"
    if command -v systemctl >/dev/null 2>&1 && systemctl --user is-active agent-settings.path >/dev/null 2>&1; then
      _ss_loaded="yes"
    fi
    printf '  Service active:     %s\n\n' "$_ss_loaded"
  fi

  printf 'Integrity Status:\n'
  if _check_integrity "$_ss_agent_dir" 0; then
    printf '  All agent-settings symlinks and build artifacts are intact.\n'
    return 0
  else
    printf '\n  Issues detected. Run with --repair to restore.\n'
    return 1
  fi
}

main() {
  CONFIG_MODE="notify"
  CONFIG_NOTIFY=1
  CONFIG_AGENT_DIR="$DEFAULT_AGENT_DIR"
  _load_config "$DEFAULT_CONFIG_FILE"

  _main_prog="$0"
  _main_action=""
  _main_mode="$CONFIG_MODE"
  _main_notify="$CONFIG_NOTIFY"
  _main_agent_dir="$CONFIG_AGENT_DIR"
  _main_quiet=0
  _main_set_mode=""

  _main_script_path=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")

  while [ $# -gt 0 ]; do
    case "$1" in
      -h | --help) _exit_usage "$_main_prog" 0 ;;
      -c | --check) _main_action="check" ;;
      -r | --repair | --auto-restore) _main_action="repair" ;;
      -m | --mode)
        shift
        [ $# -gt 0 ] || _exit_usage "$_main_prog" 1
        _main_mode="$1"
        ;;
      --set-mode)
        shift
        [ $# -gt 0 ] || _exit_usage "$_main_prog" 1
        _main_set_mode="$1"
        _main_action="set-mode"
        ;;
      -n | --notify) _main_notify=1 ;;
      --no-notify) _main_notify=0 ;;
      -i | --install-service) _main_action="install-service" ;;
      -u | --uninstall-service) _main_action="uninstall-service" ;;
      -s | --status) _main_action="status" ;;
      -d | --dir)
        shift
        [ $# -gt 0 ] || _exit_usage "$_main_prog" 1
        _main_agent_dir="$1"
        ;;
      -q | --quiet) _main_quiet=1 ;;
      --)
        shift
        break
        ;;
      -*)
        printf 'error: unrecognized option: %s\n' "$1" >&2
        _exit_usage "$_main_prog" 1
        ;;
      *)
        printf 'error: unexpected argument: %s\n' "$1" >&2
        _exit_usage "$_main_prog" 1
        ;;
    esac
    shift
  done

  case "$_main_action" in
    set-mode)
      _save_config_mode "$DEFAULT_CONFIG_FILE" "$_main_set_mode"
      exit 0
      ;;
    install-service)
      _install_service "$_main_agent_dir" "$_main_script_path"
      exit 0
      ;;
    uninstall-service)
      _uninstall_service
      exit 0
      ;;
    status)
      _show_status "$_main_agent_dir" "$_main_mode" "$_main_notify" "$DEFAULT_CONFIG_FILE"
      exit $?
      ;;
    check)
      if _check_integrity "$_main_agent_dir" "$_main_quiet"; then
        [ "$_main_quiet" -eq 1 ] || printf 'agent-settings: all symlinks and build artifacts intact\n'
        exit 0
      else
        _notify "$_main_notify" "agent-settings" "Broken symlinks or build artifacts detected. Run ensure-agent-settings.sh --repair"
        exit 1
      fi
      ;;
    repair)
      if _repair "$_main_agent_dir"; then
        _notify "$_main_notify" "agent-settings" "Symlinks and build artifacts successfully restored."
        [ "$_main_quiet" -eq 1 ] || printf 'agent-settings: repair succeeded\n'
        exit 0
      else
        _notify "$_main_notify" "agent-settings" "Repair failed. Check logs."
        printf 'agent-settings: repair failed\n' >&2
        exit 1
      fi
      ;;
    "")
      # Default behavior when run without explicit action (e.g. by launchd or background job)
      if _check_integrity "$_main_agent_dir" "$_main_quiet"; then
        [ "$_main_quiet" -eq 1 ] || printf 'agent-settings: all symlinks and build artifacts intact\n'
        exit 0
      fi

      # Broken state detected
      if [ "$_main_mode" = "auto-restore" ]; then
        [ "$_main_quiet" -eq 1 ] || printf 'agent-settings: broken items detected; auto-restore active...\n'
        if _repair "$_main_agent_dir"; then
          _notify "$_main_notify" "agent-settings" "Symlinks and build artifacts automatically restored."
          [ "$_main_quiet" -eq 1 ] || printf 'agent-settings: auto-restore succeeded\n'
          exit 0
        else
          _notify "$_main_notify" "agent-settings" "Auto-restore failed. Run manual repair."
          printf 'agent-settings: auto-restore failed\n' >&2
          exit 1
        fi
      else
        _notify "$_main_notify" "agent-settings" "Broken symlinks or build artifacts detected. Run ensure-agent-settings.sh --repair"
        [ "$_main_quiet" -eq 1 ] || printf 'agent-settings: broken items detected (mode=notify)\n' >&2
        exit 1
      fi
      ;;
  esac
}

main "$@"
