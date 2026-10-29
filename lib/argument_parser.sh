#!/usr/bin/env bash
# ==============================================================================
# argument_parser.sh - CLI argument parsing, input validation, and help guide
# ==============================================================================

[[ -n "${ARGUMENT_PARSER_INCLUDED:-}" ]] && return 0
readonly ARGUMENT_PARSER_INCLUDED=1

function display_usage_guide {
  printf "%s%sFastboot Bootloader Unlock Console%s\n\n" "${COLOR_CYAN}" "${STYLE_BOLD}" "${STYLE_RESET}"
  printf "%sUsage:%s %s [options]\n\n" "${STYLE_BOLD}" "${STYLE_RESET}" "$0"

  printf "%sCore Options:%s\n" "${STYLE_BOLD}" "${STYLE_RESET}"
  printf "  %s-h, --help%s                 Display this help guide and exit\n" "${COLOR_CYAN}" "${STYLE_RESET}"
  printf "  %s-d, --device <id>%s          Target fastboot device identifier (default: auto-detect)\n" "${COLOR_CYAN}" "${STYLE_RESET}"
  printf "  %s-c, --command <profile>%s    Command profile: auto, flashing-unlock, flashing-unlock-code,\n" "${COLOR_CYAN}" "${STYLE_RESET}"
  printf "                             oem-unlock-code, oem-unlock, oem-unlock-go (default: auto)\n"
  printf "  %s--strategy <strategy>%s      Candidate order: smart, sequential, random (default: smart)\n" "${COLOR_CYAN}" "${STYLE_RESET}"
  printf "  %s-s, --start <offset>%s       Resume or start from numeric offset (default: 0)\n\n" "${COLOR_CYAN}" "${STYLE_RESET}"

  printf "%sPattern DSL Options:%s\n" "${STYLE_BOLD}" "${STYLE_RESET}"
  printf "  %s-p, --pattern <mask>%s       Apply single pattern mask, e.g. 'X{20}', 'A{19}9', '9{6}'\n" "${COLOR_CYAN}" "${STYLE_RESET}"
  printf "  %s--patterns <schedule>%s      Semicolon-delimited list: name:mask:weight;name:mask:weight\n" "${COLOR_CYAN}" "${STYLE_RESET}"
  printf "  %s--list-patterns%s            Display experimental key profiles\n\n" "${COLOR_CYAN}" "${STYLE_RESET}"

  printf '  --key-profile <id>          Select an experimental key format\n'
  printf '  --allow-experimental        Enable an explicitly selected experimental profile\n'
  printf '  --list-key-profiles          List experimental profiles (alias: --list-patterns)\n'
  printf "  --known-positions <spec>    Fixed zero-based positions, e.g. '0:A;4:7'\n"
  printf '  --preview <count>            Print candidates without fastboot or state I/O\n'
  printf '  random samples with replacement; weights express scheduling preference only.\n\n'
  printf "%sLegacy Options:%s\n" "${STYLE_BOLD}" "${STYLE_RESET}"
  printf "  %s-t, --type <type>%s          Legacy charset alias: moto, alpha, numeric (default: moto)\n" "${COLOR_CYAN}" "${STYLE_RESET}"
  printf "  %s-l, --length <num>%s         Code length for generic search (default: 20)\n\n" "${COLOR_CYAN}" "${STYLE_RESET}"

  printf "%sPattern DSL Tokens:%s\n" "${STYLE_BOLD}" "${STYLE_RESET}"
  printf "  %s9%s   Numeric digit             0-9\n" "${COLOR_YELLOW}" "${STYLE_RESET}"
  printf "  %sA%s   Uppercase alphabetic      A-Z\n" "${COLOR_YELLOW}" "${STYLE_RESET}"
  printf "  %sa%s   Lowercase alphabetic      a-z\n" "${COLOR_YELLOW}" "${STYLE_RESET}"
  printf "  %sX%s   Uppercase alphanumeric    A-Z, 0-9\n" "${COLOR_YELLOW}" "${STYLE_RESET}"
  printf "  %sx%s   Mixed alphanumeric        A-Z, a-z, 0-9\n" "${COLOR_YELLOW}" "${STYLE_RESET}"
  printf "  %sH%s   Uppercase hexadecimal     0-9, A-F\n" "${COLOR_YELLOW}" "${STYLE_RESET}"
  printf "  %sh%s   Lowercase hexadecimal     0-9, a-f\n" "${COLOR_YELLOW}" "${STYLE_RESET}"
  printf "  %s?%s   Active charset symbol     Selected by --type\n" "${COLOR_YELLOW}" "${STYLE_RESET}"
  printf "  %s{n}%s Repeat multiplier         e.g. A{4}9A{15}, X{20}, 9{6}\n" "${COLOR_YELLOW}" "${STYLE_RESET}"
  printf "  %s*%s   Literal characters        Other characters preserved; colon/semicolon reserved (e.g. XXXX-XXXX)\n\n" "${COLOR_YELLOW}" "${STYLE_RESET}"

  printf "%sExamples:%s\n" "${STYLE_BOLD}" "${STYLE_RESET}"
  printf "  %s --command auto --strategy smart\n" "$0"
  printf "  %s --pattern 'X{20}' --command oem-unlock-code\n" "$0"
  printf "  %s --patterns 'digits:9{2}:2;hex:H{2}:1' --preview 20\n" "$0"
}

