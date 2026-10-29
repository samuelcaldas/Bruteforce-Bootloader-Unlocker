#!/usr/bin/env bash
# ==============================================================================
# constants.sh - System constants, charsets, exit codes, and builtin profiles
# ==============================================================================

# Prevent duplicate inclusion
[[ -n "${CONSTANTS_INCLUDED:-}" ]] && return 0
readonly CONSTANTS_INCLUDED=1

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_TERMINAL_FASTBOOT_ERROR=2
readonly EXIT_INTERRUPTED=130

# Numeric boundary
readonly MAX_INTEGER_VALUE=9223372036854775807

# Defaults
readonly DEFAULT_CODE_LENGTH=20
readonly DEFAULT_STRATEGY="smart"
readonly DEFAULT_COMMAND_PROFILE="auto"
readonly DEFAULT_CODE_TYPE="moto"
readonly DEFAULT_UPDATE_INTERVAL=10
readonly DEFAULT_PERSIST_INTERVAL=100

# Character Sets
readonly CHARSET_DIGITS="0123456789"
readonly CHARSET_UPPER_ALPHA="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
readonly CHARSET_LOWER_ALPHA="abcdefghijklmnopqrstuvwxyz"
readonly CHARSET_UPPER_ALPHANUMERIC="ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
readonly CHARSET_MIXED_ALPHANUMERIC="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
readonly CHARSET_HEX_UPPER="0123456789ABCDEF"
readonly CHARSET_HEX_LOWER="0123456789abcdef"

# Experimental hypotheses only; never selected from device brand automatically.
readonly BUILTIN_PATTERN_PROFILES="motorola-20:X{20}:1:Experimental Motorola historical alphabet;sony-xperia-16:H{16}:1:Experimental Xperia format;huawei-honor-legacy-16:9{16}:1:Experimental historical Huawei Honor format"
