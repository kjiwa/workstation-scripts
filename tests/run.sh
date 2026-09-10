#!/bin/sh
# Runs all unit test suites for workstation-scripts.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR

SUITES_RUN=0
SUITES_FAILED=0

_record_result() {
  _record_result_label="$1"
  _record_result_status="$2"
  SUITES_RUN=$((SUITES_RUN + 1))
  if [ "$_record_result_status" -ne 0 ]; then
    SUITES_FAILED=$((SUITES_FAILED + 1))
    printf 'FAILED: %s\n' "$_record_result_label"
  fi
}

_run_suite() {
  _run_suite_script="$1"
  _run_suite_name="$(basename "$_run_suite_script")"
  printf '\n== %s ==\n' "$_run_suite_name"
  set +e
  "$_run_suite_script"
  _run_suite_status=$?
  set -e
  _record_result "$_run_suite_name" "$_run_suite_status"
}

_run_unit_suites() {
  _run_unit_suites_dir="$1"
  for _run_unit_suites_file in "$_run_unit_suites_dir"/*.sh; do
    [ -f "$_run_unit_suites_file" ] || continue
    _run_suite "$_run_unit_suites_file"
  done
}

_report_summary() {
  printf '\n===================================\n'
  printf '%d suite(s) run, %d failed\n' "$SUITES_RUN" "$SUITES_FAILED"
  [ "$SUITES_RUN" -gt 0 ] && [ "$SUITES_FAILED" -eq 0 ]
}

main() {
  _run_unit_suites "$SCRIPT_DIR/unit"
  _report_summary
}

main "$@"
