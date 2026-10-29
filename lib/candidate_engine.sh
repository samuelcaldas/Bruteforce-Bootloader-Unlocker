#!/usr/bin/env bash
# Compiled position alphabets and mixed-radix cursors. Call in the parent shell.
[[ -n ${CANDIDATE_ENGINE_INCLUDED:-} ]] && return 0
readonly CANDIDATE_ENGINE_INCLUDED=1

engine_error() { printf 'Candidate engine: %s\n' "$*" >&2; return 1; }

# Canonical unsigned decimal, bounded before arithmetic (never evaluate user code).
engine_uint() {
  [[ $1 =~ ^(0|[1-9][0-9]*)$ ]] || return 1
  # Lexical comparison is intentional: numeric arithmetic would overflow here.
  # shellcheck disable=SC2071
  (( ${#1} < 19 )) || { (( ${#1} == 19 )) && [[ $1 < 9223372036854775808 ]]; }
}

engine_compile() {
  local schedule=${CONFIG_PATTERNS:-}
  [[ -n $schedule ]] || schedule="generic:?{${CONFIG_CODE_LENGTH:-20}}:1"
  local entry name mask weight desc expanded cs i j p total signature pos char spec
  local -a entries fixed_specs alphabets
  local -A fixed=() seen=()
  E_NAMES=(); E_MASKS=(); E_WEIGHTS=(); E_STARTS=(); E_LENGTHS=(); E_SPACES=()
  E_ALPHABETS=(); E_BASES=(); E_DIGITS=(); E_DONE=(); E_OFFSETS=()
  E_COUNT=0 E_SLOT=0 E_QUOTA=0 E_READY=0
  [[ $schedule != *$'\n'* && $schedule != *$'\r'* && $schedule != ';'* && $schedule != *';' && $schedule != *';;'* ]] || { engine_error 'Invalid schedule separators'; return 1; }
  spec=${CONFIG_KNOWN_POSITIONS:-}
  [[ $spec != *$'\n'* && $spec != *$'\r'* ]] || { engine_error 'Known positions must be a single line'; return 1; }
  if [[ -n $spec ]]; then
    [[ $spec != ';'* && $spec != *';' && $spec != *';;'* ]] || { engine_error 'Invalid known positions'; return 1; }
    IFS=';' read -r -a fixed_specs <<< "$spec"
    for entry in "${fixed_specs[@]}"; do
      pos=${entry%%:*}; char=${entry#*:}
      engine_uint "$pos" && (( pos < 4096 )) && [[ $entry == *:* && ${#char} == 1 && $char != $'\n' && $char != $'\r' ]] || { engine_error "Invalid known position: $entry"; return 1; }
      [[ ! ${fixed[$pos]+present} ]] || { engine_error "Duplicate known position: $pos"; return 1; }
      fixed[$pos]=$char
    done
  fi
  IFS=';' read -r -a entries <<< "$schedule"
  total=0
  for entry in "${entries[@]}"; do
    IFS=':' read -r name mask weight desc <<< "$entry"
    [[ -n $name ]] && engine_uint "$weight" && (( weight > 0 )) || { engine_error "Invalid pattern entry: $entry"; return 1; }
    expanded=$(expand_pattern_mask "$mask") || { engine_error "Invalid pattern mask: $mask"; return 1; }
    alphabets=(); signature=''
    for pos in "${!fixed[@]}"; do
      (( pos < ${#expanded} )) || { engine_error "Known position $pos outside mask $mask"; return 1; }
    done
    for ((j=0; j<${#expanded}; j++)); do
      cs=$(get_charset_for_symbol "${expanded:j:1}" "$CONFIG_ACTIVE_CHARSET")
      [[ -n $cs ]] || { engine_error 'Empty alphabet'; return 1; }
      if [[ ${fixed[$j]+present} ]]; then
        char=${fixed[$j]}
        [[ $cs == *"$char"* ]] || { engine_error "Known character at $j incompatible with $mask"; return 1; }
        cs=$char
      fi
      alphabets+=("$cs")
      printf -v spec '%q' "$cs"
      signature+=" $spec"
    done
    [[ ! ${seen[$signature]+present} ]] || continue
    seen[$signature]=1
    (( total <= MAX_INTEGER_VALUE - weight )) || { engine_error 'Weight total overflows'; return 1; }
    total=$((total + weight))
    i=$E_COUNT; E_COUNT=$((E_COUNT+1))
    E_NAMES[i]=$name E_MASKS[i]=$mask E_WEIGHTS[i]=$weight
    E_STARTS[i]=${#E_ALPHABETS[@]} E_LENGTHS[i]=${#alphabets[@]} E_DONE[i]=0 E_OFFSETS[i]=0
    p=1
    for cs in "${alphabets[@]}"; do
      E_ALPHABETS+=("$cs"); E_BASES+=("${#cs}"); E_DIGITS+=(0)
      if [[ $p != huge ]]; then
        if (( p > MAX_INTEGER_VALUE / ${#cs} )); then p=huge; else p=$((p * ${#cs})); fi
      fi
    done
    E_SPACES[i]=$p
  done
  E_TOTAL_WEIGHT=$total
  printf -v E_CONFIG '%q|' "${CONFIG_CODE_TYPE:-}" "${CONFIG_CODE_LENGTH:-20}" "$CONFIG_ACTIVE_CHARSET" "${CONFIG_STRATEGY:-smart}" "${CONFIG_KNOWN_POSITIONS:-}" "$schedule" "${CONFIG_KEY_PROFILE:-}" "${CONFIG_COMMAND_PROFILE:-}"
  E_READY=1
}

# Offset is applied independently to each compiled pattern; an endpoint is exhausted.
engine_seek() {
  local offset=$1 i j n base
  engine_uint "$offset" || { engine_error 'Invalid offset'; return 1; }
  if [[ ${CONFIG_STRATEGY:-smart} == random && $offset != 0 ]]; then
    engine_error 'Random sampling has no ordered offset; use --start 0'; return 1
  fi
  for ((i=0; i<E_COUNT; i++)); do
    if [[ ${E_SPACES[i]} != huge ]] && (( offset >= E_SPACES[i] )); then
      engine_error "Start offset outside pattern ${E_NAMES[i]}"; return 1
    fi
    n=$offset E_DONE[i]=0 E_OFFSETS[i]=$offset
    for ((j=E_STARTS[i]+E_LENGTHS[i]-1; j>=E_STARTS[i]; j--)); do
      base=${E_BASES[j]}; E_DIGITS[j]=$((n % base)); n=$((n / base))
    done
    (( n == 0 )) || { engine_error 'Offset outside space'; return 1; }
  done
  E_SLOT=0 E_QUOTA=0
}

engine_increment() {
  local i=$1 j
  if [[ ${E_OFFSETS[i]} != huge ]]; then
    if (( E_OFFSETS[i] == MAX_INTEGER_VALUE )); then E_OFFSETS[i]=huge; else E_OFFSETS[i]=$((E_OFFSETS[i]+1)); fi
  fi
  for ((j=E_STARTS[i]+E_LENGTHS[i]-1; j>=E_STARTS[i]; j--)); do
    if (( E_DIGITS[j]+1 < E_BASES[j] )); then
      E_DIGITS[j]=$((E_DIGITS[j]+1)); return 0
    fi
    E_DIGITS[j]=0
  done
  E_DONE[i]=1
}

# Uniform rejection sampling. Small bases need only one RANDOM draw.
engine_random_below() {
  local base=$1 sample limit
  if (( base <= 32768 )); then
    limit=$((32768 - 32768 % base))
    while :; do sample=$RANDOM; (( sample < limit )) && break; done
  else
    limit=$((MAX_INTEGER_VALUE - MAX_INTEGER_VALUE % base))
    while :; do
      sample=$(( (RANDOM << 48) | (RANDOM << 33) | (RANDOM << 18) | (RANDOM << 3) | (RANDOM & 7) ))
      (( sample < limit )) && break
    done
  fi
  E_RANDOM=$((sample % base))
}

engine_select() {
  local i n slot
  if [[ ${CONFIG_STRATEGY:-smart} == random ]]; then
    engine_random_below "$E_TOTAL_WEIGHT"; slot=$E_RANDOM
    for ((i=0; i<E_COUNT; i++)); do
      if (( slot < E_WEIGHTS[i] )); then E_SELECTED=$i; return 0; fi
      slot=$((slot - E_WEIGHTS[i]))
    done
  fi
  if [[ ${CONFIG_STRATEGY:-smart} == sequential ]]; then
    for ((i=0; i<E_COUNT; i++)); do
      if (( ! E_DONE[i] )); then E_SELECTED=$i; return 0; fi
    done
  else
    for ((n=0; n<E_COUNT; n++)); do
      if (( ! E_DONE[E_SLOT] )); then
        (( E_QUOTA > 0 )) || E_QUOTA=${E_WEIGHTS[E_SLOT]}
        E_SELECTED=$E_SLOT; return 0
      fi
      E_SLOT=$(((E_SLOT+1)%E_COUNT)); E_QUOTA=0
    done
  fi
  return 1
}

engine_owned_by_earlier() {
  local i j k match cs char
  for ((i=0; i<E_SELECTED; i++)); do
    (( E_LENGTHS[i] == ${#CURRENT_CANDIDATE_CODE} )) || continue
    match=1
    for ((j=0; j<E_LENGTHS[i]; j++)); do
      k=$((E_STARTS[i]+j)); cs=${E_ALPHABETS[k]}; char=${CURRENT_CANDIDATE_CODE:j:1}
      if [[ $cs != *"$char"* ]]; then match=0; break; fi
    done
    (( match )) && return 0
  done
  return 1
}

engine_next() {
  local j cs digit i
  while engine_select; do
    i=$E_SELECTED; CURRENT_CANDIDATE_CODE=''
    for ((j=E_STARTS[i]; j<E_STARTS[i]+E_LENGTHS[i]; j++)); do
      cs=${E_ALPHABETS[j]}
      if [[ ${CONFIG_STRATEGY:-smart} == random ]]; then
        engine_random_below "${E_BASES[j]}"; digit=$E_RANDOM
      else digit=${E_DIGITS[j]}; fi
      CURRENT_CANDIDATE_CODE+=${cs:digit:1}
    done
    if [[ ${CONFIG_STRATEGY:-smart} != random ]] && engine_owned_by_earlier; then
      engine_increment "$i"; continue
    fi
    CURRENT_PATTERN_INDEX=$i CURRENT_PATTERN_NAME=${E_NAMES[i]} CURRENT_PATTERN_MASK=${E_MASKS[i]}
    CURRENT_PATTERN_SPACE=${E_SPACES[i]} CURRENT_PATTERN_OFFSET=${E_OFFSETS[i]}
    return 0
  done
  return 1
}

engine_advance() {
  [[ ${CONFIG_STRATEGY:-smart} == random ]] || engine_increment "$CURRENT_PATTERN_INDEX"
  if [[ ${CONFIG_STRATEGY:-smart} == smart ]]; then
    E_QUOTA=$((E_QUOTA-1))
    if (( E_QUOTA == 0 )); then E_SLOT=$(((E_SLOT+1)%E_COUNT)); fi
  fi
}

engine_serialize() {
  local IFS=,
  STATE_POSITION_VECTOR="${E_DIGITS[*]}"
  STATE_EXHAUSTED_VECTOR="${E_DONE[*]}"
  STATE_PATTERN_OFFSETS="${E_OFFSETS[*]}"
  STATE_SCHEDULER="$E_SLOT,$E_QUOTA"
}

engine_restore() {
  local i j slot quota value base
  local -a digits exhausted offsets scheduler
  [[ ${STORED_ENGINE_CONFIG:-} == "$E_CONFIG" ]] || { engine_error 'State configuration differs; preserve state and restart explicitly with --start 0'; return 1; }
  [[ ${STORED_POSITION_VECTOR:-} =~ ^[0-9]+(,[0-9]+)*$ && ${STORED_EXHAUSTED_VECTOR:-} =~ ^[01](,[01])*$ && ${STORED_SCHEDULER:-} =~ ^[0-9]+,[0-9]+$ ]] || { engine_error 'Malformed state vectors'; return 1; }
  IFS=, read -r -a digits <<< "$STORED_POSITION_VECTOR"
  IFS=, read -r -a exhausted <<< "$STORED_EXHAUSTED_VECTOR"
  [[ ${STORED_PATTERN_OFFSETS:-} =~ ^(huge|[0-9]+)(,(huge|[0-9]+))*$ ]] || { engine_error 'Malformed state offsets'; return 1; }
  IFS=, read -r -a offsets <<< "$STORED_PATTERN_OFFSETS"
  IFS=, read -r -a scheduler <<< "$STORED_SCHEDULER"
  (( ${#digits[@]} == ${#E_DIGITS[@]} && ${#exhausted[@]} == E_COUNT && ${#offsets[@]} == E_COUNT )) || { engine_error 'State vector length mismatch'; return 1; }
  for ((i=0; i<${#digits[@]}; i++)); do
    engine_uint "${digits[i]}" && (( digits[i] < E_BASES[i] )) || { engine_error 'State digit outside base'; return 1; }
  done
  for ((i=0; i<E_COUNT; i++)); do
    [[ ${offsets[i]} == huge ]] || engine_uint "${offsets[i]}" || { engine_error 'Invalid state counter'; return 1; }
  done
  for ((i=0; i<E_COUNT; i++)); do
    value=0
    for ((j=E_STARTS[i]; j<E_STARTS[i]+E_LENGTHS[i]; j++)); do
      base=${E_BASES[j]}
      if [[ $value != huge ]]; then
        if (( value > (MAX_INTEGER_VALUE - digits[j]) / base )); then value=huge
        else value=$((value * base + digits[j])); fi
      fi
      if (( exhausted[i] && digits[j] != 0 )); then engine_error 'Exhausted vector has nonzero digits'; return 1; fi
    done
    if (( exhausted[i] )); then value=${E_SPACES[i]}; fi
    [[ ${offsets[i]} == "$value" ]] || { engine_error 'State offset and vector disagree'; return 1; }
    if [[ ${CONFIG_STRATEGY:-smart} == random ]] && [[ $value != 0 || ${exhausted[i]} != 0 ]]; then
      engine_error 'Invalid random state'; return 1
    fi
  done
  slot=${scheduler[0]}; quota=${scheduler[1]}
  engine_uint "$slot" && engine_uint "$quota" && (( slot < E_COUNT && quota <= E_WEIGHTS[slot] )) || { engine_error 'Invalid scheduler state'; return 1; }
  E_DIGITS=("${digits[@]}"); E_DONE=("${exhausted[@]}"); E_OFFSETS=("${offsets[@]}")
  E_SLOT=$slot E_QUOTA=$quota
}
