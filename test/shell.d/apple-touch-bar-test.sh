#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

helper="$ROOT/bin/omarchy-hw-apple-touch-bar"
leaf="$ROOT/install/hardware/apple/touch-bar.sh"
migration="$ROOT/migrations/1789480988.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

proc_root="$test_tmp/proc"
mkdir -p "$proc_root/device-tree"

for board in j293 j493; do
  printf 'apple,%s\0apple,t8103\0apple,arm-platform\0' "$board" >"$proc_root/device-tree/compatible"
  OMARCHY_PROC_ROOT="$proc_root" "$helper" || fail "the $board MacBook Pro is detected as having a Touch Bar"
done
pass "the 13-inch M1 and M2 MacBook Pros are detected as having a Touch Bar"

for compatible in 'apple,j314s\0apple,t6000\0apple,arm-platform\0' 'apple,j2930\0apple,arm-platform\0'; do
  printf "$compatible" >"$proc_root/device-tree/compatible"
  if OMARCHY_PROC_ROOT="$proc_root" "$helper"; then
    fail "an Apple Silicon Mac without a Touch Bar is rejected" "$compatible"
  fi
done
rm "$proc_root/device-tree/compatible"
if OMARCHY_PROC_ROOT="$proc_root" "$helper"; then
  fail "a machine without a device tree is rejected"
fi
pass "other Macs and machines without a device tree are rejected"

grep -Fxq 'run_logged "$OMARCHY_INSTALL/hardware/apple/touch-bar.sh"' "$ROOT/install/hardware/all.sh" ||
  fail "the Touch Bar daemon is installed during hardware setup"
grep -Fq "$(basename "$migration")) printf 'run" "$ROOT/bin/omarchy-migrate" ||
  fail "the Touch Bar migration runs under the Asahi migration policy"
pass "hardware setup and the Asahi migration policy include the Touch Bar daemon"

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-hw-apple-touch-bar" <<'SH'
#!/bin/bash

[[ ${TOUCH_BAR:-0} == "1" ]]
SH

cat >"$stub_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash

[[ ${TINY_DFR_PRESENT:-0} == "1" ]]
SH

for command_name in omarchy-pkg-add omarchy-state; do
  cat >"$stub_bin/$command_name" <<'SH'
#!/bin/bash

printf '%s' "$(basename "$0")" >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH
done

chmod +x "$stub_bin"/*

run_leaf() {
  : >"$calls"
  TOUCH_BAR="$1" TEST_LOG="$calls" PATH="$stub_bin:$PATH" \
    bash -eE -c 'source "$1"' bash "$leaf" >/dev/null
}

run_migration() {
  : >"$calls"
  TOUCH_BAR="$1" TINY_DFR_PRESENT="$2" TEST_LOG="$calls" PATH="$stub_bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null
}

run_leaf 1
[[ $(<"$calls") == $'omarchy-pkg-add\ttiny-dfr' ]] ||
  fail "a Touch Bar Mac gets tiny-dfr on install" "$(<"$calls")"
run_leaf 0
[[ ! -s $calls ]] || fail "other machines install nothing" "$(<"$calls")"
pass "new installs add tiny-dfr only on Touch Bar Macs"

run_migration 1 0
[[ $(<"$calls") == $'omarchy-pkg-add\ttiny-dfr\nomarchy-state\tset\treboot-required' ]] ||
  fail "an installed Touch Bar Mac gets tiny-dfr and a reboot prompt" "$(<"$calls")"
run_migration 1 1
[[ ! -s $calls ]] || fail "a Mac that already has tiny-dfr is left alone" "$(<"$calls")"
run_migration 0 0
[[ ! -s $calls ]] || fail "other machines are left alone" "$(<"$calls")"
pass "the migration adds tiny-dfr only where it is missing on Touch Bar Macs"
