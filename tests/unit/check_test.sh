#!/bin/sh
# Hermetic unit tests for bin/check.sh's shellcheck-missing fallback.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=../lib/harness.sh
. "$SCRIPT_DIR/../lib/harness.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly REPO_DIR

# Runs a copy of bin/check.sh against a scratch repo so the recursive
# `tests/run.sh` step in check.sh's own main() does not re-invoke this suite.
_create_scratch_repo() {
  _create_scratch_repo_dir="$1"
  mkdir -p "$_create_scratch_repo_dir/bin" "$_create_scratch_repo_dir/tests"
  cp "$REPO_DIR/bin/check.sh" "$_create_scratch_repo_dir/bin/check.sh"
  chmod +x "$_create_scratch_repo_dir/bin/check.sh"

  cat <<'EOF' >"$_create_scratch_repo_dir/tests/run.sh"
#!/bin/sh
exit 0
EOF
  chmod +x "$_create_scratch_repo_dir/tests/run.sh"

  cat <<'EOF' >"$_create_scratch_repo_dir/bin/sample.sh"
#!/bin/sh
exit 0
EOF
  chmod +x "$_create_scratch_repo_dir/bin/sample.sh"
}

setup() {
  TEST_TMP="$(mktemp -d)"
  export TEST_TMP
  _create_scratch_repo "$TEST_TMP/repo"

  OLD_PATH="$PATH"
  export OLD_PATH
}

teardown() {
  export PATH="$OLD_PATH"
  rm -rf "$TEST_TMP"
}

test_warns_when_shellcheck_missing() {
  setup
  run_capture env PATH=/usr/bin:/bin "$TEST_TMP/repo/bin/check.sh"
  assert_status "still exits 0 when shellcheck is missing" 0 "$RUN_STATUS"
  assert_contains "warns that shellcheck is missing" "$RUN_STDOUT" "shellcheck not found"
  teardown
}

test_no_warning_when_shellcheck_present() {
  setup
  if command -v shellcheck >/dev/null 2>&1; then
    run_capture "$TEST_TMP/repo/bin/check.sh"
    assert_status "exits 0 when shellcheck is present" 0 "$RUN_STATUS"
    assert_not_contains "does not warn when shellcheck is present" "$RUN_STDOUT" "shellcheck not found"
  fi
  teardown
}

main() {
  test_warns_when_shellcheck_missing
  test_no_warning_when_shellcheck_present
  test_summary
}

main "$@"
