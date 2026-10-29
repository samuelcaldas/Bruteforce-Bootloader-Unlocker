#!/usr/bin/env bash
# ==============================================================================
# test_constants.sh - Unit tests for constants.sh
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_helper.sh"

function test_exit_codes {
  source "${LIB_DIR}/constants.sh"
  assert_eq 0 "${EXIT_SUCCESS}" "EXIT_SUCCESS must be 0"
  assert_eq 1 "${EXIT_GENERAL_ERROR}" "EXIT_GENERAL_ERROR must be 1"
  assert_eq 2 "${EXIT_TERMINAL_FASTBOOT_ERROR}" "EXIT_TERMINAL_FASTBOOT_ERROR must be 2"
  assert_eq 130 "${EXIT_INTERRUPTED}" "EXIT_INTERRUPTED must be 130"
}

function test_defaults_and_boundaries {
  source "${LIB_DIR}/constants.sh"
  assert_eq 9223372036854775807 "${MAX_INTEGER_VALUE}" "MAX_INTEGER_VALUE must be signed 64-bit max"
  assert_eq 20 "${DEFAULT_CODE_LENGTH}" "DEFAULT_CODE_LENGTH must be 20"
  assert_eq "smart" "${DEFAULT_STRATEGY}" "DEFAULT_STRATEGY must be smart"
  assert_eq "auto" "${DEFAULT_COMMAND_PROFILE}" "DEFAULT_COMMAND_PROFILE must be auto"
  assert_eq "moto" "${DEFAULT_CODE_TYPE}" "DEFAULT_CODE_TYPE must be moto"
  assert_eq 10 "${DEFAULT_UPDATE_INTERVAL}" "DEFAULT_UPDATE_INTERVAL must be 10"
  assert_eq 100 "${DEFAULT_PERSIST_INTERVAL}" "DEFAULT_PERSIST_INTERVAL must be 100"
}

function test_charsets {
  source "${LIB_DIR}/constants.sh"
  assert_eq "0123456789" "${CHARSET_DIGITS}" "CHARSET_DIGITS value"
  assert_eq 10 "${#CHARSET_DIGITS}" "CHARSET_DIGITS length"

  assert_eq "ABCDEFGHIJKLMNOPQRSTUVWXYZ" "${CHARSET_UPPER_ALPHA}" "CHARSET_UPPER_ALPHA value"
  assert_eq 26 "${#CHARSET_UPPER_ALPHA}" "CHARSET_UPPER_ALPHA length"

  assert_eq "abcdefghijklmnopqrstuvwxyz" "${CHARSET_LOWER_ALPHA}" "CHARSET_LOWER_ALPHA value"
  assert_eq 26 "${#CHARSET_LOWER_ALPHA}" "CHARSET_LOWER_ALPHA length"

  assert_eq "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" "${CHARSET_UPPER_ALPHANUMERIC}" "CHARSET_UPPER_ALPHANUMERIC value"
  assert_eq 36 "${#CHARSET_UPPER_ALPHANUMERIC}" "CHARSET_UPPER_ALPHANUMERIC length"

  assert_eq 62 "${#CHARSET_MIXED_ALPHANUMERIC}" "CHARSET_MIXED_ALPHANUMERIC length"
  assert_eq "0123456789ABCDEF" "${CHARSET_HEX_UPPER}" "CHARSET_HEX_UPPER value"
  assert_eq 16 "${#CHARSET_HEX_UPPER}" "CHARSET_HEX_UPPER length"
  assert_eq "0123456789abcdef" "${CHARSET_HEX_LOWER}" "CHARSET_HEX_LOWER value"
  assert_eq 16 "${#CHARSET_HEX_LOWER}" "CHARSET_HEX_LOWER length"
}

function test_builtin_patterns {
  source "${LIB_DIR}/constants.sh"
  IFS=';' read -ra profiles <<< "${BUILTIN_PATTERN_PROFILES}"
  assert_eq 3 "${#profiles[@]}" "Exactly 3 experimental profiles must exist"

  local total_weight=0 entry name mask weight desc
  for entry in "${profiles[@]}"; do
    IFS=':' read -r name mask weight desc <<< "${entry}"
    assert_not_eq "" "${name}" "Profile name must not be empty"
    assert_not_eq "" "${mask}" "Profile mask must not be empty"
    assert_matches "${weight}" '^[0-9]+$' "Weight must be numeric"
    assert_not_eq "" "${desc}" "Description must not be empty"
    total_weight=$(( total_weight + weight ))
  done

  assert_eq 3 "${total_weight}" "Total profile weight must be 3"
  assert_contains "${BUILTIN_PATTERN_PROFILES}" "motorola-20:X{20}:1" "Experimental Motorola profile must be present"
}

function test_guard_and_immutability {
  source "${LIB_DIR}/constants.sh"
  assert_eq 1 "${CONSTANTS_INCLUDED}" "CONSTANTS_INCLUDED must be 1"

  # Sourcing again should succeed cleanly
  source "${LIB_DIR}/constants.sh"
  assert_eq 1 "${CONSTANTS_INCLUDED}" "Re-inclusion must be idempotent"

  # Readonly constants should fail mutation
  run_capture bash -c "source '${LIB_DIR}/constants.sh'; EXIT_SUCCESS=99"
  assert_not_eq 0 "${CAPTURE_STATUS}" "Mutating readonly constant should fail"
}

run_test "Constants exit codes" test_exit_codes
run_test "Constants defaults and boundaries" test_defaults_and_boundaries
run_test "Constants charsets definitions" test_charsets
run_test "Constants builtin profiles parsing" test_builtin_patterns
run_test "Constants include guard and immutability" test_guard_and_immutability

finish_tests
