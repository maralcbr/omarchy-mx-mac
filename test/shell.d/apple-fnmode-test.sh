#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/fix-fkeys.sh"
migration="$ROOT/migrations/1790305681.sh"
all="$ROOT/install/hardware/all.sh"

grep -q 'hardware/fix-fkeys.sh' "$all" || fail "hardware setup runs the F-key leaf"
pass "hardware setup runs the F-key leaf"

grep -Fq "1790305681.sh) printf 'run" "$ROOT/bin/omarchy-migrate" ||
  fail "the Apple Silicon migration policy runs the fnmode migration"
pass "the Apple Silicon migration policy runs the fnmode migration"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
conf="$test_tmp/etc/modprobe.d/hid_apple.conf"
param="$test_tmp/sys/fnmode"
pending="$test_tmp/var/lib/omarchy/migrations/1790305681-boot-image-pending"
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
# A parameter the kernel refuses to change.
[[ ${FNMODE_WRITE_FAILS:-0} == 1 && $1 == tee && $2 == "$OMARCHY_HID_APPLE_FNMODE" ]] && exit 1
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
  rm -rf "${test_tmp:?}/etc" "${test_tmp:?}/sys" "${test_tmp:?}/var"
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
    OMARCHY_HID_APPLE_PENDING="$pending" \
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
[[ ! -e $pending ]] || fail "a finished rebuild clears the pending marker"
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
[[ -f $pending ]] || fail "a failed rebuild keeps the rebuild owed"
[[ $(<"$param") == 2 ]] || fail "a failed rebuild leaves the running keyboard as it was" "$(cat "$param")"
grep -q 'will retry later' "$test_tmp/err" || fail "a failed rebuild says the migration retries" "$(cat "$test_tmp/err")"
: >"$calls"
run_migration 1
grep -q $'^mkinitcpio\t-P\tconf=options hid_apple fnmode=3$' "$calls" || fail "the retry rebuilds the image it still owes" "$(cat "$calls")"
[[ ! -e $pending && $(<"$param") == 3 ]] || fail "the retry finishes the move"
pass "a failed rebuild stays owed and the retry finishes"

# A run cut short after the file changed: fnmode=3 on disk, the rebuild owed.
reset
mkdir -p "$(dirname "$conf")" "$(dirname "$pending")"
printf 'options hid_apple fnmode=3\n' >"$conf"
: >"$pending"
run_migration 1 1
grep -q $'^omarchy-mac-boot-update\tconf=options hid_apple fnmode=3$' "$calls" ||
  fail "an interrupted run still rebuilds the image" "$(cat "$calls")"
[[ ! -e $pending ]] || fail "the finished rebuild clears the marker"
pass "an interrupted run rebuilds the image it owes"

# The owner edited the file while the rebuild was owed: rebuild what is there,
# leave the running keyboard alone.
reset
mkdir -p "$(dirname "$conf")" "$(dirname "$pending")"
printf 'options hid_apple fnmode=2 swap_opt_cmd=1\n' >"$conf"
: >"$pending"
run_migration 1
grep -q $'^mkinitcpio\t-P\tconf=options hid_apple fnmode=2 swap_opt_cmd=1$' "$calls" ||
  fail "an owed rebuild runs with the owner's edited file" "$(cat "$calls")"
[[ ! -e $pending && $(<"$param") == 2 && $(<"$conf") == "options hid_apple fnmode=2 swap_opt_cmd=1" ]] ||
  fail "an owner's edit during an owed rebuild keeps their keyboard mode" "$(cat "$param")"
pass "an owner's edit while the rebuild was owed is kept"

reset
stock_x86
FNMODE_WRITE_FAILS=1 run_migration 1 2>"$test_tmp/err" || fail "a read-only parameter does not fail the migration" "$(cat "$test_tmp/err")"
grep -q 'keeps its mode until the next reboot' "$test_tmp/err" || fail "a read-only parameter is reported" "$(cat "$test_tmp/err")"
[[ $(<"$conf") == "options hid_apple fnmode=3" && ! -e $pending ]] || fail "a read-only parameter still finishes the move"
pass "a parameter that cannot be written waits for the reboot"

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
