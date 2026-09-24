#!/bin/sh
# Hermetic unit tests for macos/keep-awake.sh using mock binaries.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=../lib/harness.sh
. "$SCRIPT_DIR/../lib/harness.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly REPO_DIR

_create_mock_uname() {
  _create_mock_uname_dir="$1"
  cat <<'EOF' >"$_create_mock_uname_dir/uname"
#!/bin/sh
set -eu
if [ "${1:-}" = "-s" ]; then
  echo "${UNAME_OS:-Darwin}"
  exit 0
fi
exec /usr/bin/uname "$@"
EOF
  chmod +x "$_create_mock_uname_dir/uname"
}

_create_mock_sudo() {
  _create_mock_sudo_dir="$1"
  cat <<'EOF' >"$_create_mock_sudo_dir/sudo"
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$SUDO_LOG"
case "${1:-}" in
  -v)
    exit "${MOCK_SUDO_V_EXIT:-0}"
    ;;
  -n)
    exit 0
    ;;
  *)
    exec "$@"
    ;;
esac
EOF
  chmod +x "$_create_mock_sudo_dir/sudo"
}

_create_mock_pmset() {
  _create_mock_pmset_dir="$1"
  cat <<'EOF' >"$_create_mock_pmset_dir/pmset"
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$PMSET_LOG"
if [ "${1:-}" = "-g" ]; then
  printf ' SleepDisabled\t\t%s\n' "${MOCK_PMSET_SLEEP_DISABLED:-0}"
  exit 0
fi
if [ "${1:-}" = "-a" ] && [ "${2:-}" = "disablesleep" ]; then
  exit "${MOCK_PMSET_DISABLESLEEP_EXIT:-0}"
fi
exit 0
EOF
  chmod +x "$_create_mock_pmset_dir/pmset"
}

