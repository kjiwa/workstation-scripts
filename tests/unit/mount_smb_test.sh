#!/bin/sh
# Hermetic unit tests for macos/mount-smb.sh using mock binaries.
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

_create_mock_mount() {
  _create_mock_mount_dir="$1"
  cat <<'EOF' >"$_create_mock_mount_dir/mount"
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$MOUNT_LOG"
exit "${MOCK_MOUNT_EXIT:-0}"
EOF
  chmod +x "$_create_mock_mount_dir/mount"
}

_create_mock_mdutil() {
  _create_mock_mdutil_dir="$1"
  cat <<'EOF' >"$_create_mock_mdutil_dir/mdutil"
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$MDUTIL_LOG"
exit "${MOCK_MDUTIL_EXIT:-0}"
EOF
  chmod +x "$_create_mock_mdutil_dir/mdutil"
}

_create_mock_id() {
  _create_mock_id_dir="$1"
  cat <<'EOF' >"$_create_mock_id_dir/id"
#!/bin/sh
set -eu
case "${1:-}" in
  -u)
    echo "${MOCK_ID_U:-501}"
    ;;
  -g)
    echo "${MOCK_ID_G:-20}"
    ;;
  *)
    exec env PATH="$OLD_PATH" id "$@"
    ;;
esac
EOF
  chmod +x "$_create_mock_id_dir/id"
}

_create_mock_stat() {
  _create_mock_stat_dir="$1"
  cat <<'EOF' >"$_create_mock_stat_dir/stat"
#!/bin/sh
set -eu
if [ "${1:-}" = "-f" ] && [ "${2:-}" = "%u" ]; then
  echo "${MOCK_STAT_UID:-501}"
  exit 0
fi
exec env PATH="$OLD_PATH" stat "$@"
EOF
  chmod +x "$_create_mock_stat_dir/stat"
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
  mkdir)
    shift
    exit_code="${MOCK_SUDO_MKDIR_EXIT:-0}"
    if [ "$exit_code" -ne 0 ]; then
      exit "$exit_code"
    fi
    for _sudo_arg in "$@"; do
      case "$_sudo_arg" in
        -*) continue ;;
        *)
          _sudo_parent="$(dirname "$_sudo_arg")"
          while [ "$_sudo_parent" != "." ] && [ "$_sudo_parent" != "/" ] && [ -d "$_sudo_parent" ]; do
            chmod u+w "$_sudo_parent" 2>/dev/null || true
            _sudo_parent="$(dirname "$_sudo_parent")"
          done
          ;;
      esac
    done
    exec mkdir "$@"
    ;;
  chown)
    shift
    exit "${MOCK_SUDO_CHOWN_EXIT:-0}"
    ;;
  rmdir)
    shift
    exit_code="${MOCK_SUDO_RMDIR_EXIT:-0}"
    if [ "$exit_code" -ne 0 ]; then
      exit "$exit_code"
    fi
    for _sudo_arg in "$@"; do
      _sudo_parent="$(dirname "$_sudo_arg")"
      chmod u+w "$_sudo_parent" 2>/dev/null || true
    done
    exec rmdir "$@"
    ;;
  *)
    exec "$@"
    ;;
esac
EOF
  chmod +x "$_create_mock_sudo_dir/sudo"
}

_create_mocks() {
  _create_mocks_dir="$1"
  mkdir -p "$_create_mocks_dir"
  _create_mock_uname "$_create_mocks_dir"
  _create_mock_mount "$_create_mocks_dir"
  _create_mock_mdutil "$_create_mocks_dir"
  _create_mock_id "$_create_mocks_dir"
  _create_mock_stat "$_create_mocks_dir"
  _create_mock_sudo "$_create_mocks_dir"
}

