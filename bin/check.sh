#!/bin/sh
# Repository consistency and validation check.
set -eu

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPO_DIR

_check_shell() {
  _check_shell_file="$1"
  case "$_check_shell_file" in
    */lib/*) ;;
    *)
      if [ ! -x "$_check_shell_file" ]; then
        printf 'Script is not executable: %s\n' "$_check_shell_file" >&2
        exit 1
      fi
      ;;
  esac
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -s sh -x -P SCRIPTDIR "$_check_shell_file"
  else
    sh -n "$_check_shell_file"
  fi
}

_check_markdown() {
  _check_md_file="$1"
  if [ -n "$(tail -c 1 "$_check_md_file")" ]; then
    printf 'Missing trailing newline: %s\n' "$_check_md_file" >&2
    exit 1
  fi
}

main() {
  find "$REPO_DIR" -name "*.sh" -not -path '*/.*' | while IFS= read -r _main_script; do
    _check_shell "$_main_script"
  done

  find "$REPO_DIR" -name "*.md" -not -path '*/.*' | while IFS= read -r _main_doc; do
    _check_markdown "$_main_doc"
  done

  "$REPO_DIR/tests/run.sh"
}

main "$@"
