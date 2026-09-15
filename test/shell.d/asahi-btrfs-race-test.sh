#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-asahi-btrfs-race.sh"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1789107528.sh"

grep -q 'apple/fix-asahi-btrfs-race.sh' "$all" ||
  fail "the static device node ordering runs during hardware setup"
pass "the static device node ordering runs during hardware setup"

# Apple Silicon runs only migrations its policy has reviewed; one left out would
# sit pending forever on exactly the machines it exists for.
grep -Eq "^[[:space:]]*1789107528\.sh\) printf 'run" "$ROOT/bin/omarchy-migrate" ||
  fail "the static device node migration is reviewed to run on Apple Silicon"
pass "the static device node migration is reviewed to run on Apple Silicon"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
dropin_dir="$test_tmp/etc/systemd/system/kmod-static-nodes.service.d"
dropin="$dropin_dir/10-before-tmpfiles-setup-dev.conf"
ready="$test_tmp/var/lib/omarchy/asahi-btrfs-initramfs-ready"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash

[[ ${APPLE_SILICON:-0} == "1" ]]
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/mkinitcpio" <<'SH'
#!/bin/bash

printf 'mkinitcpio' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
exit "${MKINITCPIO_STATUS:-0}"
SH

cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash

printf 'omarchy-state' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

sed -e "s|/etc/systemd/system|$test_tmp/etc/systemd/system|g" \
  "$leaf" >"$test_tmp/leaf.sh"

run_leaf() {
  local apple_silicon="${1:-1}"

  rm -rf "$test_tmp/etc"
  : >"$calls"

  APPLE_SILICON="$apple_silicon" TEST_LOG="$calls" PATH="$stub_bin:$PATH" \
    bash -eE -c 'source "$1"' bash "$test_tmp/leaf.sh" </dev/null
}

run_leaf >/dev/null
[[ -f $dropin ]] ||
  fail "an Apple Silicon Mac gets the drop-in" "$(ls -R "$test_tmp/etc" 2>&1)"
pass "an Apple Silicon Mac gets the drop-in"

# mkinitcpio copies every *.conf under the unit's .d directory into the image,
# and the ordering is all the drop-in may change about the stock unit.
[[ $(cat "$dropin") == $'[Unit]\nBefore=systemd-tmpfiles-setup-dev.service' ]] ||
  fail "the drop-in only orders static nodes before /dev setup" "$(cat "$dropin")"
[[ $(ls "$dropin_dir") == "10-before-tmpfiles-setup-dev.conf" ]] ||
  fail "the drop-in is the only file in the unit's drop-in directory" "$(ls "$dropin_dir")"
pass "the drop-in only orders static nodes before /dev setup"

run_leaf 0 >/dev/null
[[ ! -e $dropin ]] ||
  fail "a machine without Apple Silicon is left alone" "$(cat "$dropin")"
pass "a machine without Apple Silicon is left alone"

run_migration() {
  local apple_silicon="${1:-1}" mkinitcpio_status="${2:-0}"

  : >"$calls"

  APPLE_SILICON="$apple_silicon" TEST_LOG="$calls" PATH="$stub_bin:$PATH" \
    MKINITCPIO_STATUS="$mkinitcpio_status" \
    OMARCHY_PATH="$test_tmp/omarchy" OMARCHY_ASAHI_STATIC_NODES_DROPIN="$dropin" \
    OMARCHY_ASAHI_BTRFS_READY="$ready" \
    bash -euo pipefail "$migration"
}

mkdir -p "$test_tmp/omarchy/install/hardware/apple"
cp "$test_tmp/leaf.sh" "$test_tmp/omarchy/install/hardware/apple/fix-asahi-btrfs-race.sh"

rm -rf "$test_tmp/etc"
run_migration >/dev/null
[[ -f $dropin ]] ||
  fail "the migration fixes an install that never ran the leaf" "$(ls -R "$test_tmp/etc" 2>&1)"
grep -Fq $'mkinitcpio\t-P' "$calls" ||
  fail "the migration rebuilds the initramfs that carries the drop-in" "$(cat "$calls")"
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the migration asks for the reboot that applies it" "$(cat "$calls")"
[[ -f $ready ]] ||
  fail "the migration records a successful initramfs rebuild" "$(cat "$calls")"
pass "the migration fixes an install that never ran the leaf"

run_migration >/dev/null
[[ ! -s $calls ]] ||
  fail "a repaired install is left untouched" "$(cat "$calls")"
pass "the migration is idempotent"

rm -rf "$test_tmp/etc"
rm -f "$ready"
if run_migration 1 1 >/dev/null 2>&1; then
  fail "a failed rebuild leaves the migration pending"
fi
if grep -Fq 'omarchy-state' "$calls"; then
  fail "a failed rebuild does not ask for a reboot" "$(cat "$calls")"
fi
[[ ! -e $ready ]] ||
  fail "a failed rebuild does not record success" "$(cat "$calls")"
run_migration >/dev/null
[[ -f $ready ]] ||
  fail "a successful retry records the rebuilt initramfs" "$(cat "$calls")"
pass "a failed rebuild remains pending and retries"

rm -rf "$test_tmp/etc"
rm -f "$ready"
run_migration 0 >/dev/null
[[ ! -e $dropin ]] ||
  fail "the migration skips hardware without the race" "$(cat "$dropin")"
if grep -Fq 'mkinitcpio' "$calls"; then
  fail "the migration rebuilds nothing without Apple Silicon" "$(cat "$calls")"
fi
pass "the migration skips hardware without the race"

echo "asahi-btrfs-race: all checks passed"
