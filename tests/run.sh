#!/bin/sh
# Runs shellcheck and all unit tests for workstation-scripts.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPO_DIR

SUITES_RUN=0
SUITES_FAILED=0

_print_section() {
  _print_section_title="$1"
  printf '\n== %s ==\n' "$_print_section_title"
}

_record_result() {
  _record_result_label="$1"
  _record_result_status="$2"
  SUITES_RUN=$((SUITES_RUN + 1))
  if [ "$_record_result_status" -ne 0 ]; then
    SUITES_FAILED=$((SUITES_FAILED + 1))
    printf 'FAILED: %s\n' "$_record_result_label"
  fi
}

_run_shellcheck() {
  set +e
  shellcheck -s sh -x -P SCRIPTDIR \
    "$REPO_DIR"/bin/*.sh \
    "$REPO_DIR"/macos/*.sh \
    "$SCRIPT_DIR"/*.sh \
    "$SCRIPT_DIR"/lib/*.sh \
    "$SCRIPT_DIR"/unit/*.sh
  _run_shellcheck_status=$?
  set -e
  _record_result "shellcheck" "$_run_shellcheck_status"
}

_run_syntax_check() {
  echo "shellcheck not found on PATH; falling back to sh -n"
  _run_syntax_check_status=0
  for _run_syntax_check_file in "$REPO_DIR"/bin/*.sh "$REPO_DIR"/macos/*.sh "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/lib/*.sh "$SCRIPT_DIR"/unit/*.sh; do
    [ -f "$_run_syntax_check_file" ] || continue
    sh -n "$_run_syntax_check_file" || _run_syntax_check_status=1
  done
  _record_result "sh -n" "$_run_syntax_check_status"
}

_check_shell_syntax() {
  _print_section "shellcheck"
  if command -v shellcheck >/dev/null 2>&1; then
    _run_shellcheck
  else
    _run_syntax_check
  fi
}

_run_script_suite() {
  _run_script_suite_script="$1"
  _print_section "$(basename "$_run_script_suite_script")"
  set +e
  "$_run_script_suite_script"
  _run_script_suite_status=$?
  set -e
  _record_result "$(basename "$_run_script_suite_script")" "$_run_script_suite_status"
}

_run_unit_suites() {
  _run_unit_suites_dir="$1"
  for _run_unit_suites_file in "$_run_unit_suites_dir"/*.sh; do
    [ -f "$_run_unit_suites_file" ] || continue
    _run_script_suite "$_run_unit_suites_file"
  done
}

_report_summary() {
  printf '\n===================================\n'
  printf '%d suite(s) run, %d failed\n' "$SUITES_RUN" "$SUITES_FAILED"
  [ "$SUITES_FAILED" -eq 0 ]
}

main() {
  _check_shell_syntax
  _run_unit_suites "$SCRIPT_DIR/unit"
  _report_summary
}

main "$@"