setup() {
  TEST_TMP="$(mktemp -d)"
  export TEST_TMP
  export MOUNT_LOG="$TEST_TMP/mount.log"
  export MDUTIL_LOG="$TEST_TMP/mdutil.log"
  export SUDO_LOG="$TEST_TMP/sudo.log"
  export UNAME_OS="Darwin"
  export MOCK_MOUNT_EXIT=0
  export MOCK_MDUTIL_EXIT=0
  export MOCK_ID_U=501
  export MOCK_ID_G=20
  export MOCK_STAT_UID=501
  export MOCK_SUDO_V_EXIT=0
  export MOCK_SUDO_MKDIR_EXIT=0
  export MOCK_SUDO_CHOWN_EXIT=0
  export MOCK_SUDO_RMDIR_EXIT=0

  : > "$MOUNT_LOG"
  : > "$MDUTIL_LOG"
  : > "$SUDO_LOG"

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
  run_capture "$REPO_DIR/macos/mount-smb.sh" -h
  assert_status "exits 0 on -h" 0 "$RUN_STATUS"
  assert_contains "shows usage on -h" "$RUN_STDOUT" "Usage: mount-smb.sh"
  assert_contains "shows mount_point arg on -h" "$RUN_STDOUT" "<mount_point>"
  assert_contains "shows extra_opts on -h" "$RUN_STDOUT" "-o extra_opts"
  assert_contains "shows default opts on -h" "$RUN_STDOUT" "nodatacache"
  teardown
}

test_help_long() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" --help
  assert_status "exits 0 on --help" 0 "$RUN_STATUS"
  assert_contains "shows usage on --help" "$RUN_STDOUT" "Usage: mount-smb.sh"
  assert_contains "shows mount_point arg on --help" "$RUN_STDOUT" "<mount_point>"
  assert_contains "shows extra_opts on --help" "$RUN_STDOUT" "-o extra_opts"
  assert_contains "shows default opts on --help" "$RUN_STDOUT" "nodatacache"
  assert_contains "shows mdutil on --help" "$RUN_STDOUT" "mdutil -i off"
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

  _test_successful_mount_default_opts_mount_log=$(cat "$MOUNT_LOG" 2>/dev/null || true)
  assert_contains "mount invoked with smbfs and default opts" "$_test_successful_mount_default_opts_mount_log" "-t smbfs -o nodatacache,nomdatacache,nobrowse //user@server/share $TEST_TMP/mnt"

  _test_successful_mount_default_opts_mdutil_log=$(cat "$MDUTIL_LOG" 2>/dev/null || true)
  assert_contains "mdutil disables indexing" "$_test_successful_mount_default_opts_mdutil_log" "-i off $TEST_TMP/mnt"
  teardown
}

test_normalize_url_slashes() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" "smb://server/share/" "$TEST_TMP/mnt"
  assert_status "exits 0 with trailing slash" 0 "$RUN_STATUS"

  _test_normalize_url_slashes_mount_log=$(cat "$MOUNT_LOG" 2>/dev/null || true)
  assert_contains "trailing slash stripped" "$_test_normalize_url_slashes_mount_log" "//server/share $TEST_TMP/mnt"
  teardown
}

test_normalize_url_without_prefix() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" "server/share" "$TEST_TMP/mnt"
  assert_status "exits 0 without prefix" 0 "$RUN_STATUS"

  _test_normalize_url_without_prefix_mount_log=$(cat "$MOUNT_LOG" 2>/dev/null || true)
  assert_contains "prefix added" "$_test_normalize_url_without_prefix_mount_log" "//server/share $TEST_TMP/mnt"
  teardown
}

test_extra_options() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" -o "ro,nostreams" "//server/share" "$TEST_TMP/mnt"
  assert_status "exits 0 with extra options" 0 "$RUN_STATUS"

  _test_extra_options_mount_log=$(cat "$MOUNT_LOG" 2>/dev/null || true)
  assert_contains "mount carries extra options" "$_test_extra_options_mount_log" "-t smbfs -o nodatacache,nomdatacache,nobrowse,ro,nostreams //server/share $TEST_TMP/mnt"
  teardown
}

test_creates_mount_directory() {
  setup
  _test_creates_mount_directory_target_dir="$TEST_TMP/new_mnt_dir"
  run_capture "$REPO_DIR/macos/mount-smb.sh" "//server/share" "$_test_creates_mount_directory_target_dir"
  assert_status "exits 0 creating mount point" 0 "$RUN_STATUS"
  if [ -d "$_test_creates_mount_directory_target_dir" ]; then
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

test_double_dash_delimiter() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" -- "//server/share" "$TEST_TMP/mnt"
  assert_status "exits 0 with double dash" 0 "$RUN_STATUS"
  teardown
}

