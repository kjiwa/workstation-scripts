#!/bin/sh
# Minimal test harness for shell unit tests.
set -eu

TESTS_RUN=0
TESTS_FAILED=0

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  printf "ok - %s\n" "$1"
  return 0
}

fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "not ok - %s\n" "$1"
  [ -n "${2:-}" ] && printf "  # %s\n" "$2"
  return 0
}

assert_eq() {
  _aeq_desc="$1"
  _aeq_expected="$2"
  _aeq_actual="$3"
  if [ "$_aeq_expected" = "$_aeq_actual" ]; then
    pass "$_aeq_desc"
  else
    fail "$_aeq_desc" "expected [$_aeq_expected] got [$_aeq_actual]"
  fi
}

assert_contains() {
  _ac_desc="$1"
  _ac_haystack="$2"
  _ac_needle="$3"
  case "$_ac_haystack" in
    *"$_ac_needle"*) pass "$_ac_desc" ;;
    *) fail "$_ac_desc" "expected to find [$_ac_needle] in [$_ac_haystack]" ;;
  esac
}

assert_not_contains() {
  _anc_desc="$1"
  _anc_haystack="$2"
  _anc_needle="$3"
  case "$_anc_haystack" in
    *"$_anc_needle"*) fail "$_anc_desc" "did not expect to find [$_anc_needle] in [$_anc_haystack]" ;;
    *) pass "$_anc_desc" ;;
  esac
}

assert_status() {
  _as_desc="$1"
  _as_expected="$2"
  _as_actual="$3"
  assert_eq "$_as_desc" "$_as_expected" "$_as_actual"
}

run_capture() {
  # shellcheck disable=SC2034
  if RUN_STDOUT=$("$@" 2>&1); then
    RUN_STATUS=0
  else
    RUN_STATUS=$?
  fi
}

test_summary() {
  printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ]
}
