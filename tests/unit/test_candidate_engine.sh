#!/usr/bin/env bash
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/../test_helper.sh"

setup_engine() {
  source "$LIB_DIR/constants.sh"
  source "$LIB_DIR/pattern_engine.sh"
  source "$LIB_DIR/device_storage.sh"
  source "$LIB_DIR/unlock_runner.sh"
  CONFIG_PATTERNS=$1 CONFIG_STRATEGY=${2:-sequential} CONFIG_ACTIVE_CHARSET=01
  CONFIG_KNOWN_POSITIONS=${3:-} STATE_GLOBAL_CURSOR=0
  engine_compile
  engine_seek 0
}
collect() {
  COLLECTED=''
  while fetch_next_candidate_code; do
    COLLECTED+="$CURRENT_CANDIDATE_CODE "
    advance_runtime_cursor
  done
}
reject() { if "$@" >/dev/null 2>&1; then printf 'Expected rejection: %s\n' "$*" >&2; return 1; fi; }

test_complete() {
  setup_engine 'mixed:?9:1'
  collect
  assert_eq '00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 ' "$COLLECTED" 'Mixed-radix carry and exhaustion'
  reject fetch_next_candidate_code
  assert_eq 20 "$STATE_GLOBAL_CURSOR" 'No restart after exhaustion'
}
test_overlap() {
  setup_engine 'digits:9:2;hex:H:1;same:9{1}:99' smart
  assert_eq 2 "$E_COUNT" 'Compiled duplicates removed'
  collect
  assert_eq '0 1 A 2 3 B 4 5 C 6 7 D 8 9 E F ' "$COLLECTED" 'Weights, first owner and exhausted patterns'
  setup_engine 'hex:H:1;digits:9:2' sequential
  collect
  assert_eq '0 1 2 3 4 5 6 7 8 9 A B C D E F ' "$COLLECTED" 'Covered later pattern exhausts without emission'
  setup_engine 'left:0?:1;right:?0:1' smart
  collect
  assert_eq '00 10 01 ' "$COLLECTED" 'Partial overlap is unique with scheduling'
}
test_fixed() {
  setup_engine 'wide:X9:1;digits:99:1' sequential '0:7'
  assert_eq 1 "$E_COUNT" 'Masks deduplicate after fixing positions'
  collect
  assert_eq '70 71 72 73 74 75 76 77 78 79 ' "$COLLECTED" 'Fixed positions reduce enumerated space'
  CONFIG_KNOWN_POSITIONS='2:1'; reject engine_compile
  CONFIG_KNOWN_POSITIONS='0:!'; reject engine_compile
  CONFIG_KNOWN_POSITIONS='0:7;0:8'; reject engine_compile
  CONFIG_KNOWN_POSITIONS='0:77'; reject engine_compile
  CONFIG_KNOWN_POSITIONS='00:7'; reject engine_compile
  CONFIG_KNOWN_POSITIONS=$'0:7\n1:8'; reject engine_compile
}
test_limits() {
  setup_engine 'tiny:9:1'
  reject engine_seek 10
  reject engine_seek 9223372036854775808
  reject engine_seek 08
  reject validate_pattern_mask '9{4097}'
  reject validate_pattern_mask '9{999999999999999999999999}'
  reject validate_pattern_mask '9{4096}9'
  reject validate_pattern_mask '9}'
  validate_pattern_mask '9{4096}'
  CONFIG_PATTERNS='a:9:9223372036854775807;b:A:1'; reject engine_compile
  CONFIG_PATTERNS='a:9:0'; reject engine_compile
  setup_engine 'large:X{20}:1'
  engine_seek 9223372036854775807
  engine_next
  local before=$CURRENT_CANDIDATE_CODE
  engine_advance
  engine_next
  assert_not_eq "$before" "$CURRENT_CANDIDATE_CODE" 'Vector continues past signed scalar offset'
  STATE_GLOBAL_CURSOR=9223372036854775807
  reject fetch_next_candidate_code
  reject advance_runtime_cursor
  assert_eq 9223372036854775807 "$STATE_GLOBAL_CURSOR" 'Counter never wraps'
}
test_resume() {
  local strategy i expected
  for strategy in sequential smart; do
    setup_engine 'left:0?:2;right:?0:1;digit:9:1' "$strategy"
    for ((i=0;i<2;i++)); do fetch_next_candidate_code; advance_runtime_cursor; done
    save_device_state state.dat
    collect; expected=$COLLECTED
    load_device_state state.dat
    engine_compile
    engine_restore
    STATE_GLOBAL_CURSOR=$STORED_LAST_VALUE
    collect
    assert_eq "$expected" "$COLLECTED" "Exact $strategy resume after overlap and carry"
    save_device_state exhausted.dat
    load_device_state exhausted.dat
    engine_compile; engine_restore
    reject engine_next
  done
  load_device_state state.dat
  STORED_PATTERN_OFFSETS='0,'; reject engine_restore
  load_device_state state.dat
  STORED_PATTERN_OFFSETS='0,0,0'; reject engine_restore
  STORED_POSITION_VECTOR='999'; reject engine_restore
  load_device_state state.dat
  STORED_SCHEDULER='9223372036854775808,0'; reject engine_restore
  load_device_state state.dat
  CONFIG_KNOWN_POSITIONS='0:0'; engine_compile; reject engine_restore
}
test_random() {
  setup_engine 'letters:X:1' random
  reject engine_seek 1
  local i
  for ((i=0;i<100;i++)); do
    engine_next
    assert_matches "$CURRENT_CANDIDATE_CODE" '^[A-Z0-9]$' 'Random candidate valid'
    engine_advance
    engine_random_below 9223372036854775807
    (( E_RANDOM >= 0 && E_RANDOM < 9223372036854775807 ))
  done
  setup_engine 'literal:!:1' random
  engine_next; assert_eq '!' "$CURRENT_CANDIDATE_CODE" 'Singleton sample'
  engine_advance; engine_next; assert_eq '!' "$CURRENT_CANDIDATE_CODE" 'Random repeats with replacement'
}
run_test 'Compiled complete mixed-radix enumeration' test_complete
run_test 'Compiled overlap ownership and scheduling' test_overlap
run_test 'Compiled fixed positions and deduplication' test_fixed
run_test 'Compiled limits and overflow guards' test_limits
run_test 'Compiled exact state resume and rejection' test_resume
run_test 'Compiled random sampling with replacement' test_random
finish_tests
