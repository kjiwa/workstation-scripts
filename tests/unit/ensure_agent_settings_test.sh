#!/bin/sh
# Hermetic unit tests for bin/ensure-agent-settings.sh.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=../lib/harness.sh
. "$SCRIPT_DIR/../lib/harness.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly REPO_DIR

_create_mock_binaries() {
  _cmb_dir="$1"
  mkdir -p "$_cmb_dir"

  cat <<'EOF' >"$_cmb_dir/uname"
#!/bin/sh
set -eu
if [ "${1:-}" = "-s" ]; then
  echo "${UNAME_OS:-Darwin}"
  exit 0
fi
exec /usr/bin/uname "$@"
EOF
  chmod +x "$_cmb_dir/uname"

  cat <<'EOF' >"$_cmb_dir/osascript"
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$NOTIFY_LOG"
exit "${MOCK_OSASCRIPT_EXIT:-0}"
EOF
  chmod +x "$_cmb_dir/osascript"

  cat <<'EOF' >"$_cmb_dir/notify-send"
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$NOTIFY_LOG"
exit "${MOCK_NOTIFY_SEND_EXIT:-0}"
EOF
  chmod +x "$_cmb_dir/notify-send"

  cat <<'EOF' >"$_cmb_dir/launchctl"
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$LAUNCHCTL_LOG"
case "${1:-}" in
  print | list)
    exit "${MOCK_LAUNCHCTL_QUERY_EXIT:-0}"
    ;;
  bootstrap | load)
    exit "${MOCK_LAUNCHCTL_LOAD_EXIT:-0}"
    ;;
  bootout | unload)
    exit "${MOCK_LAUNCHCTL_UNLOAD_EXIT:-0}"
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "$_cmb_dir/launchctl"

  cat <<'EOF' >"$_cmb_dir/systemctl"
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$SYSTEMCTL_LOG"
case "${1:-}" in
  --user)
    case "${2:-}" in
      is-active | status)
        exit "${MOCK_SYSTEMCTL_QUERY_EXIT:-0}"
        ;;
      enable | disable | daemon-reload)
        exit 0
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "$_cmb_dir/systemctl"
}

_create_agent_settings_fixture() {
  _casf_dir="$1"
  mkdir -p "$_casf_dir/core" "$_casf_dir/overlays" "$_casf_dir/bin" "$_casf_dir/dot-claude" "$_casf_dir/build"

  printf '# Core rules\n' >"$_casf_dir/core/working-agreement.md"
  printf '# Overlay\n' >"$_casf_dir/overlays/claude-code.md"
  printf '{"model": "test"}\n' >"$_casf_dir/dot-claude/settings.json"

  cat <<'EOF' >"$_casf_dir/bin/build-rules.sh"
#!/bin/sh
set -eu
_b_dir=$(cd "$(dirname "$0")/.." && pwd)
cat "$_b_dir/core/working-agreement.md"
echo
cat "$_b_dir/overlays/$1"
EOF
  chmod +x "$_casf_dir/bin/build-rules.sh"

  cat <<EOF >"$_casf_dir/harnesses"
claude-code.md build/CLAUDE.md
EOF

  cat <<EOF >"$_casf_dir/links"
build/CLAUDE.md .claude/CLAUDE.md
dot-claude/settings.json .claude/settings.json
EOF

  cat <<'EOF' >"$_casf_dir/install.sh"
#!/bin/sh
set -eu
_inst_dir=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$_inst_dir/build"
"$_inst_dir/bin/build-rules.sh" claude-code.md >"$_inst_dir/build/CLAUDE.md"
mkdir -p "$HOME/.claude"
ln -sfn "$_inst_dir/build/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
ln -sfn "$_inst_dir/dot-claude/settings.json" "$HOME/.claude/settings.json"
EOF
  chmod +x "$_casf_dir/install.sh"

  # Initial install run to establish valid state
  "$_casf_dir/install.sh"
}