_create_mock_caffeinate() {
  _create_mock_caffeinate_dir="$1"
  cat <<'EOF' >"$_create_mock_caffeinate_dir/caffeinate"
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$CAFFEINATE_LOG"
if [ $# -gt 0 ]; then
  exec "$@"
fi
if [ -n "${MOCK_CAFFEINATE_SLEEP:-}" ]; then
  exec sleep "$MOCK_CAFFEINATE_SLEEP"
fi
exit "${MOCK_CAFFEINATE_EXIT:-0}"
EOF
  chmod +x "$_create_mock_caffeinate_dir/caffeinate"
}

_create_mocks() {
  _create_mocks_dir="$1"
  mkdir -p "$_create_mocks_dir"
  _create_mock_uname "$_create_mocks_dir"
  _create_mock_sudo "$_create_mocks_dir"
  _create_mock_pmset "$_create_mocks_dir"
  _create_mock_caffeinate "$_create_mocks_dir"
}

setup() {
  TEST_TMP="$(mktemp -d)"
  export TEST_TMP
  export SUDO_LOG="$TEST_TMP/sudo.log"
  export PMSET_LOG="$TEST_TMP/pmset.log"
  export CAFFEINATE_LOG="$TEST_TMP/caffeinate.log"
  export UNAME_OS="Darwin"
  export MOCK_SUDO_V_EXIT=0
  export MOCK_PMSET_SLEEP_DISABLED=0
  export MOCK_PMSET_DISABLESLEEP_EXIT=0
  export MOCK_CAFFEINATE_EXIT=0
  export MOCK_CAFFEINATE_SLEEP=""

  : > "$SUDO_LOG"
  : > "$PMSET_LOG"
  : > "$CAFFEINATE_LOG"

  _create_mocks "$TEST_TMP/bin"

  OLD_PATH="$PATH"
  export OLD_PATH
  export PATH="$TEST_TMP/bin:$PATH"
}

teardown() {
  export PATH="$OLD_PATH"
  rm -rf "$TEST_TMP"
}

test_help_short() {
  setup
  run_capture "$REPO_DIR/macos/keep-awake.sh" -h
  assert_status "exits 0 on -h" 0 "$RUN_STATUS"
  assert_contains "shows usage on -h" "$RUN_STDOUT" "Usage: keep-awake.sh"
  assert_contains "shows command arg on -h" "$RUN_STDOUT" "command [args...]"
  assert_contains "shows caffeinate on -h" "$RUN_STDOUT" "caffeinate"
  assert_contains "shows Ctrl-C on -h" "$RUN_STDOUT" "Ctrl-C"
  teardown
}

test_help_long() {
  setup
  run_capture "$REPO_DIR/macos/keep-awake.sh" --help
  assert_status "exits 0 on --help" 0 "$RUN_STATUS"
  assert_contains "shows usage on --help" "$RUN_STDOUT" "Usage: keep-awake.sh"
  assert_contains "shows command arg on --help" "$RUN_STDOUT" "command [args...]"
  assert_contains "shows caffeinate on --help" "$RUN_STDOUT" "caffeinate"
  assert_contains "shows Ctrl-C on --help" "$RUN_STDOUT" "Ctrl-C"
  assert_contains "shows disablesleep on --help" "$RUN_STDOUT" "pmset -a disablesleep 1"
  teardown
}

test_invalid_option() {
  setup
  run_capture "$REPO_DIR/macos/keep-awake.sh" -x
  assert_status "exits 1 on invalid option" 1 "$RUN_STATUS"
  assert_contains "shows usage on invalid option" "$RUN_STDOUT" "Usage: keep-awake.sh"
  teardown
}

test_non_darwin_os() {
  setup
  UNAME_OS="Linux"
  run_capture "$REPO_DIR/macos/keep-awake.sh"
  assert_status "exits 1 on non-Darwin OS" 1 "$RUN_STATUS"
  assert_contains "reports macOS required" "$RUN_STDOUT" "macOS (Darwin) required"
  teardown
}

test_sudo_failure() {
  setup
  MOCK_SUDO_V_EXIT=1
  run_capture "$REPO_DIR/macos/keep-awake.sh"
  assert_status "exits 1 on sudo failure" 1 "$RUN_STATUS"
  assert_contains "reports sudo authentication failure" "$RUN_STDOUT" "sudo authentication failed"
  teardown
}

test_disablesleep_failure() {
  setup
  MOCK_PMSET_DISABLESLEEP_EXIT=1
  run_capture "$REPO_DIR/macos/keep-awake.sh"
  assert_status "exits 1 when disabling sleep fails" 1 "$RUN_STATUS"
  assert_contains "reports sleep disable failure" "$RUN_STDOUT" "failed to disable sleep"
  teardown
}

test_already_disabled_runs_command_and_does_not_modify_sleep() {
  setup
  MOCK_PMSET_SLEEP_DISABLED=1
  run_capture "$REPO_DIR/macos/keep-awake.sh" sh -c "echo hello"
  assert_status "exits 0 when sleep was already disabled" 0 "$RUN_STATUS"
  assert_contains "command output present" "$RUN_STDOUT" "hello"

  _test_pmset_log="$(cat "$PMSET_LOG" 2>/dev/null || true)"
  assert_contains "queries sleep status" "$_test_pmset_log" "-g"
  assert_not_contains "does not disable sleep again" "$_test_pmset_log" "disablesleep 1"
  assert_not_contains "does not re-enable sleep on exit" "$_test_pmset_log" "disablesleep 0"
  teardown
}

test_disables_and_restores_sleep_around_command() {
  setup
  MOCK_PMSET_SLEEP_DISABLED=0
  run_capture "$REPO_DIR/macos/keep-awake.sh" sh -c "echo running-cmd"
  assert_status "exits 0 after command completes" 0 "$RUN_STATUS"
  assert_contains "command executed" "$RUN_STDOUT" "running-cmd"
  assert_contains "restoring sleep message printed" "$RUN_STDOUT" "Restoring sleep settings..."

  _test_pmset_log="$(cat "$PMSET_LOG" 2>/dev/null || true)"
  assert_contains "disables sleep before running command" "$_test_pmset_log" "-a disablesleep 1"
  assert_contains "restores sleep after running command" "$_test_pmset_log" "-a disablesleep 0"

  _test_caffeinate_log="$(cat "$CAFFEINATE_LOG" 2>/dev/null || true)"
  assert_contains "caffeinates wrapped command" "$_test_caffeinate_log" "sh -c echo running-cmd"
  teardown
}

test_propagates_command_exit_code() {
  setup
  MOCK_PMSET_SLEEP_DISABLED=0
  run_capture "$REPO_DIR/macos/keep-awake.sh" sh -c "exit 42"
  assert_status "propagates exit code 42" 42 "$RUN_STATUS"

  _test_pmset_log="$(cat "$PMSET_LOG" 2>/dev/null || true)"
  assert_contains "still restores sleep on non-zero exit" "$_test_pmset_log" "-a disablesleep 0"
  teardown
}

test_double_dash_delimiter() {
  setup
  MOCK_PMSET_SLEEP_DISABLED=0
  run_capture "$REPO_DIR/macos/keep-awake.sh" -- sh -c "echo dash-worked"
  assert_status "exits 0 with double dash" 0 "$RUN_STATUS"
  assert_contains "executes command after double dash" "$RUN_STDOUT" "dash-worked"
  teardown
}

test_interactive_mode_runs_caffeinate() {
  setup
  MOCK_PMSET_SLEEP_DISABLED=0
  run_capture "$REPO_DIR/macos/keep-awake.sh"
  assert_status "exits 0 when caffeinate exits normally" 0 "$RUN_STATUS"
  assert_contains "shows awake message" "$RUN_STDOUT" "Sleep disabled. Keeping system awake."
  assert_contains "shows restore message" "$RUN_STDOUT" "Restoring sleep settings..."

  _test_caffeinate_log="$(cat "$CAFFEINATE_LOG" 2>/dev/null || true)"
  assert_eq "runs caffeinate with no arguments" "" "$_test_caffeinate_log"
  teardown
}

test_sigterm_restores_sleep() {
  setup
  MOCK_PMSET_SLEEP_DISABLED=0
  MOCK_CAFFEINATE_SLEEP="5"

  "$REPO_DIR/macos/keep-awake.sh" >"$TEST_TMP/script.out" 2>&1 &
  _test_pid=$!

  _test_wait_count=0
  while [ ! -s "$CAFFEINATE_LOG" ] && [ "$_test_wait_count" -lt 30 ]; do
    sleep 0.1
    _test_wait_count=$((_test_wait_count + 1))
  done

  kill -TERM "$_test_pid"
  set +e
  wait "$_test_pid"
  _test_status=$?
  set -e

  assert_status "exits 143 on SIGTERM" 143 "$_test_status"
  _test_pmset_log="$(cat "$PMSET_LOG" 2>/dev/null || true)"
  assert_contains "restores sleep on SIGTERM" "$_test_pmset_log" "-a disablesleep 0"
  teardown
}

test_sigint_restores_sleep() {
  setup
  MOCK_PMSET_SLEEP_DISABLED=0
  MOCK_CAFFEINATE_SLEEP="5"

  if command -v perl >/dev/null 2>&1; then
    set +e
    perl -e '
      use POSIX ":sys_wait_h";
      $pid = fork();
      if ($pid == 0) {
        $SIG{INT} = "DEFAULT";
        exec(@ARGV);
      }
      my $log = $ENV{CAFFEINATE_LOG};
      for (1..50) {
        last if -s $log;
        select(undef, undef, undef, 0.05);
      }
      kill "INT", $pid;
      waitpid($pid, 0);
      exit($? >> 8);
    ' "$REPO_DIR/macos/keep-awake.sh" >"$TEST_TMP/script.out" 2>&1
    _test_status=$?
    set -e

    assert_status "exits 130 on SIGINT" 130 "$_test_status"
    _test_pmset_log="$(cat "$PMSET_LOG" 2>/dev/null || true)"
    assert_contains "restores sleep on SIGINT" "$_test_pmset_log" "-a disablesleep 0"
  fi
  teardown
}

test_sighup_restores_sleep() {
  setup
  MOCK_PMSET_SLEEP_DISABLED=0
  MOCK_CAFFEINATE_SLEEP="5"

  "$REPO_DIR/macos/keep-awake.sh" >"$TEST_TMP/script.out" 2>&1 &
  _test_pid=$!

  _test_wait_count=0
  while [ ! -s "$CAFFEINATE_LOG" ] && [ "$_test_wait_count" -lt 30 ]; do
    sleep 0.1
    _test_wait_count=$((_test_wait_count + 1))
  done

  kill -HUP "$_test_pid"
  set +e
  wait "$_test_pid"
  _test_status=$?
  set -e

  assert_status "exits 129 on SIGHUP" 129 "$_test_status"
  _test_pmset_log="$(cat "$PMSET_LOG" 2>/dev/null || true)"
  assert_contains "restores sleep on SIGHUP" "$_test_pmset_log" "-a disablesleep 0"
  teardown
}

main() {
  test_help_short
  test_help_long
  test_invalid_option
  test_non_darwin_os
  test_sudo_failure
  test_disablesleep_failure
  test_already_disabled_runs_command_and_does_not_modify_sleep
  test_disables_and_restores_sleep_around_command
  test_propagates_command_exit_code
  test_double_dash_delimiter
  test_interactive_mode_runs_caffeinate
  test_sigterm_restores_sleep
  test_sigint_restores_sleep
  test_sighup_restores_sleep
  test_summary
}

main "$@"

