#!/bin/sh
# Repository consistency and validation check.
set -eu

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPO_DIR

_check_executable() {
  _check_executable_file="$1"
  case "$_check_executable_file" in
    */lib/*) ;;
    *)
      if [ ! -x "$_check_executable_file" ]; then
        printf 'Script is not executable: %s\n' "$_check_executable_file" >&2
        exit 1
      fi
      ;;
  esac
}

_lint_shell_file() {
  _lint_shell_file_path="$1"
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -s sh -x -P SCRIPTDIR "$_lint_shell_file_path"
  else
    sh -n "$_lint_shell_file_path"
  fi
}

_check_shell_script() {
  _check_shell_script_file="$1"
  _check_executable "$_check_shell_script_file"
  _lint_shell_file "$_check_shell_script_file"
}

_check_markdown_file() {
  _check_markdown_file_path="$1"
  if [ -n "$(tail -c 1 "$_check_markdown_file_path")" ]; then
    printf 'Missing trailing newline: %s\n' "$_check_markdown_file_path" >&2
    exit 1
  fi
}

_check_all_shell_scripts() {
  _check_all_shell_scripts_root="$1"
  find "$_check_all_shell_scripts_root" -name "*.sh" -not -path '*/.*' | while IFS= read -r _check_all_shell_scripts_file; do
    _check_shell_script "$_check_all_shell_scripts_file"
  done
}

_check_all_markdown_files() {
  _check_all_markdown_files_root="$1"
  find "$_check_all_markdown_files_root" -name "*.md" -not -path '*/.*' | while IFS= read -r _check_all_markdown_files_file; do
    _check_markdown_file "$_check_all_markdown_files_file"
  done
}

_run_test_suites() {
  _run_test_suites_root="$1"
  "$_run_test_suites_root/tests/run.sh"
}

main() {
  _check_all_shell_scripts "$REPO_DIR"
  _check_all_markdown_files "$REPO_DIR"
  _run_test_suites "$REPO_DIR"
}

main "$@"