setup() {
  TEST_TMP="$(mktemp -d)"
  export TEST_TMP

  ORIG_HOME="$HOME"
  export ORIG_HOME
  HOME="$TEST_TMP/home"
  export HOME
  mkdir -p "$HOME"

  XDG_CONFIG_HOME="$HOME/.config"
  export XDG_CONFIG_HOME

  BIN_MOCK="$TEST_TMP/bin_mock"
  export BIN_MOCK
  _create_mock_binaries "$BIN_MOCK"

  NOTIFY_LOG="$TEST_TMP/notify.log"
  export NOTIFY_LOG
  touch "$NOTIFY_LOG"

  LAUNCHCTL_LOG="$TEST_TMP/launchctl.log"
  export LAUNCHCTL_LOG
  touch "$LAUNCHCTL_LOG"

  SYSTEMCTL_LOG="$TEST_TMP/systemctl.log"
  export SYSTEMCTL_LOG
  touch "$SYSTEMCTL_LOG"

  MOCK_LAUNCHCTL_QUERY_EXIT=0
  export MOCK_LAUNCHCTL_QUERY_EXIT
  MOCK_LAUNCHCTL_LOAD_EXIT=0
  export MOCK_LAUNCHCTL_LOAD_EXIT
  MOCK_LAUNCHCTL_UNLOAD_EXIT=0
  export MOCK_LAUNCHCTL_UNLOAD_EXIT
  MOCK_SYSTEMCTL_QUERY_EXIT=0
  export MOCK_SYSTEMCTL_QUERY_EXIT

  OLD_PATH="$PATH"
  export OLD_PATH
  PATH="$BIN_MOCK:$PATH"
  export PATH

  AGENT_DIR="$TEST_TMP/agent-settings"
  export AGENT_DIR
  _create_agent_settings_fixture "$AGENT_DIR"
}

teardown() {
  export PATH="$OLD_PATH"
  export HOME="$ORIG_HOME"
  rm -rf "$TEST_TMP"
}

test_help_short() {
  setup
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" -h
  assert_status "exits 0 on -h" 0 "$RUN_STATUS"
  assert_contains "shows usage on -h" "$RUN_STDOUT" "Usage:"
  assert_contains "shows check option" "$RUN_STDOUT" "--check"
  assert_contains "shows repair option" "$RUN_STDOUT" "--repair"
  teardown
}

test_help_long() {
  setup
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --help
  assert_status "exits 0 on --help" 0 "$RUN_STATUS"
  assert_contains "shows usage on --help" "$RUN_STDOUT" "Usage:"
  teardown
}

test_unrecognized_option() {
  setup
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --bogus-opt
  assert_status "exits 1 on unrecognized option" 1 "$RUN_STATUS"
  assert_contains "reports unrecognized option" "$RUN_STDOUT" "error: unrecognized option: --bogus-opt"
  teardown
}

test_check_intact() {
  setup
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$AGENT_DIR" --check
  assert_status "exits 0 when everything is intact" 0 "$RUN_STATUS"
  assert_contains "reports all intact" "$RUN_STDOUT" "all symlinks and build artifacts intact"
  teardown
}

test_check_missing_agent_dir() {
  setup
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$TEST_TMP/nonexistent" --check
  assert_status "exits 1 when agent-settings dir is missing" 1 "$RUN_STATUS"
  assert_contains "reports missing directory" "$RUN_STDOUT" "directory not found"
  teardown
}

test_check_missing_links_file() {
  setup
  rm -f "$AGENT_DIR/links"
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$AGENT_DIR" --check
  assert_status "exits 1 when links file missing" 1 "$RUN_STATUS"
  assert_contains "reports missing links file" "$RUN_STDOUT" "links file missing"
  teardown
}

test_check_missing_harnesses_file() {
  setup
  rm -f "$AGENT_DIR/harnesses"
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$AGENT_DIR" --check
  assert_status "exits 1 when harnesses file missing" 1 "$RUN_STATUS"
  assert_contains "reports missing harnesses file" "$RUN_STDOUT" "harnesses file missing"
  teardown
}

test_check_missing_build_artifact() {
  setup
  rm -rf "$AGENT_DIR/build"
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$AGENT_DIR" --check
  assert_status "exits 1 when build artifact is missing" 1 "$RUN_STATUS"
  assert_contains "reports missing build artifact" "$RUN_STDOUT" "missing build artifact"
  teardown
}

test_check_stale_build_artifact() {
  setup
  printf 'stale-content\n' >"$AGENT_DIR/build/CLAUDE.md"
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$AGENT_DIR" --check
  assert_status "exits 1 when build artifact is stale" 1 "$RUN_STATUS"
  assert_contains "reports stale build artifact" "$RUN_STDOUT" "stale build artifact"
  teardown
}

