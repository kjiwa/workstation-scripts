#!/bin/sh
# Hermetic unit tests for macos/wifi-roam-log.sh using mock binaries and temp trees.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=../lib/harness.sh
. "$SCRIPT_DIR/../lib/harness.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly REPO_DIR
readonly SCRIPT="$REPO_DIR/macos/wifi-roam-log.sh"
readonly PLIST_NAME="local.workstation-scripts.wifi-roam-log.plist"

_create_mock_tool() {
  _create_mock_tool_dir="$1"
  _create_mock_tool_name="$2"
  cat <<'MOCK' >"$_create_mock_tool_dir/$_create_mock_tool_name"
#!/bin/sh
set -eu
printf '%s %s\n' "$(basename "$0")" "$*" >> "$TOOL_LOG"
if [ "$(basename "$0")" = "launchctl" ] && [ "${1:-}" = "bootout" ]; then
  exit "${MOCK_BOOTOUT_EXIT:-0}"
fi
if [ "$(basename "$0")" = "plutil" ]; then
  exit "${MOCK_PLUTIL_EXIT:-0}"
fi
exit 0
MOCK
  chmod +x "$_create_mock_tool_dir/$_create_mock_tool_name"
}

_exists() {
  if [ -e "$1" ] || [ -L "$1" ]; then echo yes; else echo no; fi
}

setup() {
  TEST_TMP="$(mktemp -d)"
  export TEST_TMP
  export TOOL_LOG="$TEST_TMP/tool.log"
  export UNAME_OS="Darwin"
  export MOCK_BOOTOUT_EXIT=0
  export MOCK_PLUTIL_EXIT=0
  export HOME="$TEST_TMP/home"
  mkdir -p "$HOME" "$TEST_TMP/bin"
  : > "$TOOL_LOG"

  create_mock_uname "$TEST_TMP/bin"
  for _setup_tool in log launchctl plutil; do
    _create_mock_tool "$TEST_TMP/bin" "$_setup_tool"
  done

  OLD_PATH="$PATH"
  export OLD_PATH
  export PATH="$TEST_TMP/bin:$PATH"
}

teardown() {
  export PATH="$OLD_PATH"
  rm -rf "$TEST_TMP"
}

test_help_and_invalid_option() {
  setup
  run_capture "$SCRIPT" --help
  assert_status "exits 0 on --help" 0 "$RUN_STATUS"
  assert_contains "shows usage" "$RUN_STDOUT" "Usage: wifi-roam-log.sh"
  assert_contains "documents dry-run" "$RUN_STDOUT" "--dry-run"
  assert_contains "documents install-agent" "$RUN_STDOUT" "--install-agent"
  run_capture "$SCRIPT" -x
  assert_status "exits 1 on invalid option" 1 "$RUN_STATUS"
  assert_contains "shows usage on invalid option" "$RUN_STDOUT" "Usage: wifi-roam-log.sh"
  teardown
}

test_non_darwin_os() {
  setup
  UNAME_OS="Linux"
  run_capture "$SCRIPT"
  assert_status "exits 1 on non-Darwin OS" 1 "$RUN_STATUS"
  assert_contains "reports macOS required" "$RUN_STDOUT" "macOS (Darwin) required"
  assert_eq "runs no tools" "" "$(cat "$TOOL_LOG")"
  teardown
}

test_streams_roam_rows() {
  setup
  run_capture "$SCRIPT"
  assert_status "exits 0" 0 "$RUN_STATUS"
  _test_log="$(cat "$TOOL_LOG")"
  assert_contains "streams in compact style" "$_test_log" "log stream --style compact --predicate"
  assert_contains "matches BSS transition rows" "$_test_log" "handleBssTransEvent@402"
  assert_contains "matches association failure rows" "$_test_log" "Link down because assoc fail"
  assert_contains "matches roam rows" "$_test_log" "handleRoam@977"
  teardown
}

test_dry_run_changes_nothing() {
  setup
  run_capture "$SCRIPT" --dry-run
  assert_status "exits 0" 0 "$RUN_STATUS"
  assert_contains "reports the command" "$RUN_STDOUT" "would run log stream --style compact --predicate"
  assert_contains "reports the predicate" "$RUN_STDOUT" "handleRoam@977"
  assert_eq "runs no tools" "" "$(cat "$TOOL_LOG")"
  teardown
}