test_option_missing_arg() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" -o
  assert_status "exits 1 on -o without argument" 1 "$RUN_STATUS"

  run_capture "$REPO_DIR/macos/mount-smb.sh" -o "" "//server/share" "$TEST_TMP/mnt"
  assert_status "exits 1 on -o with empty argument" 1 "$RUN_STATUS"
  teardown
}

test_multiple_extra_options() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" -o "ro" -o "nostreams" "//server/share" "$TEST_TMP/mnt"
  assert_status "exits 0 with multiple -o flags" 0 "$RUN_STATUS"

  _test_multiple_extra_options_mount_log=$(cat "$MOUNT_LOG" 2>/dev/null || true)
  assert_contains "mount carries all accumulated options" "$_test_multiple_extra_options_mount_log" "-t smbfs -o nodatacache,nomdatacache,nobrowse,ro,nostreams //server/share $TEST_TMP/mnt"
  teardown
}

test_invalid_urls() {
  setup
  for _test_invalid_urls_case in "/" "//" "///" "smb:///" "server/" "smb://server/" "///share" "/share" "//server//share"; do
    run_capture "$REPO_DIR/macos/mount-smb.sh" "$_test_invalid_urls_case" "$TEST_TMP/mnt"
    assert_status "exits 1 on invalid url [$_test_invalid_urls_case]" 1 "$RUN_STATUS"
    assert_contains "reports invalid url for [$_test_invalid_urls_case]" "$RUN_STDOUT" "URL must include server and share"
  done
  teardown
}

test_normalize_url_leading_slashes() {
  setup
  for _test_normalize_url_leading_slashes_case in "/server/share" "///server/share" "smb:///server/share"; do
    : > "$MOUNT_LOG"
    run_capture "$REPO_DIR/macos/mount-smb.sh" "$_test_normalize_url_leading_slashes_case" "$TEST_TMP/mnt"
    assert_status "exits 0 normalizing [$_test_normalize_url_leading_slashes_case]" 0 "$RUN_STATUS"
    _test_normalize_url_leading_slashes_log=$(cat "$MOUNT_LOG" 2>/dev/null || true)
    assert_contains "normalizes leading slashes for [$_test_normalize_url_leading_slashes_case]" "$_test_normalize_url_leading_slashes_log" "//server/share $TEST_TMP/mnt"
  done
  teardown
}

test_url_with_domain_and_user_no_password() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" "smb://DOMAIN;user@server/share" "$TEST_TMP/mnt"
  assert_status "exits 0 with domain and user" 0 "$RUN_STATUS"

  _test_url_with_domain_and_user_no_password_mount_log=$(cat "$MOUNT_LOG" 2>/dev/null || true)
  assert_contains "mount preserves domain and user" "$_test_url_with_domain_and_user_no_password_mount_log" "//DOMAIN;user@server/share $TEST_TMP/mnt"
  teardown
}

test_url_with_password_is_rejected() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" "smb://user:pass@server/share" "$TEST_TMP/mnt"
  assert_status "exits 1 with password in URL" 1 "$RUN_STATUS"
  assert_contains "reports password rejected" "$RUN_STDOUT" "URL must not contain a password"

  run_capture "$REPO_DIR/macos/mount-smb.sh" "smb://DOMAIN;user:pass@server/share" "$TEST_TMP/mnt"
  assert_status "exits 1 with password and domain in URL" 1 "$RUN_STATUS"
  assert_contains "reports password rejected with domain" "$RUN_STDOUT" "URL must not contain a password"

  _test_url_with_password_is_rejected_mount_log=$(cat "$MOUNT_LOG" 2>/dev/null || true)
  assert_eq "mount never invoked with a password in the URL" "" "$_test_url_with_password_is_rejected_mount_log"
  teardown
}

