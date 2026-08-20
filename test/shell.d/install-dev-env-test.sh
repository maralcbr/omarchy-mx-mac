#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"

cat >"$test_tmp/bin/curl" <<'SH'
#!/bin/bash
cat <<'INSTALLER'
printf '%s\n' "${RUSTUP_USE_CURL:-unset}" >"$OMARCHY_TEST_RUSTUP_ENV"
INSTALLER
SH
cat >"$test_tmp/bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_APPLE_SILICON:-0} == "1" ]]
SH
chmod +x "$test_tmp/bin"/*

export PATH="$test_tmp/bin:$PATH"
export OMARCHY_TEST_RUSTUP_ENV="$test_tmp/rustup-env"

OMARCHY_TEST_APPLE_SILICON=1 "$ROOT/bin/omarchy-install-dev-env" rust >/dev/null
[[ $(<"$OMARCHY_TEST_RUSTUP_ENV") == "1" ]] || fail "Rust uses the curl backend on Apple Silicon"
pass "Rust uses the curl backend on Apple Silicon"

OMARCHY_TEST_APPLE_SILICON=0 "$ROOT/bin/omarchy-install-dev-env" rust >/dev/null
[[ $(<"$OMARCHY_TEST_RUSTUP_ENV") == "unset" ]] || fail "Rust keeps the supported backend on other hardware"
pass "Rust keeps the supported backend on other hardware"
