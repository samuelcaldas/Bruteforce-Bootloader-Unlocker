#!/usr/bin/env bash
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/../test_helper.sh"

test_preview() {
  make_mock_executable fastboot 'printf called >> fastboot_called; exit 99'
  export FASTBOOT_BIN="$CURRENT_SANDBOX/bin/fastboot"
  printf 'not a state\n' > PREVIEW.dat
  run_capture "$CLI_BIN" --device PREVIEW --type numeric --length 2 --start 98 --preview 5
  assert_eq 0 "$CAPTURE_STATUS" 'Preview works without device'
  assert_eq $'98\n99' "$CAPTURE_STDOUT" 'Generic type and endpoint'
  assert_file_not_exists fastboot_called 'No fastboot invocation'
  assert_eq 'not a state' "$(cat PREVIEW.dat)" 'Preview neither reads nor writes state'
  run_capture "$CLI_BIN" --pattern '9{2}' --known-positions '0:7' --preview 3
  assert_eq $'70\n71\n72' "$CAPTURE_STDOUT" 'CLI fixed positions'
}
test_profiles() {
  run_capture "$CLI_BIN" --key-profile motorola-20 --preview 1
  assert_not_eq 0 "$CAPTURE_STATUS" 'Experimental opt-in required'
  local profile
  for profile in motorola-20 sony-xperia-16 huawei-honor-legacy-16; do
    run_capture "$CLI_BIN" --key-profile "$profile" --allow-experimental --preview 1
    assert_eq 0 "$CAPTURE_STATUS" "Profile $profile supported"
  done
  run_capture "$CLI_BIN" --key-profile unknown --allow-experimental --preview 1
  assert_not_eq 0 "$CAPTURE_STATUS" 'Unknown profile rejected'
  run_capture "$CLI_BIN" --key-profile motorola-20 --pattern 9 --allow-experimental --preview 1
  assert_not_eq 0 "$CAPTURE_STATUS" 'Conflicting selectors rejected'
  run_capture "$CLI_BIN" --patterns 'p:9:1' --pattern 9 --preview 1
  assert_not_eq 0 "$CAPTURE_STATUS" 'Conflicting masks rejected'
  run_capture "$CLI_BIN" --pattern 9 --known-positions '0:A' --preview 1
  assert_not_eq 0 "$CAPTURE_STATUS" 'Incompatible positions rejected'
}
test_exhaustion_and_state() {
  create_mock_fastboot
  export MOCK_FASTBOOT_DEVICES=$'FINITE\tfastboot' MOCK_FASTBOOT_LOG=fastboot.log
  run_capture_with_stdin AUTHORIZED "$CLI_BIN" --device FINITE --pattern 9 --command oem-unlock-code
  assert_eq 0 "$CAPTURE_STATUS" 'Finite search terminates'
  assert_contains "$CAPTURE_OUTPUT" 'Candidate space exhausted' 'Reports exhaustion'
  assert_file_not_exists SUCCESS_FINITE.txt 'Exhaustion is not unlock success'
  assert_eq 10 "$(grep -c 'oem unlock ' fastboot.log)" 'Exactly ten attempts'
  cp FINITE.dat original.dat
  run_capture_with_stdin AUTHORIZED "$CLI_BIN" --device FINITE
  assert_eq 0 "$CAPTURE_STATUS" 'Exhausted state resumes'
  assert_eq 10 "$(grep -c 'oem unlock ' fastboot.log)" 'No repeated attempt'
  run_capture_with_stdin AUTHORIZED "$CLI_BIN" --device FINITE --pattern H
  assert_not_eq 0 "$CAPTURE_STATUS" 'Incompatible state rejected'
  cmp FINITE.dat original.dat
  run_capture_with_stdin AUTHORIZED "$CLI_BIN" --device FINITE --pattern H --start 15
  assert_eq 0 "$CAPTURE_STATUS" 'Explicit restart allowed'
  local backups=(FINITE.dat.before-restart.*)
  assert_eq 1 "${#backups[@]}" 'Backup retained'
  cmp "${backups[0]}" original.dat
}
test_legacy_rejection() {
  create_mock_fastboot
  export MOCK_FASTBOOT_DEVICES=$'OLD\tfastboot'
  cat > OLD.dat <<'STATE'
code_type=numeric
code_length=2
last_value=2
charset=0123456789
strategy=sequential
known_positions=0:7
command_profile=oem-unlock-code
patterns=p:99:1
pattern_offsets=2
STATE
  cp OLD.dat old-original.dat
  run_capture_with_stdin AUTHORIZED "$CLI_BIN" --device OLD
  assert_not_eq 0 "$CAPTURE_STATUS" 'Legacy fixed positions are not migrated'
  cmp OLD.dat old-original.dat
  assert_contains "$CAPTURE_OUTPUT" '--start 0' 'Explicit restart guidance'
}
test_v2_resume() {
  create_mock_fastboot
  export MOCK_FASTBOOT_DEVICES=$'RESUME\tfastboot' MOCK_FASTBOOT_MODE=terminal_carrier
  run_capture_with_stdin AUTHORIZED "$CLI_BIN" --device RESUME --pattern '9{2}' --start 12 --command oem-unlock-code
  assert_eq 2 "$CAPTURE_STATUS" 'Terminal failure preserves pending candidate'
  unset MOCK_FASTBOOT_MODE
  export MOCK_FASTBOOT_SUCCESS_CODE=13 MOCK_FASTBOOT_LOG=resume.log
  run_capture_with_stdin AUTHORIZED "$CLI_BIN" --device RESUME
  assert_eq 0 "$CAPTURE_STATUS" 'Version 2 resumes successfully'
  assert_contains "$(cat resume.log)" 'oem unlock 12' 'Pending candidate retained'
  assert_contains "$(cat resume.log)" 'oem unlock 13' 'Carry advances after resume'
  assert_eq 2 "$(grep -c 'oem unlock ' resume.log)" 'No earlier candidates replayed'
}
run_test 'Preview avoids fastboot and state IO' test_preview
run_test 'Experimental profiles and invalid combinations' test_profiles
run_test 'Finite CLI exhaustion resume and restart backup' test_exhaustion_and_state
run_test 'Incompatible legacy state is preserved' test_legacy_rejection
run_test 'Version 2 CLI resume retains pending candidate' test_v2_resume
finish_tests