test_check_missing_symlink() {
  setup
  rm -f "$HOME/.claude/CLAUDE.md"
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$AGENT_DIR" --check
  assert_status "exits 1 when symlink is missing" 1 "$RUN_STATUS"
  assert_contains "reports not a symlink" "$RUN_STDOUT" "not a symlink"
  teardown
}

test_check_dangling_symlink() {
  setup
  rm -f "$AGENT_DIR/dot-claude/settings.json"
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$AGENT_DIR" --check
  assert_status "exits 1 when symlink is dangling" 1 "$RUN_STATUS"
  assert_contains "reports dangling symlink" "$RUN_STDOUT" "dangling symlink"
  teardown
}

test_check_incorrect_target_symlink() {
  setup
  ln -sfn "/tmp" "$HOME/.claude/CLAUDE.md"
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$AGENT_DIR" --check
  assert_status "exits 1 when symlink points to wrong target" 1 "$RUN_STATUS"
  assert_contains "reports incorrect symlink target" "$RUN_STDOUT" "incorrect symlink target"
  teardown
}

test_set_mode_and_load_config() {
  setup
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --set-mode auto-restore
  assert_status "exits 0 on --set-mode" 0 "$RUN_STATUS"
  assert_contains "reports mode saved" "$RUN_STDOUT" "Saved mode=auto-restore"

  _config_content=$(cat "$XDG_CONFIG_HOME/workstation-scripts/ensure-agent-settings.conf")
  assert_contains "config file contains mode" "$_config_content" "mode=auto-restore"

  # Run --status and verify mode is loaded
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$AGENT_DIR" --status
  assert_status "exits 0 on --status" 0 "$RUN_STATUS"
  assert_contains "status displays mode auto-restore" "$RUN_STDOUT" "Mode:               auto-restore"
  teardown
}

test_set_mode_invalid() {
  setup
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --set-mode invalid-mode
  assert_status "exits 1 on invalid mode" 1 "$RUN_STATUS"
  assert_contains "reports invalid mode error" "$RUN_STDOUT" "error: invalid mode"
  teardown
}

test_notify_mode_on_failure() {
  setup
  rm -rf "$AGENT_DIR/build"
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$AGENT_DIR" --mode notify
  assert_status "exits 1 in notify mode on failure" 1 "$RUN_STATUS"
  assert_contains "notifies user" "$(cat "$NOTIFY_LOG")" "display notification"
  assert_contains "mentions broken items" "$(cat "$NOTIFY_LOG")" "Broken symlinks"
  teardown
}

test_no_notify_suppresses_notification() {
  setup
  rm -rf "$AGENT_DIR/build"
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$AGENT_DIR" --mode notify --no-notify
  assert_status "exits 1 in notify mode on failure" 1 "$RUN_STATUS"
  assert_eq "notification suppressed" "" "$(cat "$NOTIFY_LOG")"
  teardown
}

test_auto_restore_mode_repairs_and_notifies() {
  setup
  rm -rf "$AGENT_DIR/build"
  rm -f "$HOME/.claude/CLAUDE.md"
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$AGENT_DIR" --mode auto-restore
  assert_status "exits 0 when auto-restore succeeds" 0 "$RUN_STATUS"
  assert_contains "auto-restore success message" "$RUN_STDOUT" "auto-restore succeeded"
  assert_contains "notifies on recovery" "$(cat "$NOTIFY_LOG")" "automatically restored"

  # Verify files were actually restored
  if [ -f "$AGENT_DIR/build/CLAUDE.md" ]; then
    pass "build artifact restored"
  else
    fail "build artifact not restored"
  fi
  if [ -L "$HOME/.claude/CLAUDE.md" ]; then
    pass "symlink restored"
  else
    fail "symlink not restored"
  fi
  teardown
}

test_repair_action() {
  setup
  rm -rf "$AGENT_DIR/build"
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$AGENT_DIR" --repair
  assert_status "exits 0 on --repair" 0 "$RUN_STATUS"
  assert_contains "repair success message" "$RUN_STDOUT" "repair succeeded"
  if [ -f "$AGENT_DIR/build/CLAUDE.md" ]; then
    pass "build artifact created"
  else
    fail "build artifact missing"
  fi
  teardown
}