function display_builtin_patterns {
  printf "%s%sBuilt-in pattern profiles (experimental; explicit opt-in required):%s\n\n" "${COLOR_CYAN}" "${STYLE_BOLD}" "${STYLE_RESET}"
  printf "  %-22s %-12s %-8s %s\n" "PROFILE NAME" "MASK" "WEIGHT" "DESCRIPTION"
  printf "  %-22s %-12s %-8s %s\n" "------------" "----" "------" "-----------"

  IFS=';' read -ra entries <<< "${BUILTIN_PATTERN_PROFILES}"
  for entry in "${entries[@]}"; do
    IFS=':' read -r name mask weight desc <<< "${entry}"
    printf "  %-22s %-12s %-8s %s\n" "${name}" "${mask}" "${weight}" "${desc}"
  done
}

function validate_numeric_64bit {
  local num=$1
  local max_64="9223372036854775807"
  if [[ ! "${num}" =~ ^[0-9]+$ ]]; then return 1; fi
  if (( ${#num} > ${#max_64} )); then return 1; fi
  # Compare strings after checking length, before any overflowing arithmetic.
  # shellcheck disable=SC2071
  if (( ${#num} == ${#max_64} )) && [[ "${num}" > "${max_64}" ]]; then return 1; fi
  [[ $num == 0 || $num != 0* ]] || return 1
  return 0
}

function parse_cli_arguments {
  CLI_KEY_PROFILE="" CLI_ALLOW_EXPERIMENTAL=0 CLI_KNOWN_POSITIONS="" CLI_PREVIEW=""
  CLI_DEVICE_OVERRIDE=""
  CLI_CODE_TYPE=""
  CLI_CODE_LENGTH=""
  CLI_START_OFFSET=""
  CLI_SINGLE_PATTERN=""
  CLI_PATTERN_SCHEDULE=""
  CLI_STRATEGY=""
  CLI_COMMAND_PROFILE=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        display_usage_guide
        exit "${EXIT_SUCCESS}"
        ;;
      --list-patterns|--list-key-profiles)
        display_builtin_patterns
        exit "${EXIT_SUCCESS}"
        ;;
      --allow-experimental) CLI_ALLOW_EXPERIMENTAL=1; shift ;;
      --key-profile|--known-positions|--preview)
        [[ -n ${2:-} ]] || { ui_fail "Missing value for $1"; exit 1; }
        case $1 in
          --key-profile) CLI_KEY_PROFILE=$2 ;;
          --known-positions) CLI_KNOWN_POSITIONS=$2 ;;
          --preview)
            engine_uint "$2" || { ui_fail 'Invalid preview count'; exit 1; }
            CLI_PREVIEW=$2 ;;
        esac
        shift 2 ;;
      -d|--device)
        [[ -z "${2:-}" ]] && { ui_fail "Missing value for --device"; exit "${EXIT_GENERAL_ERROR}"; }
        CLI_DEVICE_OVERRIDE="$2"; shift 2 ;;
      -t|--type)
        [[ -z "${2:-}" ]] && { ui_fail "Missing value for --type"; exit "${EXIT_GENERAL_ERROR}"; }
        case "$2" in
          numeric|alpha|moto) CLI_CODE_TYPE="$2" ;;
          *) ui_fail "Invalid --type '$2'. Allowed values: numeric, alpha, moto."; exit "${EXIT_GENERAL_ERROR}" ;;
        esac
        shift 2 ;;
      -l|--length)
        [[ -z "${2:-}" ]] && { ui_fail "Missing value for --length"; exit "${EXIT_GENERAL_ERROR}"; }
        if ! validate_numeric_64bit "$2" || [[ "$2" -le 0 || "$2" -gt 4096 ]]; then
          ui_fail "Invalid --length '$2'. Must be a positive integer between 1 and 4096."
          exit "${EXIT_GENERAL_ERROR}";
        fi
        CLI_CODE_LENGTH="$2"; shift 2 ;;
      -s|--start)
        [[ -z "${2:-}" ]] && { ui_fail "Missing value for --start"; exit "${EXIT_GENERAL_ERROR}"; }
        if ! validate_numeric_64bit "$2"; then
          ui_fail "Invalid --start '$2'. Must be a non-negative 64-bit integer offset."
          exit "${EXIT_GENERAL_ERROR}";
        fi
        CLI_START_OFFSET="$2"; shift 2 ;;
      -p|--pattern)
        [[ -z "${2:-}" ]] && { ui_fail "Missing value for --pattern"; exit "${EXIT_GENERAL_ERROR}"; }
        CLI_SINGLE_PATTERN="$2"; shift 2 ;;
      --patterns)
        [[ -z "${2:-}" ]] && { ui_fail "Missing value for --patterns"; exit "${EXIT_GENERAL_ERROR}"; }
        CLI_PATTERN_SCHEDULE="$2"; shift 2 ;;
      --strategy)
        [[ -z "${2:-}" ]] && { ui_fail "Missing value for --strategy"; exit "${EXIT_GENERAL_ERROR}"; }
        case "$2" in
          smart|sequential|random) CLI_STRATEGY="$2" ;;
          *) ui_fail "Invalid --strategy '$2'. Allowed values: smart, sequential, random."; exit "${EXIT_GENERAL_ERROR}" ;;
        esac
        shift 2 ;;
      -c|--command)
        [[ -z "${2:-}" ]] && { ui_fail "Missing value for --command"; exit "${EXIT_GENERAL_ERROR}"; }
        case "$2" in
          auto|flashing-unlock|flashing-unlock-code|oem-unlock-code|oem-unlock|oem-unlock-go) CLI_COMMAND_PROFILE="$2" ;;
          *) ui_fail "Invalid --command '$2'. Allowed values: auto, flashing-unlock, flashing-unlock-code, oem-unlock-code, oem-unlock, oem-unlock-go."; exit "${EXIT_GENERAL_ERROR}" ;;
        esac
        shift 2 ;;
      *)
        ui_fail "Unknown argument: $1"
        printf "Run '%s --help' for available options.\n" "$0"
        exit "${EXIT_GENERAL_ERROR}"
        ;;
    esac
  done
  if [[ -n $CLI_SINGLE_PATTERN && -n $CLI_PATTERN_SCHEDULE ]] ||
     [[ -n $CLI_KEY_PROFILE && ( -n $CLI_SINGLE_PATTERN || -n $CLI_PATTERN_SCHEDULE ) ]]; then
    ui_fail 'Choose only one of --pattern, --patterns, --key-profile'; exit 1
  fi
}
