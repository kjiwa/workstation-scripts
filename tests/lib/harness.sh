#!/bin/sh
# Minimal test harness for shell unit tests.
set -eu

TESTS_RUN=0
TESTS_FAILED=0

pass() {
  _pass_desc="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  printf "ok - %s\n" "$_pass_desc"
  return 0
}

fail() {
  _fail_desc="$1"
  _fail_reason="${2:-}"
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "not ok - %s\n" "$_fail_desc"
  [ -n "$_fail_reason" ] && printf "  # %s\n" "$_fail_reason"
  return 0
}

assert_eq() {
  _assert_eq_desc="$1"
  _assert_eq_expected="$2"
  _assert_eq_actual="$3"
  if [ "$_assert_eq_expected" = "$_assert_eq_actual" ]; then
    pass "$_assert_eq_desc"
  else
    fail "$_assert_eq_desc" "expected [$_assert_eq_expected] got [$_assert_eq_actual]"
  fi
}

assert_contains() {
  _assert_contains_desc="$1"
  _assert_contains_haystack="$2"
  _assert_contains_needle="$3"
  case "$_assert_contains_haystack" in
    *"$_assert_contains_needle"*) pass "$_assert_contains_desc" ;;
    *) fail "$_assert_contains_desc" "expected to find [$_assert_contains_needle] in [$_assert_contains_haystack]" ;;
  esac
}

assert_not_contains() {
  _assert_not_contains_desc="$1"
  _assert_not_contains_haystack="$2"
  _assert_not_contains_needle="$3"
  case "$_assert_not_contains_haystack" in
    *"$_assert_not_contains_needle"*) fail "$_assert_not_contains_desc" "did not expect to find [$_assert_not_contains_needle] in [$_assert_not_contains_haystack]" ;;
    *) pass "$_assert_not_contains_desc" ;;
  esac
}

assert_status() {
  _assert_status_desc="$1"
  _assert_status_expected="$2"
  _assert_status_actual="$3"
  assert_eq "$_assert_status_desc" "$_assert_status_expected" "$_assert_status_actual"
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
