#!/bin/sh
# Hermetic unit tests for macos/prune-caches.sh using mock binaries and temp trees.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=../lib/harness.sh
. "$SCRIPT_DIR/../lib/harness.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly REPO_DIR
readonly OLD_STAMP="202001010000"

_create_mock_uname() {
  _create_mock_uname_dir="$1"
  cat <<'MOCK' >"$_create_mock_uname_dir/uname"
#!/bin/sh
set -eu
if [ "${1:-}" = "-s" ]; then
  echo "${UNAME_OS:-Darwin}"
  exit 0
fi
exec /usr/bin/uname "$@"
MOCK
  chmod +x "$_create_mock_uname_dir/uname"
}

_create_mock_tool() {
  _create_mock_tool_dir="$1"
  _create_mock_tool_name="$2"
  cat <<'MOCK' >"$_create_mock_tool_dir/$_create_mock_tool_name"
#!/bin/sh
set -eu
printf '%s %s\n' "$(basename "$0")" "$*" >> "$TOOL_LOG"
if [ "$(basename "$0")" = "docker" ] && [ "${1:-}" = "info" ]; then
  exit "${MOCK_DOCKER_INFO_EXIT:-0}"
fi
exit 0
MOCK
  chmod +x "$_create_mock_tool_dir/$_create_mock_tool_name"
}

_age() {
  find "$1" -exec touch -h -t "$OLD_STAMP" {} +
}

_make_provider() {
  mkdir -p "$TF_PLUGIN_CACHE_DIR/registry.terraform.io/$1/$2/$3/darwin_arm64"
  : > "$TF_PLUGIN_CACHE_DIR/registry.terraform.io/$1/$2/$3/darwin_arm64/terraform-provider-$2"
}

_make_lock() {
  mkdir -p "$PRUNE_SRC_DIRS/$1"
  cat <<LOCK >"$PRUNE_SRC_DIRS/$1/.terraform.lock.hcl"
provider "registry.terraform.io/$2/$3" {
  version     = "$4"
  constraints = "$4"
  hashes = [
    "h1:abc",
  ]
}
LOCK
}

