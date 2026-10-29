#!/usr/bin/env bash
# ==============================================================================
# test_argument_parser.sh - Unit tests for argument_parser.sh
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_helper.sh"

function test_valid_flag_parsing {
  source "${LIB_DIR}/constants.sh"
  source "${LIB_DIR}/terminal_ui.sh"
  source "${LIB_DIR}/argument_parser.sh"

  parse_cli_arguments \
    --device "ZY2234ABCD" \
    --type "numeric" \
    --length "8" \
    --start "5000" \
    --strategy "sequential" \
    --command "oem-unlock-code" \
    --pattern "9{8}"

  assert_eq "ZY2234ABCD" "${CLI_DEVICE_OVERRIDE}" "CLI_DEVICE_OVERRIDE parsed"
  assert_eq "numeric" "${CLI_CODE_TYPE}" "CLI_CODE_TYPE parsed"
  assert_eq "8" "${CLI_CODE_LENGTH}" "CLI_CODE_LENGTH parsed"
  assert_eq "5000" "${CLI_START_OFFSET}" "CLI_START_OFFSET parsed"
  assert_eq "sequential" "${CLI_STRATEGY}" "CLI_STRATEGY parsed"
  assert_eq "oem-unlock-code" "${CLI_COMMAND_PROFILE}" "CLI_COMMAND_PROFILE parsed"
  assert_eq "9{8}" "${CLI_SINGLE_PATTERN}" "CLI_SINGLE_PATTERN parsed"
}

function test_numeric_validation_and_boundaries {
  source "${LIB_DIR}/constants.sh"
  source "${LIB_DIR}/terminal_ui.sh"
  source "${LIB_DIR}/argument_parser.sh"

  # Max 64-bit value accepted
  parse_cli_arguments --start "9223372036854775807"
  assert_eq "9223372036854775807" "${CLI_START_OFFSET}" "MAX_INTEGER_VALUE accepted"

  # Value > 64-bit max rejected
  run_capture parse_cli_arguments --start "9223372036854775808"
  assert_not_eq 0 "${CAPTURE_STATUS}" "Overflow start offset rejected"

  # Negative start rejected
  run_capture parse_cli_arguments --start "-10"
  assert_not_eq 0 "${CAPTURE_STATUS}" "Negative start offset rejected"

  # Non-numeric start rejected
  run_capture parse_cli_arguments --start "abc"
  assert_not_eq 0 "${CAPTURE_STATUS}" "Non-numeric start offset rejected"

  # Zero length rejected
  run_capture parse_cli_arguments --length "0"
  assert_not_eq 0 "${CAPTURE_STATUS}" "Zero length rejected"
}

function test_missing_values_and_unknown_flags {
  source "${LIB_DIR}/constants.sh"
  source "${LIB_DIR}/terminal_ui.sh"
  source "${LIB_DIR}/argument_parser.sh"

  # Missing values
  run_capture parse_cli_arguments --device
  assert_not_eq 0 "${CAPTURE_STATUS}" "Missing device argument fails"

  run_capture parse_cli_arguments --strategy
  assert_not_eq 0 "${CAPTURE_STATUS}" "Missing strategy argument fails"

  # Unknown flags
  run_capture parse_cli_arguments --invalid-flag
  assert_not_eq 0 "${CAPTURE_STATUS}" "Unknown flag fails"
  assert_contains "${CAPTURE_OUTPUT}" "Unknown argument" "Error mentions unknown argument"
}

function test_help_and_list_patterns_output {
  source "${LIB_DIR}/constants.sh"
  source "${LIB_DIR}/terminal_ui.sh"
  source "${LIB_DIR}/argument_parser.sh"

  # Help output
  run_capture parse_cli_arguments --help
  assert_eq 0 "${CAPTURE_STATUS}" "--help returns exit code 0"
  assert_contains "${CAPTURE_OUTPUT}" "Fastboot Bootloader Unlock Console" "Help title"
  assert_contains "${CAPTURE_OUTPUT}" "Core Options:" "Help options"
  assert_contains "${CAPTURE_OUTPUT}" "Pattern DSL Tokens:" "Help DSL tokens"

  # List patterns output
  run_capture parse_cli_arguments --list-patterns
  assert_eq 0 "${CAPTURE_STATUS}" "--list-patterns returns exit code 0"
  assert_contains "${CAPTURE_OUTPUT}" "motorola-20" "Lists motorola-20"
  assert_contains "${CAPTURE_OUTPUT}" "sony-xperia-16" "Lists sony-xperia-16"
  assert_contains "${CAPTURE_OUTPUT}" "huawei-honor-legacy-16" "Lists huawei-honor-legacy-16"
}

run_test "Argument parser valid flag parsing" test_valid_flag_parsing
run_test "Argument parser numeric validation and boundaries" test_numeric_validation_and_boundaries
run_test "Argument parser missing values and unknown flags" test_missing_values_and_unknown_flags
run_test "Argument parser help and pattern listing" test_help_and_list_patterns_output

finish_tests
