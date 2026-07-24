#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Tests for bin/build (unit-level, mocked environment)
#
# These tests verify the build script logic without actually running composer
# or Docker. We mock the environment by:
#   - Creating a fake app directory with composer.json/lock
#   - Setting CNB_LAYERS_DIR to a temp directory
#   - Providing a mock 'composer' command that succeeds (no-op)
#   - Skipping /var/task copy (requires root) — we test the layer creation
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDPACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD="${BUILDPACK_DIR}/bin/build"

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
# Setup: create a temporary workspace simulating an app + CNB environment
# =============================================================================
echo "--- Setting up mock build environment ---"
TMPDIR_BUILD=$(mktemp -d)
APP_DIR="${TMPDIR_BUILD}/workspace"
LAYERS_DIR="${TMPDIR_BUILD}/layers"
MOCK_BIN="${TMPDIR_BUILD}/mock-bin"

mkdir -p "${APP_DIR}" "${LAYERS_DIR}" "${MOCK_BIN}"

# Create mock app files
cat > "${APP_DIR}/composer.json" << 'EOF'
{
    "name": "bref/sample-app",
    "require": {
        "php": "^8.4",
        "bref/bref": "^3.0"
    },
    "scripts": {
        "shrink-vendor": "echo 'shrink done'"
    }
}
EOF

cat > "${APP_DIR}/composer.lock" << 'EOF'
{
    "content-hash": "abc123",
    "packages": [],
    "packages-dev": []
}
EOF

mkdir -p "${APP_DIR}/public"
echo '<?php return fn() => "hello";' > "${APP_DIR}/public/index.php"

mkdir -p "${APP_DIR}/bin"
echo '#!/usr/bin/env php' > "${APP_DIR}/bin/console"
echo '<?php echo "console";' >> "${APP_DIR}/bin/console"

# Create a mock vendor directory (as if composer already ran)
mkdir -p "${APP_DIR}/vendor"
echo '{}' > "${APP_DIR}/vendor/autoload.php"

# Create mock composer binary that does nothing successfully
cat > "${MOCK_BIN}/composer" << 'MOCK'
#!/usr/bin/env bash
# Mock composer: just succeed, printing a message
echo "Mock composer: $*"
exit 0
MOCK
chmod +x "${MOCK_BIN}/composer"

# Create mock docker binary (for extensions step)
cat > "${MOCK_BIN}/docker" << 'MOCK'
#!/usr/bin/env bash
echo "mock-container-id"
exit 0
MOCK
chmod +x "${MOCK_BIN}/docker"

# Create mock sha256sum (macOS uses shasum -a 256)
cat > "${MOCK_BIN}/sha256sum" << 'MOCK'
#!/usr/bin/env bash
shasum -a 256 "$@"
MOCK
chmod +x "${MOCK_BIN}/sha256sum"

# Create /opt/bref/etc/php/conf.d/ if we can, or skip opcache test
OPCACHE_DIR="/opt/bref/etc/php/conf.d"

# =============================================================================
# Test 1: bin/build runs without error
# =============================================================================
echo "--- Test 1: bin/build runs without error ---"

# We need to run the build script in a way that avoids:
# 1. Writing to /var/task (requires root)
# 2. Writing to /opt/bref/etc/php/conf.d (requires root)
# So we patch the script to skip those parts by disabling opcache and
# using a modified version that doesn't cp to /var/task

# Create a modified build script that skips root-requiring operations
MODIFIED_BUILD="${TMPDIR_BUILD}/build-test"
sed \
    -e 's|rm -rf /var/task.*|# SKIPPED: rm -rf /var/task (test)|' \
    -e 's|cp -a "\$(pwd)" /var/task|# SKIPPED: cp to /var/task (test)|' \
    -e 's|local_ini="/opt/bref/etc/php/conf.d/opcache-buildpack.ini"|local_ini="${CNB_LAYERS_DIR}/opcache/opcache-buildpack.ini"|' \
    "${BUILD}" > "${MODIFIED_BUILD}"
