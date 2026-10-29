#!/usr/bin/env bash
# ==============================================================================
# test_cli_workflow.sh - Integration tests for bootloader_unlocker CLI workflow
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_helper.sh"

function test_cli_help_and_list {
  # Help option
  run_capture "${CLI_BIN}" --help
  assert_eq 0 "${CAPTURE_STATUS}" "--help exits 0"
  assert_contains "${CAPTURE_OUTPUT}" "Fastboot Bootloader Unlock Console" "Output contains title"
  assert_no_ansi "${CAPTURE_OUTPUT}" "Non-TTY output has no ANSI codes"

  # List patterns option
  run_capture "${CLI_BIN}" --list-patterns
  assert_eq 0 "${CAPTURE_STATUS}" "--list-patterns exits 0"
  assert_contains "${CAPTURE_OUTPUT}" "motorola-20" "Output lists builtin profile"

  # Verify no state files created
  local dat_count
  dat_count=$(ls -1 *.dat 2>/dev/null | wc -l || true)
  assert_eq 0 "${dat_count}" "No state files created during info queries"
}

function test_cli_missing_fastboot_binary {
  # Ensure no fastboot binary in PATH
  export PATH="/usr/bin:/bin"
  export FASTBOOT_BIN="/nonexistent/path/to/fastboot"

  run_capture "${CLI_BIN}"
  assert_not_eq 0 "${CAPTURE_STATUS}" "Missing fastboot binary must fail"
  assert_contains "${CAPTURE_OUTPUT}" "fastboot binary not found in PATH" "Helpful installation advice printed"
}

function test_cli_no_device_connected {
  create_mock_fastboot
  export MOCK_FASTBOOT_DEVICES=""

  run_capture "${CLI_BIN}"
  assert_not_eq 0 "${CAPTURE_STATUS}" "No connected device must fail"
  assert_contains "${CAPTURE_OUTPUT}" "No device detected in Fastboot mode" "Safety stop warning printed"
}

function test_cli_authorization_refusal {
  create_mock_fastboot
  export MOCK_FASTBOOT_DEVICES="ZY22345678	fastboot"
  export MOCK_FASTBOOT_LOG="fastboot_calls.log"

  run_capture_with_stdin "NO" "${CLI_BIN}" --device "ZY22345678" --command "oem-unlock-code"
  assert_not_eq 0 "${CAPTURE_STATUS}" "Refused authorization must exit non-zero"
  assert_contains "${CAPTURE_OUTPUT}" "Authorization confirmation was not provided" "Abort notice displayed"

  # Verify no unlock dispatch happened
  if [[ -f "${MOCK_FASTBOOT_LOG}" ]]; then
    local calls
    calls=$(cat "${MOCK_FASTBOOT_LOG}")
    assert_not_contains "${calls}" "unlock" "No unlock payload sent without authorization"
  fi
}

function test_cli_direct_unlock_success {
  create_mock_fastboot
  export MOCK_FASTBOOT_DEVICES="ZY22345678	fastboot"
  export MOCK_FASTBOOT_LOG="fastboot_calls.log"

  run_capture_with_stdin "AUTHORIZED" "${CLI_BIN}" --device "ZY22345678" --command "flashing-unlock"
  assert_eq 0 "${CAPTURE_STATUS}" "Direct flashing-unlock exits 0"
  assert_contains "${CAPTURE_OUTPUT}" "Unlock command sent successfully" "Success message displayed"

  # Verify mock received exact command
  assert_file_exists "${MOCK_FASTBOOT_LOG}" "Mock log exists"
  local calls
  calls=$(cat "${MOCK_FASTBOOT_LOG}")
  assert_contains "${calls}" "-s ZY22345678 flashing unlock" "Dispatched direct flashing unlock"
}

function test_cli_candidate_success_immediate {
  create_mock_fastboot
  export MOCK_FASTBOOT_DEVICES="TESTDEV100	fastboot"
  export MOCK_FASTBOOT_SUCCESS_CODE="00"

  run_capture_with_stdin "AUTHORIZED" "${CLI_BIN}" \
    --device "TESTDEV100" \
    --pattern "9{2}" \
    --strategy "sequential" \
    --command "oem-unlock-code"

  assert_eq 0 "${CAPTURE_STATUS}" "Immediate unlock code match exits 0"
  assert_contains "${CAPTURE_OUTPUT}" "SUCCESS! Verified unlock code: 00" "Success banner displayed"

  # Verify state and success files exist
  assert_file_exists "TESTDEV100.dat" "Device state file must exist"
  assert_file_exists "SUCCESS_TESTDEV100.txt" "Success record file must exist"

  local recorded_code
  recorded_code=$(cat "SUCCESS_TESTDEV100.txt")
  assert_eq "00" "${recorded_code}" "Verified code written to file"
}

