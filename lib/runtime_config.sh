#!/usr/bin/env bash
# Configuration and conservative state migration, before any state write.
resolve_candidate_configuration() {
  CONFIG_CODE_TYPE=${CLI_CODE_TYPE:-${STORED_CODE_TYPE:-$DEFAULT_CODE_TYPE}}
  CONFIG_CODE_LENGTH=${CLI_CODE_LENGTH:-${STORED_CODE_LENGTH:-$DEFAULT_CODE_LENGTH}}
  CONFIG_STRATEGY=${CLI_STRATEGY:-${STORED_STRATEGY:-$DEFAULT_STRATEGY}}
  CONFIG_COMMAND_PROFILE=${CLI_COMMAND_PROFILE:-${STORED_COMMAND_PROFILE:-$DEFAULT_COMMAND_PROFILE}}
  CONFIG_KNOWN_POSITIONS=${CLI_KNOWN_POSITIONS:-${STORED_KNOWN_POSITIONS:-}}
  CONFIG_KEY_PROFILE=${CLI_KEY_PROFILE:-${STORED_KEY_PROFILE:-}}
  STATE_GLOBAL_CURSOR=${CLI_START_OFFSET:-${STORED_LAST_VALUE:-0}}
  engine_uint "$STATE_GLOBAL_CURSOR" && engine_uint "$CONFIG_CODE_LENGTH" && (( CONFIG_CODE_LENGTH > 0 && CONFIG_CODE_LENGTH <= 4096 )) || { engine_error 'Invalid stored length or cursor'; return 1; }
  case $CONFIG_CODE_TYPE in
    numeric) CONFIG_ACTIVE_CHARSET=$CHARSET_DIGITS ;;
    alpha|moto) CONFIG_ACTIVE_CHARSET=$CHARSET_UPPER_ALPHANUMERIC ;;
    *) engine_error 'Invalid code type'; return 1 ;;
  esac
  case $CONFIG_STRATEGY in smart|sequential|random) ;; *) engine_error 'Invalid strategy'; return 1 ;; esac
  case $CONFIG_COMMAND_PROFILE in auto|flashing-unlock|flashing-unlock-code|oem-unlock-code|oem-unlock|oem-unlock-go) ;; *) engine_error 'Invalid command profile'; return 1 ;; esac
  local entry name mask weight desc found=0
  local -a profiles
  CONFIG_PATTERNS=${STORED_PATTERNS:-}
  if [[ -n $CLI_SINGLE_PATTERN || -n $CLI_PATTERN_SCHEDULE ]]; then
    CONFIG_KEY_PROFILE=''
    if [[ -n $CLI_SINGLE_PATTERN ]]; then
      [[ $CLI_SINGLE_PATTERN != *:* && $CLI_SINGLE_PATTERN != *';'* ]] || { engine_error 'Colon and semicolon are reserved schedule delimiters'; return 1; }
      CONFIG_PATTERNS="custom:$CLI_SINGLE_PATTERN:10:User custom mask"
    else CONFIG_PATTERNS=$CLI_PATTERN_SCHEDULE; fi
  elif [[ -n $CONFIG_KEY_PROFILE ]]; then
    (( CLI_ALLOW_EXPERIMENTAL == 1 )) || { engine_error 'Experimental profiles require --allow-experimental (also on resume)'; return 1; }
    IFS=';' read -r -a profiles <<< "$BUILTIN_PATTERN_PROFILES"
    for entry in "${profiles[@]}"; do
      IFS=: read -r name mask weight desc <<< "$entry"
      if [[ $name == "$CONFIG_KEY_PROFILE" ]]; then CONFIG_PATTERNS=$entry; found=1; break; fi
    done
    (( found )) || { engine_error "Unknown key profile: $CONFIG_KEY_PROFILE"; return 1; }
  fi
  engine_compile || return 1
}

initialize_candidate_state() {
  local offset
  if [[ -n $CLI_START_OFFSET ]]; then engine_seek "$CLI_START_OFFSET"; return $?; fi
  if [[ -z ${STORED_STATE_PRESENT:-} ]]; then engine_seek 0; return $?; fi
  [[ -n ${STORED_LAST_VALUE:-} ]] || { engine_error 'Missing state cursor; restart explicitly with --start 0'; return 1; }
  if [[ ${STORED_STATE_VERSION:-} == 2 ]]; then engine_restore; return $?; fi
  [[ -z ${STORED_STATE_VERSION:-} ]] || { engine_error 'Unsupported state version; restart explicitly with --start 0'; return 1; }
  # The legacy multi-pattern scheduler restarted exhausted masks and had no ownership
  # rule. Only a single unmodified deterministic pattern has equivalent enumeration.
  if (( E_COUNT != 1 )) || [[ -n $CONFIG_KNOWN_POSITIONS || $CONFIG_STRATEGY == random ||
    $CONFIG_CODE_TYPE != "${STORED_CODE_TYPE:-}" || $CONFIG_CODE_LENGTH != "${STORED_CODE_LENGTH:-}" ||
    $CONFIG_ACTIVE_CHARSET != "${STORED_CHARSET:-}" || $CONFIG_STRATEGY != "${STORED_STRATEGY:-}" ||
    $CONFIG_PATTERNS != "${STORED_PATTERNS:-}" || ${STORED_PATTERNS:-} == *';'* ||
    ( -z ${STORED_PATTERNS:-} && $CONFIG_ACTIVE_CHARSET != "$CHARSET_UPPER_ALPHANUMERIC" ) ]]; then
    engine_error 'Legacy enumeration is not equivalent; state preserved. Restart explicitly with --start 0'; return 1
  fi
  offset=${STORED_PATTERN_OFFSETS:-$STORED_LAST_VALUE}
  engine_seek "$offset" || { engine_error 'Legacy offset cannot be migrated; restart explicitly with --start 0'; return 1; }
}

preview_candidates() {
  local n status
  for ((n=0; n<CLI_PREVIEW; n++)); do
    if fetch_next_candidate_code; then :; else
      status=$?; (( status == 1 )) && return 0; return "$status"
    fi
    printf '%s\n' "$CURRENT_CANDIDATE_CODE"
    advance_runtime_cursor || return 1
  done
}