test_mount_failure_is_fatal() {
  setup
  MOCK_MOUNT_EXIT=1
  run_capture "$REPO_DIR/macos/mount-smb.sh" "//server/share" "$TEST_TMP/mnt"
  assert_status "exits non-zero when mount fails" 1 "$RUN_STATUS"

  _test_mount_failure_is_fatal_mdutil_log=$(cat "$MDUTIL_LOG" 2>/dev/null || true)
  assert_not_contains "mdutil not executed after mount failure" "$_test_mount_failure_is_fatal_mdutil_log" "-i off"
  teardown
}

test_mount_failure_removes_created_mount_point() {
  setup
  MOCK_MOUNT_EXIT=1
  _test_mount_failure_removes_created_mount_point_dir="$TEST_TMP/new_mnt_dir"
  run_capture "$REPO_DIR/macos/mount-smb.sh" "//server/share" "$_test_mount_failure_removes_created_mount_point_dir"
  assert_status "exits non-zero when mount fails" 1 "$RUN_STATUS"
  if [ -d "$_test_mount_failure_removes_created_mount_point_dir" ]; then
    fail "removes mount point it created on mount failure" "directory still exists"
  else
    pass "removes mount point it created on mount failure"
  fi
  teardown
}

test_mount_failure_keeps_preexisting_mount_point() {
  setup
  MOCK_MOUNT_EXIT=1
  _test_mount_failure_keeps_preexisting_mount_point_dir="$TEST_TMP/preexisting_mnt_dir"
  mkdir -p "$_test_mount_failure_keeps_preexisting_mount_point_dir"
  run_capture "$REPO_DIR/macos/mount-smb.sh" "//server/share" "$_test_mount_failure_keeps_preexisting_mount_point_dir"
  assert_status "exits non-zero when mount fails" 1 "$RUN_STATUS"
  if [ -d "$_test_mount_failure_keeps_preexisting_mount_point_dir" ]; then
    pass "keeps pre-existing mount point on mount failure"
  else
    fail "keeps pre-existing mount point on mount failure" "directory was removed"
  fi
  teardown
}

test_spaces_in_arguments() {
  setup
  _test_spaces_in_arguments_dir="$TEST_TMP/mount dir"
  run_capture "$REPO_DIR/macos/mount-smb.sh" "//server/my share" "$_test_spaces_in_arguments_dir"
  assert_status "exits 0 with spaces in share and mount point" 0 "$RUN_STATUS"

  _test_spaces_in_arguments_mount_log=$(cat "$MOUNT_LOG" 2>/dev/null || true)
  assert_contains "mount preserves spaces in url and mount point" "$_test_spaces_in_arguments_mount_log" "//server/my share $_test_spaces_in_arguments_dir"
  teardown
}

test_root_user_rejected() {
  setup
  MOCK_ID_U=0
  run_capture "$REPO_DIR/macos/mount-smb.sh" "//server/share" "$TEST_TMP/mnt"
  assert_status "exits 1 when run as root" 1 "$RUN_STATUS"
  assert_contains "reports do not run as root" "$RUN_STDOUT" "do not run as root"
  _test_root_mount_log=$(cat "$MOUNT_LOG" 2>/dev/null || true)
  assert_eq "mount never invoked when run as root" "" "$_test_root_mount_log"
  teardown
}

test_user_writable_mount_point_never_calls_sudo() {
  setup
  run_capture "$REPO_DIR/macos/mount-smb.sh" "//server/share" "$TEST_TMP/mnt"
  assert_status "exits 0 mounting to user-writable path" 0 "$RUN_STATUS"
  _test_sudo_log=$(cat "$SUDO_LOG" 2>/dev/null || true)
  assert_eq "sudo never invoked for user-writable path" "" "$_test_sudo_log"
  teardown
}

test_restricted_parent_dir_prompts_sudo_and_chowns() {
  setup
  _test_restricted_vol="$TEST_TMP/mock_volumes"
  mkdir -p "$_test_restricted_vol"
  chmod 555 "$_test_restricted_vol"
  run_capture "$REPO_DIR/macos/mount-smb.sh" "//server/share" "$_test_restricted_vol/nas"
  assert_status "exits 0 mounting to restricted parent dir" 0 "$RUN_STATUS"
  _test_sudo_log=$(cat "$SUDO_LOG" 2>/dev/null || true)
  assert_contains "sudo -v authenticated" "$_test_sudo_log" "-v"
  assert_contains "sudo mkdir -p created mount point" "$_test_sudo_log" "mkdir -p $_test_restricted_vol/nas"
  assert_contains "sudo chown assigned ownership to user" "$_test_sudo_log" "chown 501:20 $_test_restricted_vol/nas"
  _test_mount_log=$(cat "$MOUNT_LOG" 2>/dev/null || true)
  assert_contains "mount invoked with correct mount point" "$_test_mount_log" "//server/share $_test_restricted_vol/nas"
  teardown
}

