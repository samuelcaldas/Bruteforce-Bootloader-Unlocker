#!/usr/bin/env bash
# ==============================================================================
# run_all_tests.sh - Master test runner (syntax verification, unit, integration)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Global counters
SYNTAX_PASS=0
SYNTAX_FAIL=0
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0
FILES_PASSED=0
FILES_FAILED=0
START_TIME=$(date +%s)

# Filter argument
FILTER="${1:-${TEST_FILTER:-}}"

# Styling setup
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
  C_CYAN="$(printf '\033[36m')"
  C_GREEN="$(printf '\033[32m')"
  C_YELLOW="$(printf '\033[33m')"
  C_RED="$(printf '\033[31m')"
  C_BOLD="$(printf '\033[1m')"
  C_RESET="$(printf '\033[0m')"
else
  C_CYAN=""
  C_GREEN=""
  C_YELLOW=""
  C_RED=""
  C_BOLD=""
  C_RESET=""
fi

printf "%s%s======================================================================%s\n" "${C_CYAN}" "${C_BOLD}" "${C_RESET}"
printf "%s%s Fastboot Bootloader Unlocker - Automated Test Suite%s\n" "${C_CYAN}" "${C_BOLD}" "${C_RESET}"
printf "%s%s======================================================================%s\n\n" "${C_CYAN}" "${C_BOLD}" "${C_RESET}"

# ------------------------------------------------------------------------------
# Phase 1: Static Bash Syntax Validation (bash -n)
# ------------------------------------------------------------------------------
printf "%s[PHASE 1]%s Verifying Bash syntax across all project scripts...\n" "${C_CYAN}" "${C_RESET}"

SCRIPTS_TO_CHECK=(
  "${REPO_ROOT}/bootloader_unlocker"
  "${REPO_ROOT}/lib/constants.sh"
  "${REPO_ROOT}/lib/terminal_ui.sh"
  "${REPO_ROOT}/lib/device_storage.sh"
  "${REPO_ROOT}/lib/pattern_engine.sh"
  "${REPO_ROOT}/lib/candidate_engine.sh"
  "${REPO_ROOT}/lib/runtime_config.sh"
  "${REPO_ROOT}/lib/fastboot_client.sh"
  "${REPO_ROOT}/lib/argument_parser.sh"
  "${REPO_ROOT}/lib/unlock_runner.sh"
  "${REPO_ROOT}/tests/test_helper.sh"
  "${REPO_ROOT}/tests/run_all_tests.sh"
)

for f in "${REPO_ROOT}"/tests/unit/test_*.sh "${REPO_ROOT}"/tests/integration/test_*.sh; do
  [[ -f "${f}" ]] && SCRIPTS_TO_CHECK+=("${f}")
done

for script in "${SCRIPTS_TO_CHECK[@]}"; do
  rel_path="${script#"${REPO_ROOT}/"}"
  if bash -n "${script}" 2>/dev/null; then
    SYNTAX_PASS=$(( SYNTAX_PASS + 1 ))
  else
    SYNTAX_FAIL=$(( SYNTAX_FAIL + 1 ))
    printf "  %s[FAIL]%s %s has syntax errors\n" "${C_RED}" "${C_RESET}" "${rel_path}"
  fi
done

if (( SYNTAX_FAIL > 0 )); then
  printf "\n%s[ERROR]%s Syntax verification failed with %d error(s). Aborting test run.\n" "${C_RED}" "${C_RESET}" "${SYNTAX_FAIL}"
  exit 1
fi

printf "  %s[OK]%s Syntax check passed for all %d script files.\n\n" "${C_GREEN}" "${C_RESET}" "${SYNTAX_PASS}"

# ------------------------------------------------------------------------------
# Phase 2: Unit & Integration Test Suites
# ------------------------------------------------------------------------------
printf "%s[PHASE 2]%s Executing unit and integration suites...\n" "${C_CYAN}" "${C_RESET}"

TEST_FILES=(
  "${REPO_ROOT}/tests/unit/test_constants.sh"
  "${REPO_ROOT}/tests/unit/test_terminal_ui.sh"
  "${REPO_ROOT}/tests/unit/test_device_storage.sh"
  "${REPO_ROOT}/tests/unit/test_pattern_engine.sh"
  "${REPO_ROOT}/tests/unit/test_candidate_engine.sh"
  "${REPO_ROOT}/tests/integration/test_candidate_cli.sh"
  "${REPO_ROOT}/tests/unit/test_fastboot_client.sh"
  "${REPO_ROOT}/tests/unit/test_argument_parser.sh"
  "${REPO_ROOT}/tests/unit/test_unlock_runner.sh"
  "${REPO_ROOT}/tests/integration/test_cli_workflow.sh"
)

