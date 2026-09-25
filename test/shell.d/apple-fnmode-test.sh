#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/fix-fkeys.sh"
migration="$ROOT/migrations/1790305681.sh"
all="$ROOT/install/hardware/all.sh"

grep -q 'hardware/fix-fkeys.sh' "$all" || fail "hardware setup runs the F-key leaf"
pass "hardware setup runs the F-key leaf"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
conf="$test_tmp/etc/modprobe.d/hid_apple.conf"
param="$test_tmp/sys/fnmode"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
[[ ${APPLE_SILICON:-0} == 1 ]]
SH
cat >"$stub_bin/omarchy-mac-limine-active" <<'SH'
#!/bin/bash
[[ ${LIMINE:-0} == 1 ]]
SH
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH
# The rebuild sees the file as it is while the image is built.
for tool in mkinitcpio omarchy-mac-boot-update; do
  cat >"$stub_bin/$tool" <<'SH'
#!/bin/bash
printf '%s' "${0##*/}" >>"$TEST_LOG"
printf '\t%s' "$@" "conf=$(cat "$OMARCHY_HID_APPLE_CONF")" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
exit "${REBUILD_STATUS:-0}"
SH
done
chmod +x "$stub_bin"/*

reset() {
  rm -rf "${test_tmp:?}/etc" "${test_tmp:?}/sys"
  mkdir -p "$test_tmp/sys"
  printf '2\n' >"$param"
  : >"$calls"
}

run_leaf() {
  APPLE_SILICON=$1 OMARCHY_HID_APPLE_CONF="$conf" PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    bash -euo pipefail -c 'source "$1"' _ "$leaf"
}

run_migration() {
  APPLE_SILICON=$1 LIMINE=${2:-0} OMARCHY_HID_APPLE_CONF="$conf" OMARCHY_HID_APPLE_FNMODE="$param" \
    PATH="$stub_bin:$PATH" TEST_LOG="$calls" bash -euo pipefail "$migration"
}

stock_x86() {
  mkdir -p "$(dirname "$conf")"
  printf 'options hid_apple fnmode=2\n' >"$conf"
}

reset
run_leaf 0
[[ $(<"$conf") == "options hid_apple fnmode=2" ]] || fail "x86 keeps F-keys first (fnmode=2)" "$(cat "$conf")"
pass "x86 keeps F-keys first (fnmode=2)"

reset
run_leaf 1
[[ $(<"$conf") == "options hid_apple fnmode=3" ]] || fail "an Apple Silicon install puts media keys first (fnmode=3)" "$(cat "$conf")"
pass "an Apple Silicon install puts media keys first (fnmode=3)"

reset
mkdir -p "$(dirname "$conf")"
printf 'options hid_apple fnmode=2 swap_opt_cmd=1\n' >"$conf"
run_leaf 1
[[ $(<"$conf") == "options hid_apple fnmode=2 swap_opt_cmd=1" ]] || fail "the leaf leaves an existing hid_apple.conf alone"
pass "the leaf leaves an existing hid_apple.conf alone"

reset
stock_x86
run_migration 0
[[ $(<"$conf") == "options hid_apple fnmode=2" && ! -s $calls ]] || fail "the migration does nothing off Apple Silicon" "$(cat "$calls")"
pass "the migration does nothing off Apple Silicon"

reset
stock_x86
run_migration 1
[[ $(<"$conf") == "options hid_apple fnmode=3" ]] || fail "the migration replaces the stock fnmode=2 on a Mac" "$(cat "$conf")"
grep -q $'^mkinitcpio\t-P\tconf=options hid_apple fnmode=3$' "$calls" ||
  fail "a GRUB Mac rebuilds its initramfs with the new option" "$(cat "$calls")"
! grep -q '^omarchy-mac-boot-update' "$calls" || fail "a GRUB Mac does not run the Limine rebuild" "$(cat "$calls")"
[[ $(<"$param") == 3 ]] || fail "the running keyboard switches without a reboot" "$(cat "$param")"
pass "a GRUB Mac moves from fnmode=2 to fnmode=3 and rebuilds its initramfs"

reset
stock_x86
run_migration 1 1
grep -q $'^omarchy-mac-boot-update\tconf=options hid_apple fnmode=3$' "$calls" ||
  fail "a Limine Mac rebuilds its UKI with the new option" "$(cat "$calls")"
! grep -q '^mkinitcpio' "$calls" || fail "a Limine Mac leaves the rebuild to omarchy-mac-boot-update" "$(cat "$calls")"
pass "a Limine Mac rebuilds its UKI"

reset
stock_x86
if REBUILD_STATUS=1 run_migration 1 2>"$test_tmp/err"; then
  fail "a failed rebuild fails the migration"
fi
[[ $(<"$conf") == "options hid_apple fnmode=2" ]] || fail "a failed rebuild puts the stock line back for the retry" "$(cat "$conf")"
[[ $(<"$param") == 2 ]] || fail "a failed rebuild leaves the running keyboard as it was" "$(cat "$param")"
grep -q 'will retry later' "$test_tmp/err" || fail "a failed rebuild says the migration retries" "$(cat "$test_tmp/err")"
: >"$calls"
run_migration 1
[[ $(<"$conf") == "options hid_apple fnmode=3" ]] || fail "the retry finishes the move" "$(cat "$conf")"
pass "a failed rebuild restores the stock line and the retry finishes"

for owned in 'options hid_apple fnmode=1' 'options hid_apple fnmode=2 iso_layout=0' 'options hid_apple fnmode=3'; do
  reset
  mkdir -p "$(dirname "$conf")"
  printf '%s\n' "$owned" >"$conf"
  run_migration 1
  [[ $(<"$conf") == "$owned" && ! -s $calls ]] || fail "the migration leaves '$owned' alone" "$(cat "$calls")"
done
reset
run_migration 1
[[ ! -e $conf && ! -s $calls ]] || fail "the migration writes nothing when there is no hid_apple.conf"
pass "a hid_apple.conf the owner wrote, or none, is left alone"
