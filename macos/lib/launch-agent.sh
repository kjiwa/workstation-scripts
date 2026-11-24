# Sourced by macos scripts that install a LaunchAgent. The caller defines
# AGENT_LABEL, AGENT_PLIST, AGENT_LOG, _dry_run, _warn and
# _agent_plist_content <script-path>, and runs _install_agent_main.
# shellcheck disable=SC2154

_xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

_script_path() {
  _script_path_dir="$(cd "$(dirname "$0")" && pwd -P)"
  printf '%s/%s' "$_script_path_dir" "$(basename "$0")"
}

_write_agent_plist() {
  mkdir -p "$(dirname "$AGENT_PLIST")" "$(dirname "$AGENT_LOG")"
  _agent_plist_content "$1" >"$AGENT_PLIST"
  printf 'wrote %s\n' "$AGENT_PLIST"
}

_lint_agent_plist() {
  if ! command -v plutil >/dev/null 2>&1; then
    _warn "skipping plist validation: plutil not found"
    return 0
  fi
  if ! plutil -lint "$AGENT_PLIST" >/dev/null; then
    _warn "error: invalid plist: $AGENT_PLIST"
    return 1
  fi
}

_load_agent() {
  _load_agent_domain="gui/$(id -u)"
  launchctl bootout "$_load_agent_domain/$AGENT_LABEL" >/dev/null 2>&1 || true
  if ! launchctl bootstrap "$_load_agent_domain" "$AGENT_PLIST"; then
    sleep 2
    if ! launchctl bootstrap "$_load_agent_domain" "$AGENT_PLIST"; then
      _warn "error: launchctl bootstrap failed"
      return 1
    fi
  fi
  printf 'loaded %s\n' "$AGENT_LABEL"
}

_dry_run_install_agent() {
  printf 'would write %s\n' "$AGENT_PLIST"
  _agent_plist_content "$1"
  printf 'would run plutil -lint %s\n' "$AGENT_PLIST"
  printf 'would run launchctl bootout gui/%s/%s\n' "$(id -u)" "$AGENT_LABEL"
  printf 'would run launchctl bootstrap gui/%s %s\n' "$(id -u)" "$AGENT_PLIST"
}

_install_agent_main() {
  _install_agent_main_script="$(_script_path)"
  if [ "$_dry_run" -eq 1 ]; then
    _dry_run_install_agent "$_install_agent_main_script"
    return 0
  fi
  _write_agent_plist "$_install_agent_main_script"
  _lint_agent_plist || return 1
  _load_agent
}