for test_file in "${TEST_FILES[@]}"; do
  rel_name="${test_file#"${REPO_ROOT}/"}"

  # If filter provided and doesn't match file name or test path, pass filter to runner
  if [[ -n "${FILTER}" && "${rel_name}" != *"${FILTER}"* ]]; then
    export TEST_FILTER="${FILTER}"
  else
    unset TEST_FILTER
  fi

  printf "\n%s▶ Running %s%s\n" "${C_BOLD}" "${rel_name}" "${C_RESET}"

  output_f=$(mktemp)
  set +e
  bash "${test_file}" > "${output_f}" 2>&1
  status=$?
  set -e

  cat "${output_f}"

  # Parse summary line: # TEST_SUMMARY total=X passed=Y failed=Z skipped=W duration=Ts
  summary_line=$(grep "^# TEST_SUMMARY" "${output_f}" | tail -n 1 || true)
  if [[ -n "${summary_line}" ]]; then
    total=$(echo "${summary_line}" | sed -n 's/.*total=\([0-9]*\).*/\1/p')
    passed=$(echo "${summary_line}" | sed -n 's/.*passed=\([0-9]*\).*/\1/p')
    failed=$(echo "${summary_line}" | sed -n 's/.*failed=\([0-9]*\).*/\1/p')
    skipped=$(echo "${summary_line}" | sed -n 's/.*skipped=\([0-9]*\).*/\1/p')

    TOTAL_TESTS=$(( TOTAL_TESTS + ${total:-0} ))
    TOTAL_PASSED=$(( TOTAL_PASSED + ${passed:-0} ))
    TOTAL_FAILED=$(( TOTAL_FAILED + ${failed:-0} ))
    TOTAL_SKIPPED=$(( TOTAL_SKIPPED + ${skipped:-0} ))
  fi

  rm -f "${output_f}"

  if [[ ${status} -eq 0 ]]; then
    FILES_PASSED=$(( FILES_PASSED + 1 ))
  else
    FILES_FAILED=$(( FILES_FAILED + 1 ))
  fi
done

# ------------------------------------------------------------------------------
# Phase 3: Final Consolidated Report
# ------------------------------------------------------------------------------
DURATION=$(( $(date +%s) - START_TIME ))

printf "\n%s%s======================================================================%s\n" "${C_CYAN}" "${C_BOLD}" "${C_RESET}"
printf "%s%s Final Test Summary%s\n" "${C_CYAN}" "${C_BOLD}" "${C_RESET}"
printf "%s%s======================================================================%s\n" "${C_CYAN}" "${C_BOLD}" "${C_RESET}"
printf "  Syntax:   %s%d passed%s, %d failed\n" "${C_GREEN}" "${SYNTAX_PASS}" "${C_RESET}" "${SYNTAX_FAIL}"
printf "  Tests:    %s%d passed%s, %s%d failed%s, %s%d skipped%s\n" \
  "${C_GREEN}" "${TOTAL_PASSED}" "${C_RESET}" \
  "${C_RED}" "${TOTAL_FAILED}" "${C_RESET}" \
  "${C_YELLOW}" "${TOTAL_SKIPPED}" "${C_RESET}"
printf "  Files:    %s%d passed%s, %s%d failed%s\n" \
  "${C_GREEN}" "${FILES_PASSED}" "${C_RESET}" \
  "${C_RED}" "${FILES_FAILED}" "${C_RESET}"
printf "  Duration: %ds\n" "${DURATION}"

if (( FILES_FAILED > 0 || TOTAL_FAILED > 0 || SYNTAX_FAIL > 0 )); then
  printf "\n%s%sRESULT: OVERALL FAILURE%s\n\n" "${C_RED}" "${C_BOLD}" "${C_RESET}"
  exit 1
else
  printf "\n%s%sRESULT: ALL TESTS PASSED%s\n\n" "${C_GREEN}" "${C_BOLD}" "${C_RESET}"
  exit 0
fi
