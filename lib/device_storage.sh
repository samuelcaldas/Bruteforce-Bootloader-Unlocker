#!/usr/bin/env bash
# ==============================================================================
# device_storage.sh - State persistence, device file serialization, and safety
# ==============================================================================

[[ -n "${DEVICE_STORAGE_INCLUDED:-}" ]] && return 0
readonly DEVICE_STORAGE_INCLUDED=1

function sanitize_device_identifier {
  local raw_identifier=$1
  printf "%s" "${raw_identifier}" | tr -c 'A-Za-z0-9._-' '_'
}

function resolve_state_file_path {
  local safe_id=$1
  printf "./%s.dat" "${safe_id}"
}

function resolve_success_file_path {
  local safe_id=$1
  printf "./SUCCESS_%s.txt" "${safe_id}"
}

function load_device_state {
  local file_path=$1
  [[ ! -f "${file_path}" ]] && return 0

  STORED_STATE_PRESENT=1
  while IFS='=' read -r key value || [[ -n "${key}" ]]; do
    case "${key}" in
      state_version) STORED_STATE_VERSION=$value ;;
      engine_config) STORED_ENGINE_CONFIG=$value ;;
      position_vector) STORED_POSITION_VECTOR=$value ;;
      exhausted_vector) STORED_EXHAUSTED_VECTOR=$value ;;
      scheduler) STORED_SCHEDULER=$value ;;
      key_profile) STORED_KEY_PROFILE=$value ;;
      code_type) STORED_CODE_TYPE="${value}" ;;
      code_length) STORED_CODE_LENGTH="${value}" ;;
      last_value) STORED_LAST_VALUE="${value}" ;;
      charset) STORED_CHARSET="${value}" ;;
      strategy) STORED_STRATEGY="${value}" ;;
      known_positions) STORED_KNOWN_POSITIONS="${value}" ;;
      command_profile) STORED_COMMAND_PROFILE="${value}" ;;
      patterns) STORED_PATTERNS="${value}" ;;
      pattern_offsets) STORED_PATTERN_OFFSETS="${value}" ;;
      resolved_command) STORED_RESOLVED_COMMAND="${value}" ;;
    esac
  done < "${file_path}"
}

function save_device_state {
  local file_path=$1 temp_path="${1}.tmp.$$"

  if [[ ${E_READY:-0} == 1 ]]; then engine_serialize; fi
  {
    printf 'state_version=2\nengine_config=%s\n' "${E_CONFIG:-}"
    printf 'position_vector=%s\nexhausted_vector=%s\nscheduler=%s\n' "${STATE_POSITION_VECTOR:-}" "${STATE_EXHAUSTED_VECTOR:-}" "${STATE_SCHEDULER:-}"
    printf 'key_profile=%s\n' "${CONFIG_KEY_PROFILE:-}"
    printf "code_type=%s\n" "${CONFIG_CODE_TYPE:-}"
    printf "code_length=%s\n" "${CONFIG_CODE_LENGTH:-}"
    printf "last_value=%s\n" "${STATE_GLOBAL_CURSOR:-0}"
    printf "charset=%s\n" "${CONFIG_ACTIVE_CHARSET:-}"
    printf "strategy=%s\n" "${CONFIG_STRATEGY:-}"
    printf "known_positions=%s\n" "${CONFIG_KNOWN_POSITIONS:-}"
    printf "command_profile=%s\n" "${CONFIG_COMMAND_PROFILE:-}"
    printf "patterns=%s\n" "${CONFIG_PATTERNS:-}"
    printf "pattern_offsets=%s\n" "${STATE_PATTERN_OFFSETS:-}"
    printf "resolved_command=%s\n" "${STATE_RESOLVED_COMMAND:-}"
  } > "${temp_path}"

  mv -f "${temp_path}" "${file_path}"
}

function record_successful_unlock {
  local file_path=$1 code=$2
  printf "%s\n" "${code}" > "${file_path}"
}

function apply_known_positional_characters {
  local raw_code=$1 positions_spec=$2 temp_code pos char
  temp_code="${raw_code}"
  [[ -z "${positions_spec}" ]] && { printf "%s" "${temp_code}"; return 0; }

  while IFS=':' read -r pos char; do
    if [[ "${pos}" =~ ^[0-9]+$ && -n "${char}" && ${#char} -eq 1 && "${pos}" -lt ${#temp_code} ]]; then
      temp_code="${temp_code:0:${pos}}${char}${temp_code:$((pos+1))}"
    fi
  done <<< "${positions_spec//;/$'\n'}"

  printf "%s" "${temp_code}"
}