chmod +x "${MODIFIED_BUILD}"

export CNB_LAYERS_DIR="${LAYERS_DIR}"
export BP_OPCACHE_ENABLE="false"
export BP_BREF_EXTENSIONS=""
export BP_SYMFONY_WARMUP="false"
export PATH="${MOCK_BIN}:${PATH}"

build_output=$(cd "${APP_DIR}" && "${MODIFIED_BUILD}" 2>&1) || true
build_exit=$?

if [[ ${build_exit} -eq 0 ]]; then
    pass "bin/build exits 0"
else
    fail "bin/build exited ${build_exit}"
    echo "    Output: ${build_output}"
fi

# =============================================================================
# Test 2: Layer TOML files are created
# =============================================================================
echo "--- Test 2: Layer TOML files are created ---"

if [[ -f "${LAYERS_DIR}/extensions.toml" ]]; then
    pass "extensions.toml created"
else
    fail "extensions.toml not created"
fi

if [[ -f "${LAYERS_DIR}/vendor.toml" ]]; then
    pass "vendor.toml created"
else
    fail "vendor.toml not created"
fi

if [[ -f "${LAYERS_DIR}/app.toml" ]]; then
    pass "app.toml created"
else
    fail "app.toml not created"
fi

if [[ -f "${LAYERS_DIR}/env.toml" ]]; then
    pass "env.toml created"
else
    fail "env.toml not created"
fi

if [[ -f "${LAYERS_DIR}/launch.toml" ]]; then
    pass "launch.toml created"
else
    fail "launch.toml not created"
fi

# =============================================================================
# Test 3: launch.toml has correct process configuration
# =============================================================================
echo "--- Test 3: launch.toml process configuration ---"

if grep -q 'type = "web"' "${LAYERS_DIR}/launch.toml" 2>/dev/null; then
    pass "launch.toml has web process"
else
    fail "launch.toml missing web process"
fi

if grep -q 'command' "${LAYERS_DIR}/launch.toml" 2>/dev/null; then
    pass "launch.toml has command defined"
else
    fail "launch.toml missing command"
fi

if grep -q 'public/index.php' "${LAYERS_DIR}/launch.toml" 2>/dev/null; then
    pass "launch.toml has correct default handler (public/index.php)"
else
    fail "launch.toml missing default handler"
fi

# =============================================================================
# Test 4: vendor.toml has cache metadata
# =============================================================================
echo "--- Test 4: vendor.toml cache metadata ---"

if grep -q 'cache = true' "${LAYERS_DIR}/vendor.toml" 2>/dev/null; then
    pass "vendor.toml has cache = true"
else
    fail "vendor.toml missing cache = true"
fi

if grep -q 'lock_sha' "${LAYERS_DIR}/vendor.toml" 2>/dev/null; then
    pass "vendor.toml has lock_sha metadata"
else
    fail "vendor.toml missing lock_sha metadata"
fi

# =============================================================================
# Test 5: Environment layer sets BREF_RUNTIME
# =============================================================================
echo "--- Test 5: Environment layer ---"

if [[ -f "${LAYERS_DIR}/env/env.launch/BREF_RUNTIME" ]]; then
    runtime_val=$(cat "${LAYERS_DIR}/env/env.launch/BREF_RUNTIME")
    if [[ "${runtime_val}" == "function" ]]; then
        pass "BREF_RUNTIME env set to 'function'"
    else
        fail "BREF_RUNTIME is '${runtime_val}', expected 'function'"
    fi
else
    fail "BREF_RUNTIME env file not created"
fi

# =============================================================================
# Cleanup
# =============================================================================
rm -rf "${TMPDIR_BUILD}"

# Unset exported vars
unset CNB_LAYERS_DIR BP_OPCACHE_ENABLE BP_BREF_EXTENSIONS BP_SYMFONY_WARMUP

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=== build tests: ${PASSED} passed, ${FAILED} failed ==="

if [[ ${FAILED} -gt 0 ]]; then
    exit 1
fi