function test_cli_retry_loop_eventual_success {
  create_mock_fastboot
  export MOCK_FASTBOOT_DEVICES="TESTDEV200	fastboot"
  export MOCK_FASTBOOT_SUCCESS_CODE="02"
  export MOCK_FASTBOOT_LOG="fastboot_calls.log"

  run_capture_with_stdin "AUTHORIZED" "${CLI_BIN}" \
    --device "TESTDEV200" \
    --pattern "9{2}" \
    --strategy "sequential" \
    --command "oem-unlock-code"

  assert_eq 0 "${CAPTURE_STATUS}" "Eventual match exits 0"
  assert_contains "${CAPTURE_OUTPUT}" "SUCCESS! Verified unlock code: 02" "Success code 02 confirmed"

  # Verify attempt sequence in log
  local calls
  calls=$(cat "${MOCK_FASTBOOT_LOG}")
  assert_contains "${calls}" "oem unlock 00" "Attempted code 00"
  assert_contains "${calls}" "oem unlock 01" "Attempted code 01"
  assert_contains "${calls}" "oem unlock 02" "Attempted code 02"

  local recorded_code
  recorded_code=$(cat "SUCCESS_TESTDEV200.txt")
  assert_eq "02" "${recorded_code}" "Code 02 recorded"
}

function test_cli_state_persistence_and_resume {
  create_mock_fastboot
  export MOCK_FASTBOOT_DEVICES="TESTDEV300	fastboot"
  export MOCK_FASTBOOT_LOG="fastboot_calls_1.log"

  # Seed state file with last_value=2
  cat <<'EOF' > TESTDEV300.dat
code_type=numeric
code_length=2
last_value=2
charset=0123456789
strategy=sequential
known_positions=
command_profile=oem-unlock-code
patterns=custom:9{2}:10:User custom mask
pattern_offsets=2
resolved_command=oem-unlock-code
EOF

  # Mock success on code 03
  export MOCK_FASTBOOT_SUCCESS_CODE="03"

  run_capture_with_stdin "AUTHORIZED" "${CLI_BIN}" --device "TESTDEV300"
  assert_eq 0 "${CAPTURE_STATUS}" "Resumed search exits 0 on match"

  local calls
  calls=$(cat "${MOCK_FASTBOOT_LOG}")
  # Must start from 02 (the saved offset), not 00
  assert_not_contains "${calls}" "oem unlock 00" "Did not re-test 00"
  assert_not_contains "${calls}" "oem unlock 01" "Did not re-test 01"
  assert_contains "${calls}" "oem unlock 02" "Tested offset 2 (02)"
  assert_contains "${calls}" "oem unlock 03" "Tested offset 3 (03) and succeeded"
}

function test_cli_terminal_rejection_halt {
  create_mock_fastboot
  export MOCK_FASTBOOT_DEVICES="TESTDEV400	fastboot"
  export MOCK_FASTBOOT_MODE="terminal_carrier"

  run_capture_with_stdin "AUTHORIZED" "${CLI_BIN}" \
    --device "TESTDEV400" \
    --pattern "9{2}" \
    --command "oem-unlock-code"

  # Exit code 2 for terminal fastboot errors
  assert_eq 2 "${CAPTURE_STATUS}" "Terminal fastboot rejection exits with code 2"
  assert_contains "${CAPTURE_OUTPUT}" "Terminal Fastboot error encountered" "Terminal error warning printed"
  assert_file_exists "TESTDEV400.dat" "State saved on terminal rejection"
  assert_file_not_exists "SUCCESS_TESTDEV400.txt" "No success file created"
}

function test_cli_sandbox_containment {
  create_mock_fastboot
  export MOCK_FASTBOOT_DEVICES="SAFE../../DEV	fastboot"
  export MOCK_FASTBOOT_SUCCESS_CODE="99"

  run_capture_with_stdin "AUTHORIZED" "${CLI_BIN}" \
    --pattern "9{2}" \
    --start "99" \
    --command "oem-unlock-code"

  assert_eq 0 "${CAPTURE_STATUS}" "Containment test exits 0"

  # State files must stay inside sandbox without escaping to parent
  assert_file_not_exists "../SAFE.._.._DEV.dat" "No files escaped to parent directory"
  assert_file_exists "SAFE.._.._DEV.dat" "Sanitized state file exists in sandbox"
}

run_test "CLI --help and --list-patterns queries" test_cli_help_and_list
run_test "CLI missing fastboot dependency" test_cli_missing_fastboot_binary
run_test "CLI no connected fastboot device" test_cli_no_device_connected
run_test "CLI authorization refusal abort" test_cli_authorization_refusal
run_test "CLI direct flashing unlock flow" test_cli_direct_unlock_success
run_test "CLI immediate candidate unlock success" test_cli_candidate_success_immediate
run_test "CLI retry loop with eventual success" test_cli_retry_loop_eventual_success
run_test "CLI state persistence and resume" test_cli_state_persistence_and_resume
run_test "CLI terminal fastboot rejection halt" test_cli_terminal_rejection_halt
run_test "CLI filesystem containment and path safety" test_cli_sandbox_containment

finish_tests