test_install_agent_writes_plist_and_loads() {
  setup
  run_capture "$SCRIPT" --install-agent
  assert_status "exits 0" 0 "$RUN_STATUS"
  _test_plist="$HOME/Library/LaunchAgents/$PLIST_NAME"
  _test_content="$(cat "$_test_plist")"
  _test_script="$(cd "$REPO_DIR/macos" && pwd -P)/wifi-roam-log.sh"
  assert_contains "has label" "$_test_content" "<string>local.workstation-scripts.wifi-roam-log</string>"
  assert_contains "has absolute script path" "$_test_content" "<string>$_test_script</string>"
  assert_contains "runs at load" "$_test_content" "<key>RunAtLoad</key>
  <true/>"
  assert_contains "keeps alive" "$_test_content" "<key>KeepAlive</key>
  <true/>"
  assert_contains "logs stdout" "$_test_content" "<key>StandardOutPath</key>
  <string>$HOME/Library/Logs/wifi-roam.log</string>"
  assert_contains "logs stderr" "$_test_content" "<key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/wifi-roam.log</string>"
  assert_contains "sets system PATH" "$_test_content" "<string>/usr/bin:/bin:/usr/sbin:/sbin</string>"
  assert_eq "calls bootout then bootstrap" "launchctl bootout gui/$(id -u)/local.workstation-scripts.wifi-roam-log
launchctl bootstrap gui/$(id -u) $_test_plist" "$(grep '^launchctl' "$TOOL_LOG")"
  teardown
}

test_install_agent_is_idempotent() {
  setup
  MOCK_BOOTOUT_EXIT=1
  run_capture "$SCRIPT" --install-agent
  assert_status "first install exits 0" 0 "$RUN_STATUS"
  _test_first="$(cat "$HOME/Library/LaunchAgents/$PLIST_NAME")"
  run_capture "$SCRIPT" --install-agent
  assert_status "reinstall exits 0 when bootout fails" 0 "$RUN_STATUS"
  assert_eq "plist unchanged" "$_test_first" "$(cat "$HOME/Library/LaunchAgents/$PLIST_NAME")"
  assert_eq "bootstraps each time" 2 "$(grep -c '^launchctl bootstrap' "$TOOL_LOG")"
  teardown
}

test_install_agent_dry_run_changes_nothing() {
  setup
  run_capture "$SCRIPT" --install-agent --dry-run
  assert_status "exits 0" 0 "$RUN_STATUS"
  assert_contains "reports write" "$RUN_STDOUT" "would write $HOME/Library/LaunchAgents/$PLIST_NAME"
  assert_contains "reports bootout" "$RUN_STDOUT" "would run launchctl bootout"
  assert_contains "reports bootstrap" "$RUN_STDOUT" "would run launchctl bootstrap"
  assert_eq "writes no plist" no "$(_exists "$HOME/Library")"
  assert_eq "runs no tools" "" "$(cat "$TOOL_LOG")"
  teardown
}

test_install_agent_invalid_plist_fails() {
  setup
  MOCK_PLUTIL_EXIT=1
  run_capture "$SCRIPT" --install-agent
  assert_status "exits 1" 1 "$RUN_STATUS"
  assert_contains "reports invalid plist" "$RUN_STDOUT" "invalid plist"
  assert_not_contains "does not load" "$(cat "$TOOL_LOG")" "launchctl"
  teardown
}

test_install_agent_rejects_extra_option() {
  setup
  run_capture "$SCRIPT" --install-agent --bogus
  assert_status "exits 1" 1 "$RUN_STATUS"
  assert_contains "shows usage" "$RUN_STDOUT" "Usage: wifi-roam-log.sh"
  assert_eq "writes nothing" no "$(_exists "$HOME/Library")"
  teardown
}

main() {
  test_help_and_invalid_option
  test_non_darwin_os
  test_streams_roam_rows
  test_dry_run_changes_nothing
  test_install_agent_writes_plist_and_loads
  test_install_agent_is_idempotent
  test_install_agent_dry_run_changes_nothing
  test_install_agent_invalid_plist_fails
  test_install_agent_rejects_extra_option
  test_summary
}

main "$@"
