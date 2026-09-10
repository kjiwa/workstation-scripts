#!/bin/sh
# Runs shellcheck and all unit tests for workstation-scripts.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPO_DIR

SUITES_RUN=0
SUITES_FAILED=0

section() {
  printf '\n== %s ==\n' "$1"
}

record_result() {
  _record_label="$1"
  _record_status="$2"
  SUITES_RUN=$((SUITES_RUN + 1))
  if [ "$_record_status" -ne 0 ]; then
    SUITES_FAILED=$((SUITES_FAILED + 1))
    printf 'FAILED: %s\n' "$_record_label"
  fi
}

run_script_suite() {
  _run_script="$1"
  section "$(basename "$_run_script")"
  set +e
  "$_run_script"
  _run_status=$?
  set -e
  record_result "$(basename "$_run_script")" "$_run_status"
}

run_shellcheck() {
  section "shellcheck"
  if command -v shellcheck >/dev/null 2>&1; then
    set +e
    shellcheck -s sh -x -P SCRIPTDIR \
      "$REPO_DIR"/bin/*.sh \
      "$REPO_DIR"/macos/*.sh \
      "$SCRIPT_DIR"/*.sh \
      "$SCRIPT_DIR"/lib/*.sh \
      "$SCRIPT_DIR"/unit/*.sh
    _sc_status=$?
    set -e
    record_result "shellcheck" "$_sc_status"
  else
    echo "shellcheck not found on PATH; falling back to sh -n"
    _syntax_status=0
    for _f in "$REPO_DIR"/bin/*.sh "$REPO_DIR"/macos/*.sh "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/lib/*.sh "$SCRIPT_DIR"/unit/*.sh; do
      [ -f "$_f" ] || continue
      sh -n "$_f" || _syntax_status=1
    done
    record_result "sh -n" "$_syntax_status"
  fi
}

main() {
  run_shellcheck

  for _main_unit in "$SCRIPT_DIR"/unit/*.sh; do
    [ -f "$_main_unit" ] || continue
    run_script_suite "$_main_unit"
  done

  printf '\n===================================\n'
  printf '%d suite(s) run, %d failed\n' "$SUITES_RUN" "$SUITES_FAILED"

  [ "$SUITES_FAILED" -eq 0 ]
}

main "$@"