setup() {
  TEST_TMP="$(mktemp -d)"
  export TEST_TMP
  export TOOL_LOG="$TEST_TMP/tool.log"
  export UNAME_OS="Darwin"
  export MOCK_DOCKER_INFO_EXIT=0
  export HOME="$TEST_TMP/home"
  export TF_PLUGIN_CACHE_DIR="$TEST_TMP/plugin-cache"
  export PRUNE_SRC_DIRS="$TEST_TMP/src"
  export PRUNE_CLAUDE_TMP_DIR="$TEST_TMP/claude"
  mkdir -p "$HOME" "$TF_PLUGIN_CACHE_DIR" "$PRUNE_SRC_DIRS" "$PRUNE_CLAUDE_TMP_DIR" "$TEST_TMP/bin"
  : > "$TOOL_LOG"

  _create_mock_uname "$TEST_TMP/bin"
  for _setup_tool in brew uv npm docker; do
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

_exists() {
  if [ -e "$1" ] || [ -L "$1" ]; then echo yes; else echo no; fi
}

test_help_and_invalid_option() {
  setup
  run_capture "$REPO_DIR/macos/prune-caches.sh" --help
  assert_status "exits 0 on --help" 0 "$RUN_STATUS"
  assert_contains "shows usage" "$RUN_STDOUT" "Usage: prune-caches.sh"
  assert_contains "documents dry-run" "$RUN_STDOUT" "--dry-run"
  run_capture "$REPO_DIR/macos/prune-caches.sh" -x
  assert_status "exits 1 on invalid option" 1 "$RUN_STATUS"
  assert_contains "shows usage on invalid option" "$RUN_STDOUT" "Usage: prune-caches.sh"
  teardown
}

test_non_darwin_os() {
  setup
  UNAME_OS="Linux"
  run_capture "$REPO_DIR/macos/prune-caches.sh"
  assert_status "exits 1 on non-Darwin OS" 1 "$RUN_STATUS"
  assert_contains "reports macOS required" "$RUN_STDOUT" "macOS (Darwin) required"
  teardown
}

test_runs_tool_prunes() {
  setup
  run_capture "$REPO_DIR/macos/prune-caches.sh"
  assert_status "exits 0" 0 "$RUN_STATUS"
  _test_log="$(cat "$TOOL_LOG")"
  assert_contains "runs brew cleanup" "$_test_log" "brew cleanup"
  assert_contains "runs uv cache prune" "$_test_log" "uv cache prune"
  assert_contains "runs npm cache verify" "$_test_log" "npm cache verify"
  assert_contains "runs docker image prune" "$_test_log" "docker image prune -f"
  assert_contains "runs docker builder prune" "$_test_log" "docker builder prune -f"
  teardown
}

test_docker_daemon_unreachable_is_skipped() {
  setup
  MOCK_DOCKER_INFO_EXIT=1
  run_capture "$REPO_DIR/macos/prune-caches.sh"
  assert_status "exits 0" 0 "$RUN_STATUS"
  assert_contains "reports daemon unreachable" "$RUN_STDOUT" "daemon unreachable"
  assert_not_contains "does not prune images" "$(cat "$TOOL_LOG")" "docker image prune"
  teardown
}

test_missing_tools_are_skipped() {
  setup
  rm -f "$TEST_TMP/bin/brew" "$TEST_TMP/bin/uv" "$TEST_TMP/bin/npm" "$TEST_TMP/bin/docker"
  PATH="$TEST_TMP/bin:/usr/bin:/bin"
  run_capture "$REPO_DIR/macos/prune-caches.sh"
  assert_status "exits 0 with tools missing" 0 "$RUN_STATUS"
  assert_contains "reports brew missing" "$RUN_STDOUT" "skipping brew: not found"
  assert_contains "reports uv missing" "$RUN_STDOUT" "skipping uv: not found"
  assert_contains "reports npm missing" "$RUN_STDOUT" "skipping npm: not found"
  assert_contains "reports docker missing" "$RUN_STDOUT" "skipping docker: not found"
  teardown
}

test_terraform_prunes_unpinned_and_symlinks() {
  setup
  _make_provider hashicorp aws 6.72.0
  _make_provider hashicorp aws 6.60.0
  _make_provider hashicorp google 1.0.0
  _make_provider hashicorp random 3.0.0
  _make_lock repo-a hashicorp aws 6.72.0
  _make_lock repo-b hashicorp random 3.0.0
  mkdir -p "$TEST_TMP/target"
  mkdir -p "$TF_PLUGIN_CACHE_DIR/registry.terraform.io/hashicorp/aws/6.99.0"
  ln -s "$TEST_TMP/target" "$TF_PLUGIN_CACHE_DIR/registry.terraform.io/hashicorp/aws/6.99.0/darwin_arm64"
  ln -s "$TEST_TMP/target" "$TF_PLUGIN_CACHE_DIR/registry.terraform.io/hashicorp/aws/6.98.0"

  run_capture "$REPO_DIR/macos/prune-caches.sh"
  assert_status "exits 0" 0 "$RUN_STATUS"
  _test_aws="$TF_PLUGIN_CACHE_DIR/registry.terraform.io/hashicorp/aws"
  assert_eq "keeps pinned aws version" yes "$(_exists "$_test_aws/6.72.0")"
  assert_eq "keeps version pinned by another repo" yes "$(_exists "$TF_PLUGIN_CACHE_DIR/registry.terraform.io/hashicorp/random/3.0.0")"
  assert_eq "removes unpinned aws version" no "$(_exists "$_test_aws/6.60.0")"
  assert_eq "removes unpinned provider version" no "$(_exists "$TF_PLUGIN_CACHE_DIR/registry.terraform.io/hashicorp/google/1.0.0")"
  assert_eq "removes empty provider dir" no "$(_exists "$TF_PLUGIN_CACHE_DIR/registry.terraform.io/hashicorp/google")"
  assert_eq "removes top-level symlink entry" no "$(_exists "$_test_aws/6.98.0")"
  assert_eq "removes nested symlink entry" no "$(_exists "$_test_aws/6.99.0/darwin_arm64")"
  assert_eq "does not follow symlinks" yes "$(_exists "$TEST_TMP/target")"
  teardown
}

test_terraform_skipped_when_source_dir_missing() {
  setup
  _make_provider hashicorp aws 6.60.0
  PRUNE_SRC_DIRS="$TEST_TMP/nonexistent"
  run_capture "$REPO_DIR/macos/prune-caches.sh"
  assert_status "exits 0" 0 "$RUN_STATUS"
  assert_contains "reports missing source dir" "$RUN_STDOUT" "source directory not found"
  assert_eq "keeps everything" yes "$(_exists "$TF_PLUGIN_CACHE_DIR/registry.terraform.io/hashicorp/aws/6.60.0")"
  teardown
}

test_claude_tmp_prune() {
  setup
  _test_root="$PRUNE_CLAUDE_TMP_DIR"
  mkdir -p "$_test_root/-proj/stale/sub" "$_test_root/-proj/recent-deep/a/b" "$_test_root/-gone/stale"
  : > "$_test_root/-proj/stale/sub/f"
  : > "$_test_root/-proj/recent-deep/a/b/old"
  : > "$_test_root/-gone/stale/f"
  : > "$_test_root/loose-old"
  : > "$_test_root/loose-new"
  mkdir -p "$_test_root/loosedir-old" "$_test_root/bash-edit-diff" "$_test_root/plugin-tool-staging"
  : > "$_test_root/loosedir-old/f"
  : > "$_test_root/bash-edit-diff/f"
  : > "$_test_root/plugin-tool-staging/f"
  mkdir -p "$TEST_TMP/outside"
  : > "$TEST_TMP/outside/new"
  ln -s "$TEST_TMP/outside" "$_test_root/-proj/stale/link"
  _age "$_test_root/-proj/stale"
  _age "$_test_root/-gone"
  _age "$_test_root/loose-old"
  _age "$_test_root/loosedir-old"
  _age "$_test_root/bash-edit-diff"
  _age "$_test_root/plugin-tool-staging"
  _age "$_test_root/-proj/recent-deep"
  : > "$_test_root/-proj/recent-deep/a/b/new"

  run_capture "$REPO_DIR/macos/prune-caches.sh"
  assert_status "exits 0" 0 "$RUN_STATUS"
  assert_eq "removes stale session" no "$(_exists "$_test_root/-proj/stale")"
  assert_eq "keeps session with recent deep file" yes "$(_exists "$_test_root/-proj/recent-deep/a/b/new")"
  assert_eq "removes empty project dir" no "$(_exists "$_test_root/-gone")"
  assert_eq "keeps project dir with live sessions" yes "$(_exists "$_test_root/-proj")"
  assert_eq "removes stale loose file" no "$(_exists "$_test_root/loose-old")"
  assert_eq "keeps recent loose file" yes "$(_exists "$_test_root/loose-new")"
  assert_eq "removes stale loose dir" no "$(_exists "$_test_root/loosedir-old")"
  assert_eq "keeps bash-edit-diff" yes "$(_exists "$_test_root/bash-edit-diff/f")"
  assert_eq "keeps plugin-tool-staging" yes "$(_exists "$_test_root/plugin-tool-staging/f")"
  assert_eq "does not follow symlinks" yes "$(_exists "$TEST_TMP/outside/new")"
  teardown
}

test_dry_run_changes_nothing() {
  setup
  _make_provider hashicorp aws 6.60.0
  _make_lock repo-a hashicorp aws 6.72.0
  ln -s "$TEST_TMP" "$TF_PLUGIN_CACHE_DIR/registry.terraform.io/hashicorp/aws/6.98.0"
  mkdir -p "$PRUNE_CLAUDE_TMP_DIR/-proj/stale"
  : > "$PRUNE_CLAUDE_TMP_DIR/-proj/stale/f"
  : > "$PRUNE_CLAUDE_TMP_DIR/loose-old"
  _age "$PRUNE_CLAUDE_TMP_DIR/-proj/stale"
  _age "$PRUNE_CLAUDE_TMP_DIR/loose-old"
  _test_before="$(find "$TF_PLUGIN_CACHE_DIR" "$PRUNE_CLAUDE_TMP_DIR" | sort)"

  run_capture "$REPO_DIR/macos/prune-caches.sh" --dry-run
  assert_status "exits 0" 0 "$RUN_STATUS"
  assert_contains "reports unpinned version" "$RUN_STDOUT" "would remove $TF_PLUGIN_CACHE_DIR/registry.terraform.io/hashicorp/aws/6.60.0"
  assert_contains "reports symlink" "$RUN_STDOUT" "would remove $TF_PLUGIN_CACHE_DIR/registry.terraform.io/hashicorp/aws/6.98.0"
  assert_contains "reports stale session" "$RUN_STDOUT" "would remove $PRUNE_CLAUDE_TMP_DIR/-proj/stale"
  assert_contains "reports stale loose file" "$RUN_STDOUT" "would remove $PRUNE_CLAUDE_TMP_DIR/loose-old"
  assert_contains "reports tool commands" "$RUN_STDOUT" "would run brew cleanup"
  assert_eq "tree unchanged" "$_test_before" "$(find "$TF_PLUGIN_CACHE_DIR" "$PRUNE_CLAUDE_TMP_DIR" | sort)"
  assert_eq "runs only the read-only docker probe" "docker info" "$(cat "$TOOL_LOG")"
  teardown
}

main() {
  test_help_and_invalid_option
  test_non_darwin_os
  test_runs_tool_prunes
  test_docker_daemon_unreachable_is_skipped
  test_missing_tools_are_skipped
  test_terraform_prunes_unpinned_and_symlinks
  test_terraform_skipped_when_source_dir_missing
  test_claude_tmp_prune
  test_dry_run_changes_nothing
  test_summary
}

main "$@"
