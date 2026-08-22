#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'pkg:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
exit 0
SH

cat >"$mock_bin/omarchy-pkg-available" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_OMAZED:-0} == 1 ]]
SH

cat >"$mock_bin/omazed" <<'SH'
#!/bin/bash
printf 'omazed:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
printf 'launch:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

chmod +x "$mock_bin"/*

export PATH="$mock_bin:$PATH"
export OMARCHY_TEST_LOG="$test_tmp/zed.log"

wait_for_log() {
  local expected="$1"

  for ((attempt = 0; attempt < 100; attempt++)); do
    grep -Fxq "$expected" "$OMARCHY_TEST_LOG" && return 0
    sleep 0.01
  done

  return 1
}

: >"$OMARCHY_TEST_LOG"
OMARCHY_TEST_OMAZED=0 bash "$ROOT/bin/omarchy-install-editor-zed" >"$test_tmp/skip.out"

grep -Fqx 'pkg:zed' "$OMARCHY_TEST_LOG" || fail "Zed installer installs zed without omazed"
if grep -Fq 'pkg:omazed' "$OMARCHY_TEST_LOG"; then
  fail "Zed installer skips unpublished omazed"
fi
if grep -Fq 'omazed:' "$OMARCHY_TEST_LOG"; then
  fail "Zed installer does not run omazed when it is unpublished"
fi
grep -Fq 'omazed is not available for this architecture' "$test_tmp/skip.out" ||
  fail "Zed installer explains the skipped theme helper"
wait_for_log 'launch:uwsm-app -- gtk-launch dev.zed.Zed' ||
  fail "Zed installer still launches Zed without omazed"
pass "Zed installer skips unpublished omazed and still launches Zed"

: >"$OMARCHY_TEST_LOG"
OMARCHY_TEST_OMAZED=1 bash "$ROOT/bin/omarchy-install-editor-zed" >"$test_tmp/setup.out"

grep -Fqx 'pkg:zed' "$OMARCHY_TEST_LOG" || fail "Zed installer installs zed before omazed"
grep -Fqx 'pkg:omazed' "$OMARCHY_TEST_LOG" || fail "Zed installer installs omazed when it is published"
grep -Fqx 'omazed:setup' "$OMARCHY_TEST_LOG" || fail "Zed installer runs omazed setup when it is published"
if grep -Fq 'omazed is not available' "$test_tmp/setup.out"; then
  fail "Zed installer does not skip omazed when it is published"
fi
pass "Zed installer configures omazed when the package is published"
