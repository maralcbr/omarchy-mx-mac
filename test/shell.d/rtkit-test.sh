#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
calls="$test_tmp/calls"
migration="$ROOT/migrations/1787552067.sh"
mkdir -p "$mock_bin"

cat >"$mock_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
exit "${OMARCHY_TEST_APPLE:-1}"
SH
cat >"$mock_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'pkg:%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
SH
chmod +x "$mock_bin"/*

OMARCHY_TEST_APPLE=0 OMARCHY_TEST_CALLS="$calls" PATH="$mock_bin:$PATH" \
  bash -euo pipefail "$migration"
grep -Fxq 'pkg:rtkit' "$calls" || fail "realtime migration installs rtkit on Apple Silicon"
pass "realtime migration installs the bounded scheduling provider"

: >"$calls"
OMARCHY_TEST_APPLE=1 OMARCHY_TEST_CALLS="$calls" PATH="$mock_bin:$PATH" \
  bash -euo pipefail "$migration"
[[ ! -s $calls ]] || fail "realtime migration leaves non-Apple systems unchanged"
pass "realtime migration is scoped to Apple Silicon"

grep -Fxq rtkit "$ROOT/install/omarchy-base-asahi.packages" || fail "fresh Asahi package closure includes rtkit"
grep -Fq 'networkmanager iwd rtkit' "$ROOT/test/vm/asahi-fresh/guest/verify" || fail "fresh-install VM requires rtkit"
grep -Fq '1787552067.sh)' "$ROOT/bin/omarchy-migrate" || fail "rtkit migration is reviewed for Asahi"
pass "fresh installs and upgrades require realtime scheduling support"
