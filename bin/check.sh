#!/bin/sh
# Repository consistency and validation check.
set -eu

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPO_DIR

_check_executables() {
  _check_executables_dir="$1"
  find "$_check_executables_dir" -name "*.sh" -not -path '*/.*' -not -path '*/lib/*' | while IFS= read -r _check_executables_file; do
    if [ ! -x "$_check_executables_file" ]; then
      printf 'Script is not executable: %s\n' "$_check_executables_file" >&2
      exit 1
    fi
  done
}

_lint_scripts() {
  _lint_scripts_dir="$1"
  if command -v shellcheck >/dev/null 2>&1; then
    find "$_lint_scripts_dir" -name "*.sh" -not -path '*/.*' -exec shellcheck -s sh -x -P SCRIPTDIR {} +
  else
    printf 'warning: shellcheck not found; falling back to sh -n (syntax only, no lint checks)\n' >&2
    find "$_lint_scripts_dir" -name "*.sh" -not -path '*/.*' -exec sh -n {} +
  fi
}

_check_markdown() {
  _check_markdown_dir="$1"
  find "$_check_markdown_dir" -name "*.md" -not -path '*/.*' | while IFS= read -r _check_markdown_file; do
    if [ -n "$(tail -c 1 "$_check_markdown_file")" ]; then
      printf 'Missing trailing newline: %s\n' "$_check_markdown_file" >&2
      exit 1
    fi
  done
}

_run_tests() {
  _run_tests_dir="$1"
  "$_run_tests_dir/tests/run.sh"
}

main() {
  _check_executables "$REPO_DIR"
  _lint_scripts "$REPO_DIR"
  _check_markdown "$REPO_DIR"
  _run_tests "$REPO_DIR"
}

main "$@"
