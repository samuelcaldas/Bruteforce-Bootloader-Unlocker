#!/usr/bin/env bash
# ==============================================================================
# test_unlock_runner.sh - Unit tests for unlock_runner.sh
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_helper.sh"

function test_percentage_formatting {
  source "${LIB_DIR}/unlock_runner.sh"

  assert_eq "0.000" "$(format_percentage_string 0 100)" "0 / 100 is 0.000%"
  assert_eq "1.000" "$(format_percentage_string 1 100)" "1 / 100 is 1.000%"
  assert_eq "33.333" "$(format_percentage_string 1 3)" "1 / 3 is 33.333%"
  assert_eq "100.000" "$(format_percentage_string 100 100)" "100 / 100 is 100.000%"
  assert_eq "n/a" "$(format_percentage_string 50 "huge")" "huge space returns n/a"
  assert_eq "n/a" "$(format_percentage_string 50 0)" "0 total returns n/a"
}

function test_time_estimate_formatting {
  source "${LIB_DIR}/unlock_runner.sh"

  # Rate = 0 or invalid inputs -> calculating
  assert_eq "calculating" "$(format_time_estimate 0 1000 10)" "Zero current -> calculating"
  assert_eq "calculating" "$(format_time_estimate 50 1000 0)" "Zero elapsed -> calculating"
  assert_eq "calculating" "$(format_time_estimate 50 "huge" 10)" "Huge total -> calculating"

  # Completed work -> 0s
  assert_eq "0s" "$(format_time_estimate 1000 1000 10)" "Completed work -> 0s"

  # Rate = 10/s, remaining 50 -> 5s
  assert_eq "5s" "$(format_time_estimate 100 150 10)" "Remaining 5s"

  # Rate = 1/s, remaining 125s -> 2m 5s
  assert_eq "2m 5s" "$(format_time_estimate 10 135 10)" "Remaining 2m 5s"

  # Rate = 1/s, remaining 3665s -> 1h 1m 5s
  assert_eq "1h 1m 5s" "$(format_time_estimate 10 3675 10)" "Remaining 1h 1m 5s"

  # Rate = 1/s, remaining 90000s -> 1d 1h 0m
  assert_eq "1d 1h 0m" "$(format_time_estimate 10 90010 10)" "Remaining 1d 1h 0m"
}

function test_authorization_guard {
  source "${LIB_DIR}/constants.sh"
  source "${LIB_DIR}/terminal_ui.sh"
  source "${LIB_DIR}/unlock_runner.sh"
  function terminal_stdout_is_tty { return 1; }
  init_terminal_styles

  # Case 1: Exact 'AUTHORIZED' provided
  run_capture_with_stdin "AUTHORIZED" prompt_authorization_guard
  assert_eq 0 "${CAPTURE_STATUS}" "Exact AUTHORIZED succeeds"
  assert_contains "${CAPTURE_OUTPUT}" "[RULE] authorized use confirmation" "Renders rule header"

  # Case 2: Wrong input provided
  run_capture_with_stdin "NO" prompt_authorization_guard
  assert_not_eq 0 "${CAPTURE_STATUS}" "Wrong input fails"
  assert_contains "${CAPTURE_OUTPUT}" "Aborting" "Rejection notice printed"

  # Case 3: Empty input
  run_capture_with_stdin "" prompt_authorization_guard
  assert_not_eq 0 "${CAPTURE_STATUS}" "Empty input fails"
}

function test_cursor_advancement {
  source "${LIB_DIR}/constants.sh"
  source "${LIB_DIR}/pattern_engine.sh"
  source "${LIB_DIR}/unlock_runner.sh"
  CONFIG_PATTERNS='first:9{2}:1;second:A:1'
  CONFIG_ACTIVE_CHARSET=$CHARSET_DIGITS CONFIG_STRATEGY=smart
  STATE_GLOBAL_CURSOR=10
  engine_compile
  engine_seek 10
  E_SLOT=1 E_QUOTA=1 CURRENT_PATTERN_INDEX=1
  advance_runtime_cursor
  engine_serialize
  assert_eq 11 "$STATE_GLOBAL_CURSOR" 'Global cursor incremented'
  assert_eq '10,11' "$STATE_PATTERN_OFFSETS" 'Selected position vector advanced'
}

function test_fetch_next_candidate {
  source "${LIB_DIR}/constants.sh"
  source "${LIB_DIR}/pattern_engine.sh"
  source "${LIB_DIR}/device_storage.sh"
  source "${LIB_DIR}/unlock_runner.sh"

  CONFIG_PATTERNS="pin6:9{6}:10:PIN 6"
  CONFIG_ACTIVE_CHARSET="${CHARSET_DIGITS}"
  CONFIG_STRATEGY="sequential"
  CONFIG_KNOWN_POSITIONS=""
  STATE_GLOBAL_CURSOR=0
  STATE_PATTERN_OFFSETS="0"

  fetch_next_candidate_code
  assert_eq "000000" "${CURRENT_CANDIDATE_CODE}" "First candidate is 000000"

  advance_runtime_cursor
  fetch_next_candidate_code
  assert_eq "000001" "${CURRENT_CANDIDATE_CODE}" "Second candidate is 000001"
}

run_test "Runner percentage formatting" test_percentage_formatting
run_test "Runner time estimate calculation" test_time_estimate_formatting
run_test "Runner authorization guard verification" test_authorization_guard
run_test "Runner cursor advancement" test_cursor_advancement
run_test "Runner candidate code generation" test_fetch_next_candidate

finish_tests