test_repair_fails_when_install_not_executable() {
  setup
  chmod -x "$AGENT_DIR/install.sh"
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$AGENT_DIR" --repair
  assert_status "exits 1 when installer not executable" 1 "$RUN_STATUS"
  assert_contains "reports installer not executable" "$RUN_STDOUT" "installer not executable"
  teardown
}

test_install_and_uninstall_launchd_service() {
  setup
  export UNAME_OS="Darwin"
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$AGENT_DIR" --install-service
  assert_status "exits 0 installing launchd service" 0 "$RUN_STATUS"

  _plist_file="$HOME/Library/LaunchAgents/com.kjiwa.agent-settings.plist"
  if [ -f "$_plist_file" ]; then
    pass "launchd plist created"
  else
    fail "launchd plist not created"
  fi

  _plist_content=$(cat "$_plist_file")
  assert_contains "plist has label" "$_plist_content" "<string>com.kjiwa.agent-settings</string>"
  assert_contains "plist has watch path build" "$_plist_content" "<string>$AGENT_DIR/build</string>"
  assert_contains "plist has watch path links" "$_plist_content" "<string>$AGENT_DIR/links</string>"
  assert_contains "plist has watch path destination" "$_plist_content" "<string>$HOME/.claude/CLAUDE.md</string>"
  assert_contains "launchctl bootstrapped" "$(cat "$LAUNCHCTL_LOG")" "bootstrap"

  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$AGENT_DIR" --uninstall-service
  assert_status "exits 0 uninstalling launchd service" 0 "$RUN_STATUS"
  if [ ! -f "$_plist_file" ]; then
    pass "launchd plist removed"
  else
    fail "launchd plist still exists"
  fi
  assert_contains "launchctl booted out" "$(cat "$LAUNCHCTL_LOG")" "bootout"
  teardown
}

test_install_and_uninstall_systemd_service() {
  setup
  export UNAME_OS="Linux"
  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$AGENT_DIR" --install-service
  assert_status "exits 0 installing systemd service" 0 "$RUN_STATUS"

  _path_unit="$HOME/.config/systemd/user/agent-settings.path"
  _service_unit="$HOME/.config/systemd/user/agent-settings.service"

  if [ -f "$_path_unit" ]; then
    pass "systemd path unit created"
  else
    fail "systemd path unit not created"
  fi
  if [ -f "$_service_unit" ]; then
    pass "systemd service unit created"
  else
    fail "systemd service unit not created"
  fi

  _path_content=$(cat "$_path_unit")
  assert_contains "path unit has PathModified build" "$_path_content" "PathModified=$AGENT_DIR/build"
  assert_contains "path unit has PathModified link" "$_path_content" "PathModified=$HOME/.claude/CLAUDE.md"
  assert_contains "systemctl invoked" "$(cat "$SYSTEMCTL_LOG")" "enable --now agent-settings.path"

  run_capture "$REPO_DIR/bin/ensure-agent-settings.sh" --dir "$AGENT_DIR" --uninstall-service
  assert_status "exits 0 uninstalling systemd service" 0 "$RUN_STATUS"
  if [ ! -f "$_path_unit" ]; then
    pass "systemd path unit removed"
  else
    fail "systemd path unit still exists"
  fi
  if [ ! -f "$_service_unit" ]; then
    pass "systemd service unit removed"
  else
    fail "systemd service unit still exists"
  fi
  assert_contains "systemctl disabled" "$(cat "$SYSTEMCTL_LOG")" "disable --now agent-settings.path"
  teardown
}

main() {
  test_help_short
  test_help_long
  test_unrecognized_option
  test_check_intact
  test_check_missing_agent_dir
  test_check_missing_links_file
  test_check_missing_harnesses_file
  test_check_missing_build_artifact
  test_check_stale_build_artifact
  test_check_missing_symlink
  test_check_dangling_symlink
  test_check_incorrect_target_symlink
  test_set_mode_and_load_config
  test_set_mode_invalid
  test_notify_mode_on_failure
  test_no_notify_suppresses_notification
  test_auto_restore_mode_repairs_and_notifies
  test_repair_action
  test_repair_fails_when_install_not_executable
  test_install_and_uninstall_launchd_service
  test_install_and_uninstall_systemd_service
  test_summary
}

main "$@"
