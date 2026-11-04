#!/bin/sh
set -eu

readonly CLAUDE_TMP_MAX_AGE_DAYS=7
readonly CLAUDE_TMP_INTERNAL_ENTRIES="bash-edit-diff plugin-tool-staging"
readonly TF_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
readonly SRC_DIRS="${PRUNE_SRC_DIRS:-$HOME/src}"
readonly AGENT_LABEL="com.github.kjiwa.prune-caches"
readonly AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
readonly AGENT_LOG="$HOME/Library/Logs/prune-caches.log"
readonly AGENT_PATH_ENV="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
readonly CLAUDE_TMP_DIR="${PRUNE_CLAUDE_TMP_DIR:-/private/tmp/claude-$(id -u)}"

_prog=""
_dry_run=0
_install_agent=0
_failed=0
_step_kb=0
_step_count=0

_usage() {
  _usage_prog="$1"
  cat <<EOF
Usage: $_usage_prog [-h|--help] [-n|--dry-run] [--install-agent]

Prune regenerable caches while keeping data that is still in use.

Options:
  -h, --help     Show this help message and exit.
  -n, --dry-run  Print each action as 'would remove <path>' or
                 'would run <command>' and change nothing.
      --install-agent
                 Install and load a LaunchAgent that runs this script
                 weekly (Sundays 10:00), replacing a loaded one. Logs to
                 ~/Library/Logs/prune-caches.log. With --dry-run, print
                 what would be written and run.

Behavior:
  - Runs 'brew cleanup', 'uv cache prune', 'npm cache verify', and
    'docker image prune -f' plus 'docker builder prune -f'. Stopped
    containers and volumes are left alone.
  - Removes Terraform plugin cache versions that no .terraform.lock.hcl
    under the source directories pins, and every symlink in the cache.
    Cache: \$TF_PLUGIN_CACHE_DIR (default ~/.terraform.d/plugin-cache).
    Source directories: colon-separated \$PRUNE_SRC_DIRS (default ~/src).
    Skipped if a source directory is missing.
  - Removes Claude session directories and loose files under
    \$PRUNE_CLAUDE_TMP_DIR (default /private/tmp/claude-<uid>) that
    contain nothing modified in the last $CLAUDE_TMP_MAX_AGE_DAYS days.
  - Reports a missing tool on stderr and skips it.
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

_have_tool() {
  _have_tool_name="$1"
  if command -v "$_have_tool_name" >/dev/null 2>&1; then
    return 0
  fi
  _warn "skipping $_have_tool_name: not found"
  return 1
}

_run_tool() {
  if [ "$_dry_run" -eq 1 ]; then
    printf 'would run %s\n' "$*"
    return 0
  fi
  printf 'running %s\n' "$*"
  if ! "$@"; then
    _warn "command failed: $*"
    _failed=1
  fi
}

_remove_path() {
  _remove_path_target="$1"
  _remove_path_kb="$(du -sk "$_remove_path_target" 2>/dev/null | awk '{print $1}')"
  _step_kb=$((_step_kb + ${_remove_path_kb:-0}))
  _step_count=$((_step_count + 1))
  if [ "$_dry_run" -eq 1 ]; then
    printf 'would remove %s\n' "$_remove_path_target"
    return 0
  fi
  printf 'removing %s\n' "$_remove_path_target"
  if ! rm -rf -- "$_remove_path_target"; then
    _warn "failed to remove $_remove_path_target"
    _failed=1
  fi
}

_remove_empty_parents() {
  _remove_empty_parents_path="$1"
  _remove_empty_parents_root="$2"
  [ "$_dry_run" -eq 0 ] || return 0
  _remove_empty_parents_dir="$(dirname "$_remove_empty_parents_path")"
  while [ "$_remove_empty_parents_dir" != "$_remove_empty_parents_root" ]; do
    rmdir "$_remove_empty_parents_dir" 2>/dev/null || break
    _remove_empty_parents_dir="$(dirname "$_remove_empty_parents_dir")"
  done
}

_report_step() {
  _report_step_label="$1"
  printf '%s: %d path(s), %d MiB\n' "$_report_step_label" "$_step_count" "$((_step_kb / 1024))"
  _step_kb=0
  _step_count=0
}

_prune_brew() {
  _have_tool brew || return 0
  _run_tool brew cleanup
}

_prune_uv() {
  _have_tool uv || return 0
  _run_tool uv cache prune
}

_prune_npm() {
  _have_tool npm || return 0
  _run_tool npm cache verify
}

_prune_docker() {
  _have_tool docker || return 0
  if ! docker info >/dev/null 2>&1; then
    _warn "skipping docker: daemon unreachable"
    return 0
  fi
  _run_tool docker image prune -f
  _run_tool docker builder prune -f
}

_collect_terraform_pins() {
  (
    IFS=:
    set -f
    for _collect_terraform_pins_dir in $SRC_DIRS; do
      if [ ! -d "$_collect_terraform_pins_dir" ]; then
        _warn "source directory not found: $_collect_terraform_pins_dir"
        exit 1
      fi
      find "$_collect_terraform_pins_dir" -name .terraform.lock.hcl -type f -exec awk '
        FNR == 1 { source = "" }
        $1 == "provider" { source = $2; gsub(/"/, "", source) }
        $1 == "version" && source != "" {
          version = $3; gsub(/"/, "", version)
          print source "/" version
          source = ""
        }
      ' {} +
    done
  )
}

_prune_terraform_symlinks() {
  _prune_terraform_symlinks_link=""
  while IFS= read -r _prune_terraform_symlinks_link; do
    [ -n "$_prune_terraform_symlinks_link" ] || continue
    _remove_path "$_prune_terraform_symlinks_link"
    _remove_empty_parents "$_prune_terraform_symlinks_link" "$TF_CACHE_DIR"
  done <<EOF
$(find "$TF_CACHE_DIR" -type l)
EOF
}

_prune_terraform_versions() {
  _prune_terraform_versions_pins="$1"
  for _prune_terraform_versions_dir in "$TF_CACHE_DIR"/*/*/*/*; do
    [ -d "$_prune_terraform_versions_dir" ] || continue
    [ ! -L "$_prune_terraform_versions_dir" ] || continue
    _prune_terraform_versions_key="${_prune_terraform_versions_dir#"$TF_CACHE_DIR"/}"
    if printf '%s\n' "$_prune_terraform_versions_pins" | grep -Fxq -- "$_prune_terraform_versions_key"; then
      continue
    fi
    _remove_path "$_prune_terraform_versions_dir"
    _remove_empty_parents "$_prune_terraform_versions_dir" "$TF_CACHE_DIR"
  done
}

_prune_terraform() {
  if [ ! -d "$TF_CACHE_DIR" ]; then
    _warn "skipping terraform: $TF_CACHE_DIR not found"
    return 0
  fi
  if ! _prune_terraform_pins="$(_collect_terraform_pins)"; then
    _warn "skipping terraform: cannot determine pinned versions"
    return 0
  fi
  _prune_terraform_symlinks
  _prune_terraform_versions "$_prune_terraform_pins"
  _report_step "terraform"
}

_is_stale() {
  _is_stale_path="$1"
  [ -z "$(find "$_is_stale_path" -mtime "-$CLAUDE_TMP_MAX_AGE_DAYS" -print | head -n 1)" ]
}

_prune_if_stale() {
  _prune_if_stale_path="$1"
  if _is_stale "$_prune_if_stale_path"; then
    _remove_path "$_prune_if_stale_path"
  fi
}

_is_claude_internal() {
  _is_claude_internal_name="$1"
  for _is_claude_internal_entry in $CLAUDE_TMP_INTERNAL_ENTRIES; do
    [ "$_is_claude_internal_name" != "$_is_claude_internal_entry" ] || return 0
  done
  return 1
}

_is_project_dir() {
  _is_project_dir_path="$1"
  [ -d "$_is_project_dir_path" ] && [ ! -L "$_is_project_dir_path" ] || return 1
  case "$(basename "$_is_project_dir_path")" in
    -*) return 0 ;;
    *) return 1 ;;
  esac
}

_prune_claude_project() {
  _prune_claude_project_dir="$1"
  for _prune_claude_project_session in "$_prune_claude_project_dir"/* "$_prune_claude_project_dir"/.[!.]*; do
    [ -e "$_prune_claude_project_session" ] || [ -L "$_prune_claude_project_session" ] || continue
    _prune_if_stale "$_prune_claude_project_session"
  done
  [ "$_dry_run" -eq 1 ] || rmdir "$_prune_claude_project_dir" 2>/dev/null || true
}

_prune_claude_tmp() {
  if [ ! -d "$CLAUDE_TMP_DIR" ]; then
    _warn "skipping claude tmp: $CLAUDE_TMP_DIR not found"
    return 0
  fi
  for _prune_claude_tmp_entry in "$CLAUDE_TMP_DIR"/* "$CLAUDE_TMP_DIR"/.[!.]*; do
    [ -e "$_prune_claude_tmp_entry" ] || [ -L "$_prune_claude_tmp_entry" ] || continue
    if _is_claude_internal "$(basename "$_prune_claude_tmp_entry")"; then
      continue
    fi
    if _is_project_dir "$_prune_claude_tmp_entry"; then
      _prune_claude_project "$_prune_claude_tmp_entry"
    else
      _prune_if_stale "$_prune_claude_tmp_entry"
    fi
  done
  _report_step "claude tmp"
}

_xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

_script_path() {
  _script_path_dir="$(cd "$(dirname "$0")" && pwd -P)"
  printf '%s/%s' "$_script_path_dir" "$(basename "$0")"
}

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
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key>
    <integer>0</integer>
    <key>Hour</key>
    <integer>10</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
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
    _warn "error: launchctl bootstrap failed"
    return 1
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

  _prune_brew
  _prune_uv
  _prune_npm
  _prune_docker
  _prune_terraform
  _prune_claude_tmp

  exit "$_failed"
}

main "$@"
