#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# Test Runner for Bref Buildpack
#
# Runs all test scripts and reports overall pass/fail.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

run_suite() {
    local test_file="$1"
    local test_name
    test_name=$(basename "${test_file}" .sh)

    echo ""
    echo "============================================="
    echo "Running: ${test_name}"
    echo "============================================="

    TOTAL_SUITES=$((TOTAL_SUITES + 1))

    if bash "${test_file}"; then
        PASSED_SUITES=$((PASSED_SUITES + 1))
    else
        FAILED_SUITES=$((FAILED_SUITES + 1))
    fi
}

# Run all test suites
run_suite "${SCRIPT_DIR}/test_detect.sh"
run_suite "${SCRIPT_DIR}/test_build.sh"

# =============================================================================
# Overall Summary
# =============================================================================
echo ""
echo "============================================="
echo "OVERALL RESULTS"
echo "============================================="
echo "  Suites run:    ${TOTAL_SUITES}"
echo "  Suites passed: ${PASSED_SUITES}"
echo "  Suites failed: ${FAILED_SUITES}"
echo "============================================="

if [[ ${FAILED_SUITES} -gt 0 ]]; then
    echo "RESULT: FAIL"
    exit 1
else
    echo "RESULT: PASS"
    exit 0
fi
