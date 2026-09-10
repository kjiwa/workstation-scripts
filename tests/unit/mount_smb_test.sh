#!/bin/sh
# Hermetic unit tests for macos/mount-smb.sh using mock binaries.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=../lib/harness.sh
. "$SCRIPT_DIR/../lib/harness.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly REPO_DIR

setup() {
  TEST_TMP="$(mktemp -d)"
  export TEST_TMP
  export MOUNT_LOG="$TEST_TMP/mount.log"
  export MDUTIL_LOG="$TEST_TMP/mdutil.log"
  export UNAME_OS="Darwin"
  export MOCK_MOUNT_EXIT=0
  export MOCK_MDUTIL_EXIT=0

  mkdir -p "$TEST_TMP/bin"

  cat <<'EOF' >"$TEST_TMP/bin/uname"
#!/bin/sh
set -eu
if [ "${1:-}" = "-s" ]; then
  echo "${UNAME_OS:-Darwin}"
  exit 0
fi
exec /usr/bin/uname "$@"
EOF
  chmod +x "$TEST_TMP/bin/uname"

  cat <<'EOF' >"$TEST_TMP/bin/mount"
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$MOUNT_LOG"
exit "${MOCK_MOUNT_EXIT:-0}"
EOF
  chmod +x "$TEST_TMP/bin/mount"

  cat <<'EOF' >"$TEST_TMP/bin/mdutil"
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$MDUTIL_LOG"
exit "${MOCK_MDUTIL_EXIT:-0}"
EOF
  chmod +x "$TEST_TMP/bin/mdutil"

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
  run_capture "$REPO_DIR/macos/mount-smb.sh" -h
  assert_status "exits 0 on -h" 0 "$RUN_STATUS"
  assert_contains "shows usage on -h" "$RUN_STDOUT" "Usage: mount-smb.sh"
  teardown
}

test_help_long() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" --help
  assert_status "exits 0 on --help" 0 "$RUN_STATUS"
  assert_contains "shows usage on --help" "$RUN_STDOUT" "Usage: mount-smb.sh"
  teardown
}

test_missing_args() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh"
  assert_status "exits 1 on missing args" 1 "$RUN_STATUS"
  assert_contains "shows usage on missing args" "$RUN_STDOUT" "Usage: mount-smb.sh"
  teardown
}

test_one_arg_missing() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" "//server/share"
  assert_status "exits 1 when mount point is missing" 1 "$RUN_STATUS"
  assert_contains "shows usage when mount point is missing" "$RUN_STDOUT" "Usage: mount-smb.sh"
  teardown
}

test_unknown_option() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" --invalid
  assert_status "exits 1 on invalid option" 1 "$RUN_STATUS"
  assert_contains "shows usage on invalid option" "$RUN_STDOUT" "Usage: mount-smb.sh"
  teardown
}

test_empty_args() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" "" "$TEST_TMP/mnt"
  assert_status "exits 1 on empty URL" 1 "$RUN_STATUS"

  run_capture "$REPO_DIR/macos/mount-smb.sh" "//server/share" ""
  assert_status "exits 1 on empty mount point" 1 "$RUN_STATUS"
  teardown
}

test_non_darwin_os() {
  setup
  UNAME_OS="Linux"
  run_capture "$REPO_DIR/macos/mount-smb.sh" "//server/share" "$TEST_TMP/mnt"
  assert_status "exits 1 on non-Darwin OS" 1 "$RUN_STATUS"
  assert_contains "reports macOS required" "$RUN_STDOUT" "macOS (Darwin) required"
  teardown
}

test_missing_share_in_url() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" "//server" "$TEST_TMP/mnt"
  assert_status "exits 1 when share missing" 1 "$RUN_STATUS"
  assert_contains "reports share required" "$RUN_STDOUT" "URL must include server and share"

  run_capture "$REPO_DIR/macos/mount-smb.sh" "smb://user@server" "$TEST_TMP/mnt"
  assert_status "exits 1 when share missing with user" 1 "$RUN_STATUS"
  teardown
}

test_successful_mount_default_opts() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" "smb://user@server/share" "$TEST_TMP/mnt"
  assert_status "exits 0 on valid mount" 0 "$RUN_STATUS"

  _mount_log=$(cat "$MOUNT_LOG" 2>/dev/null || true)
  assert_contains "mount invoked with smbfs and default opts" "$_mount_log" "-t smbfs -o nodatacache,nomdatacache,nobrowse //user@server/share $TEST_TMP/mnt"

  _mdutil_log=$(cat "$MDUTIL_LOG" 2>/dev/null || true)
  assert_contains "mdutil disables indexing" "$_mdutil_log" "-i off $TEST_TMP/mnt"
  teardown
}

test_normalize_url_slashes() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" "smb://server/share/" "$TEST_TMP/mnt"
  assert_status "exits 0 with trailing slash" 0 "$RUN_STATUS"

  _mount_log=$(cat "$MOUNT_LOG" 2>/dev/null || true)
  assert_contains "trailing slash stripped" "$_mount_log" "//server/share $TEST_TMP/mnt"
  teardown
}

test_normalize_url_without_prefix() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" "server/share" "$TEST_TMP/mnt"
  assert_status "exits 0 without prefix" 0 "$RUN_STATUS"

  _mount_log=$(cat "$MOUNT_LOG" 2>/dev/null || true)
  assert_contains "prefix added" "$_mount_log" "//server/share $TEST_TMP/mnt"
  teardown
}

test_extra_options() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" -o "ro,nostreams" "//server/share" "$TEST_TMP/mnt"
  assert_status "exits 0 with extra options" 0 "$RUN_STATUS"

  _mount_log=$(cat "$MOUNT_LOG" 2>/dev/null || true)
  assert_contains "mount carries extra options" "$_mount_log" "-t smbfs -o nodatacache,nomdatacache,nobrowse,ro,nostreams //server/share $TEST_TMP/mnt"
  teardown
}

test_creates_mount_directory() {
  setup
  _target_dir="$TEST_TMP/new_mnt_dir"
  run_capture "$REPO_DIR/macos/mount-smb.sh" "//server/share" "$_target_dir"
  assert_status "exits 0 creating mount point" 0 "$RUN_STATUS"
  if [ -d "$_target_dir" ]; then
    pass "creates mount point directory"
  else
    fail "creates mount point directory" "directory was not created"
  fi
  teardown
}

test_mdutil_failure_is_nonfatal() {
  setup
  MOCK_MDUTIL_EXIT=1
  run_capture "$REPO_DIR/macos/mount-smb.sh" "//server/share" "$TEST_TMP/mnt"
  assert_status "exits 0 when mdutil fails" 0 "$RUN_STATUS"
  teardown
}

main() {
  test_help_short
  test_help_long
  test_missing_args
  test_one_arg_missing
  test_unknown_option
  test_empty_args
  test_non_darwin_os
  test_missing_share_in_url
  test_successful_mount_default_opts
  test_normalize_url_slashes
  test_normalize_url_without_prefix
  test_extra_options
  test_creates_mount_directory
  test_mdutil_failure_is_nonfatal
  test_summary
}

main "$@"