#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# Tests for bin/detect
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDPACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DETECT="${BUILDPACK_DIR}/bin/detect"

PASSED=0
FAILED=0

pass() {
    echo "  PASS: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo "  FAIL: $1"
    FAILED=$((FAILED + 1))
}

# =============================================================================
# Test 1: detect passes when composer.json has bref/bref
# =============================================================================
echo "--- Test 1: detect passes when composer.json has bref/bref ---"
TMPDIR_T1=$(mktemp -d)

cat > "${TMPDIR_T1}/composer.json" << 'EOF'
{
    "require": {
        "php": "^8.4",
        "bref/bref": "^3.0"
    }
}
EOF

export CNB_BUILD_PLAN_PATH="${TMPDIR_T1}/build-plan.toml"

set +e
(cd "${TMPDIR_T1}" && "${DETECT}") > /dev/null 2>&1
exit_code=$?
set -e

if [[ ${exit_code} -eq 0 ]]; then
    pass "detect exits 0 for app with bref/bref dependency"
else
    fail "detect exited ${exit_code}, expected 0"
fi

# Verify build plan was written
if [[ -f "${TMPDIR_T1}/build-plan.toml" ]]; then
    if grep -q 'name = "bref"' "${TMPDIR_T1}/build-plan.toml"; then
        pass "build plan contains bref provider"
    else
        fail "build plan missing bref provider"
    fi
else
    fail "build plan file was not created"
fi

rm -rf "${TMPDIR_T1}"

# =============================================================================
# Test 2: detect fails (exit 100) when no composer.json
# =============================================================================
echo "--- Test 2: detect fails when no composer.json ---"
TMPDIR_T2=$(mktemp -d)

export CNB_BUILD_PLAN_PATH="${TMPDIR_T2}/build-plan.toml"

set +e
(cd "${TMPDIR_T2}" && "${DETECT}") > /dev/null 2>&1
exit_code=$?
set -e

if [[ ${exit_code} -eq 100 ]]; then
    pass "detect exits 100 when no composer.json"
else
    fail "detect exited ${exit_code}, expected 100"
fi

rm -rf "${TMPDIR_T2}"

# =============================================================================
# Test 3: detect fails when composer.json has no bref dependency
# =============================================================================
echo "--- Test 3: detect fails when composer.json has no bref dependency ---"
TMPDIR_T3=$(mktemp -d)

cat > "${TMPDIR_T3}/composer.json" << 'EOF'
{
    "require": {
        "php": "^8.4",
        "laravel/framework": "^11.0"
    }
}
EOF

export CNB_BUILD_PLAN_PATH="${TMPDIR_T3}/build-plan.toml"

set +e
(cd "${TMPDIR_T3}" && "${DETECT}") > /dev/null 2>&1
exit_code=$?
set -e

if [[ ${exit_code} -eq 100 ]]; then
    pass "detect exits 100 when no bref/bref dependency"
else
    fail "detect exited ${exit_code}, expected 100"
fi

rm -rf "${TMPDIR_T3}"

# =============================================================================
# Test 4: detect passes when .bref marker file exists (even without bref dep)
# =============================================================================
echo "--- Test 4: detect passes when .bref marker file exists ---"
TMPDIR_T4=$(mktemp -d)

cat > "${TMPDIR_T4}/composer.json" << 'EOF'
{
    "require": {
        "php": "^8.4"
    }
}
EOF

touch "${TMPDIR_T4}/.bref"

export CNB_BUILD_PLAN_PATH="${TMPDIR_T4}/build-plan.toml"

set +e
(cd "${TMPDIR_T4}" && "${DETECT}") > /dev/null 2>&1
exit_code=$?
set -e

if [[ ${exit_code} -eq 0 ]]; then
    pass "detect exits 0 when .bref marker file exists"
else
    fail "detect exited ${exit_code}, expected 0"
fi

rm -rf "${TMPDIR_T4}"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=== detect tests: ${PASSED} passed, ${FAILED} failed ==="

if [[ ${FAILED} -gt 0 ]]; then
    exit 1
fi
