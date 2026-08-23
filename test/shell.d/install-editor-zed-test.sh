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
[[ ${OMARCHY_TEST_PKG_FAIL:-0} == 0 ]]
SH
cat >"$mock_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_OMAZED_INSTALLED:-0} == 1 ]]
SH
cat >"$mock_bin/omarchy-pkg-available" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_OMAZED_AVAILABLE:-0} == 1 ]]
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

wait_for_launch() {
  for ((attempt = 0; attempt < 100; attempt++)); do
    grep -Fq 'launch:' "$OMARCHY_TEST_LOG" && return 0
    sleep 0.01
  done
  return 1
}

: >"$OMARCHY_TEST_LOG"
OMARCHY_TEST_OMAZED_AVAILABLE=0 bash "$ROOT/bin/omarchy-install-editor-zed" >"$test_tmp/skip.out"
grep -Fqx 'pkg:zed' "$OMARCHY_TEST_LOG" || fail 'Zed installer installs zed'
! grep -Fq 'pkg:omazed' "$OMARCHY_TEST_LOG" || fail 'Zed installer skips unavailable omazed'
grep -Fq 'omazed is not available for this architecture' "$test_tmp/skip.out" || fail 'Zed installer explains skipped theme setup'
wait_for_launch || fail 'Zed installer launches after installing without omazed'
pass 'Zed installer skips unavailable omazed'

: >"$OMARCHY_TEST_LOG"
OMARCHY_TEST_OMAZED_INSTALLED=1 OMARCHY_TEST_OMAZED_AVAILABLE=0 bash "$ROOT/bin/omarchy-install-editor-zed" >/dev/null
grep -Fqx 'omazed:setup' "$OMARCHY_TEST_LOG" || fail 'Zed installer configures an installed omazed package'
wait_for_launch || fail 'Zed installer launches after configuring installed omazed'
pass 'Zed installer configures an installed omazed package'

: >"$OMARCHY_TEST_LOG"
if OMARCHY_TEST_PKG_FAIL=1 bash "$ROOT/bin/omarchy-install-editor-zed" >/dev/null 2>&1; then
  fail 'Zed installer returns failure when zed fails to install'
fi
! grep -Fq 'launch:' "$OMARCHY_TEST_LOG" || fail 'Zed installer does not launch after package failure'
pass 'Zed installer propagates package installation failures'