test_preexisting_dir_owned_by_root_chowns_to_user() {
  setup
  _test_root_mnt="$TEST_TMP/root_mnt"
  mkdir -p "$_test_root_mnt"
  MOCK_STAT_UID=0
  run_capture "$REPO_DIR/macos/mount-smb.sh" "//server/share" "$_test_root_mnt"
  assert_status "exits 0 mounting to root-owned dir" 0 "$RUN_STATUS"
  _test_sudo_log=$(cat "$SUDO_LOG" 2>/dev/null || true)
  assert_contains "sudo -v authenticated" "$_test_sudo_log" "-v"
  assert_contains "sudo chown assigned ownership to user" "$_test_sudo_log" "chown 501:20 $_test_root_mnt"
  assert_not_contains "sudo mkdir not called for pre-existing dir" "$_test_sudo_log" "mkdir"
  teardown
}

test_sudo_auth_failure_is_fatal() {
  setup
  _test_restricted_vol="$TEST_TMP/mock_volumes"
  mkdir -p "$_test_restricted_vol"
  chmod 555 "$_test_restricted_vol"
  MOCK_SUDO_V_EXIT=1
  run_capture "$REPO_DIR/macos/mount-smb.sh" "//server/share" "$_test_restricted_vol/nas"
  assert_status "exits 1 on sudo auth failure" 1 "$RUN_STATUS"
  assert_contains "reports sudo authentication failed" "$RUN_STDOUT" "sudo authentication failed"
  _test_mount_log=$(cat "$MOUNT_LOG" 2>/dev/null || true)
  assert_eq "mount never invoked when sudo fails" "" "$_test_mount_log"
  teardown
}

test_mount_failure_removes_sudo_created_mount_point() {
  setup
  _test_restricted_vol="$TEST_TMP/mock_volumes"
  mkdir -p "$_test_restricted_vol"
  chmod 555 "$_test_restricted_vol"
  MOCK_MOUNT_EXIT=1
  run_capture "$REPO_DIR/macos/mount-smb.sh" "//server/share" "$_test_restricted_vol/nas"
  assert_status "exits non-zero when mount fails" 1 "$RUN_STATUS"
  _test_sudo_log=$(cat "$SUDO_LOG" 2>/dev/null || true)
  assert_contains "sudo rmdir removes created mount point" "$_test_sudo_log" "rmdir $_test_restricted_vol/nas"
  if [ -d "$_test_restricted_vol/nas" ]; then
    fail "removes sudo-created mount point on mount failure" "directory still exists"
  else
    pass "removes sudo-created mount point on mount failure"
  fi
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
  test_root_user_rejected
  test_user_writable_mount_point_never_calls_sudo
  test_restricted_parent_dir_prompts_sudo_and_chowns
  test_preexisting_dir_owned_by_root_chowns_to_user
  test_sudo_auth_failure_is_fatal
  test_mount_failure_removes_sudo_created_mount_point
  test_missing_share_in_url
  test_successful_mount_default_opts
  test_normalize_url_slashes
  test_normalize_url_without_prefix
  test_extra_options
  test_creates_mount_directory
  test_mdutil_failure_is_nonfatal
  test_double_dash_delimiter
  test_option_missing_arg
  test_multiple_extra_options
  test_invalid_urls
  test_normalize_url_leading_slashes
  test_url_with_domain_and_user_no_password
  test_url_with_password_is_rejected
  test_mount_failure_is_fatal
  test_mount_failure_removes_created_mount_point
  test_mount_failure_keeps_preexisting_mount_point
  test_spaces_in_arguments
  test_summary
}

main "$@"
