#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1790055026.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls"
omarchy="$test_tmp/omarchy"
mkdir -p "$stub_bin" "$omarchy/install/hardware/apple" "$test_tmp/etc"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
echo "sudo $*" >>"$TEST_CALLS"
exec "$@"
SH
printf '#!/bin/bash\nexit 0\n' >"$stub_bin/omarchy-hw-apple-silicon"
printf '#!/bin/bash\necho linux-asahi\n' >"$stub_bin/omarchy-hw-apple-kernel"
printf '#!/bin/bash\nexit 0\n' >"$stub_bin/limine-update"
cat >"$stub_bin/omarchy-mac-esp" <<'SH'
#!/bin/bash
[[ -n ${TEST_FOUND_ESP:-} ]] || { echo "omarchy-mac-esp: not found" >&2; exit 1; }
echo "$TEST_FOUND_ESP"
SH
cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
echo "pacman $*" >>"$TEST_CALLS"
case "$1" in
  -S) exit 0 ;;
  -Q) echo "limine-mkinitcpio-hook 1.36.0-3" ;;
  -Qlq) printf '/usr/\n/usr/lib/modules/7.1.13-3-2-ARCH/vmlinuz\n/usr/lib/modules/7.1.13-3-2-ARCH/pkgbase\n' ;;
esac
SH
# /boot holds the installed kernel unless the test says it went stale.
cat >"$stub_bin/cmp" <<'SH'
#!/bin/bash
echo "cmp $*" >>"$TEST_CALLS"
[[ -z ${TEST_STALE_BOOT:-} ]]
SH
# mkinitcpio's own hook script, which pacman runs from /.
cat >"$stub_bin/mkinitcpio-alpm" <<'SH'
#!/bin/bash
echo "mkinitcpio-alpm $* cwd=$PWD targets=$(cat)" >>"$TEST_CALLS"
[[ -z ${TEST_MKINITCPIO_FAILS:-} ]]
SH
# The leaf activates Limine by writing its defaults, unless told to decline.
cat >"$omarchy/install/hardware/apple/limine-boot.sh" <<'SH'
echo "leaf" >>"$TEST_CALLS"
[[ -n ${TEST_LEAF_DECLINES:-} ]] || printf 'ESP_PATH="%s"\n' "$TEST_FOUND_ESP" >"$OMARCHY_LIMINE_DEFAULT"
SH
# The boot check: a kernel installed by this update boots after the reboot.
cat >"$stub_bin/omarchy-apple-silicon-boot-check" <<'SH'
#!/bin/bash
echo "boot-check $* pending=${OMARCHY_BOOT_CHECK_ALLOW_PENDING_REBOOT:-0}" >>"$TEST_CALLS"
[[ -z ${TEST_CHECK_FAILS:-} ]] || { echo "Apple Silicon boot check: /boot/limine.conf is missing on a Limine Mac" >&2; exit 1; }
if [[ -n ${TEST_NEW_KERNEL:-} ]]; then
  if [[ ${OMARCHY_BOOT_CHECK_ALLOW_PENDING_REBOOT:-0} != 1 ]]; then
    echo "Apple Silicon boot check: running kernel is 7.1.13-1-1-ARCH, not the installed linux-asahi 7.1.13-3-2-ARCH" >&2
    exit 1
  fi
  echo "Apple Silicon boot check: running kernel is 7.1.13-1-1-ARCH; linux-asahi 7.1.13-3-2-ARCH is installed from the installed linux-asahi, reboot pending"
  exit 0
fi
echo "Apple Silicon boot check: running linux-asahi 7.1.13-3-2-ARCH from the installed linux-asahi"
SH
chmod +x "$stub_bin"/*
ln -s "$ROOT/bin/omarchy-mac-limine-active" "$stub_bin/omarchy-mac-limine-active"

gate="$test_tmp/limine.enabled"
limine_default="$test_tmp/etc/limine"

run_migration() {
  : >"$calls"
  rm -f "$gate" "$limine_default"
  status=0
  TEST_CALLS="$calls" OMARCHY_PATH="$omarchy" OMARCHY_LIMINE_GATE="$gate" OMARCHY_LIMINE_DEFAULT="$limine_default" \
    OMARCHY_MKINITCPIO_ALPM="$stub_bin/mkinitcpio-alpm" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >"$test_tmp/out" 2>"$test_tmp/err" || status=$?
}

# Issue #238: an ESP neither at /boot/efi nor at /boot. The Mac keeps GRUB, and
# the migration settles instead of failing every update and blocking the
# migrations after it.
run_migration
(( status == 0 )) || fail "a Mac without a system ESP settles the migration" "$(cat "$test_tmp/err")"
grep -Fq 'this Mac keeps booting GRUB' "$test_tmp/err" || fail "the Mac is told GRUB stays" "$(cat "$test_tmp/err")"
[[ ! -e $gate ]] && ! grep -q '^pacman -S\|^leaf' "$calls" ||
  fail "without a system ESP nothing is installed and no gate is written" "$(cat "$calls")"
pass "a Mac without a system ESP keeps GRUB and the migration settles"

export TEST_FOUND_ESP="$test_tmp/boot"
run_migration
(( status == 0 )) || fail "the migration activates Limine" "$(cat "$test_tmp/err")"
[[ -e $gate ]] || fail "the migration writes the gate"
grep -q '^leaf$' "$calls" || fail "the migration runs the leaf" "$(cat "$calls")"
pass "an ESP at /boot activates Limine"

# Issue #235: the same update installed a new kernel. The Limine files are
# verified; the running kernel follows at the reboot.
TEST_NEW_KERNEL=1 run_migration
(( status == 0 )) || fail "a kernel waiting for the reboot does not fail the migration" "$(cat "$test_tmp/err")"
grep -Fq 'boot-check linux-asahi pending=1' "$calls" || fail "the boot check allows the pending reboot" "$(cat "$calls")"
grep -Fq 'reboot to start the new kernel' "$test_tmp/out" || fail "the owner is told to reboot" "$(cat "$test_tmp/out")"
pass "a new kernel waiting for the reboot is not a failed migration"

# A kernel updated while the old limine-mkinitcpio-hook shadowed mkinitcpio's
# hook never reached /boot; mkinitcpio's hook script installs it before the
# check.
TEST_STALE_BOOT=1 run_migration
(( status == 0 )) || fail "a stale /boot kernel is installed again" "$(cat "$test_tmp/err")"
grep -Fxq 'mkinitcpio-alpm install cwd=/ targets=usr/lib/modules/7.1.13-3-2-ARCH/vmlinuz' "$calls" ||
  fail "mkinitcpio's hook script gets the kernel image, from /" "$(cat "$calls")"
[[ $(grep -n '^mkinitcpio-alpm' "$calls" | cut -d: -f1) -lt $(grep -n '^boot-check' "$calls" | cut -d: -f1) ]] ||
  fail "the kernel is installed before the boot check" "$(cat "$calls")"
run_migration
! grep -q 'mkinitcpio-alpm' "$calls" || fail "a current /boot kernel is left alone" "$(cat "$calls")"
TEST_STALE_BOOT=1 TEST_MKINITCPIO_FAILS=1 run_migration
(( status == 1 )) && grep -Fq 'could not be installed under /boot' "$test_tmp/err" ||
  fail "a failed kernel install leaves the migration to retry" "$(cat "$test_tmp/err")"
pass "a kernel the old hook kept from /boot is installed before the check"

TEST_CHECK_FAILS=1 run_migration
(( status == 1 )) || fail "boot files that do not verify fail the migration"
grep -Fq 'will retry later' "$test_tmp/err" || fail "the failure says the migration retries" "$(cat "$test_tmp/err")"
TEST_LEAF_DECLINES=1 run_migration
(( status == 1 )) && grep -Fq 'Limine was not activated' "$test_tmp/err" ||
  fail "a leaf that declines leaves the migration to retry" "$(cat "$test_tmp/err")"
pass "real failures still leave the migration to retry"
unset TEST_FOUND_ESP

# omarchy-mac-esp: the device tree's ESP where it is mounted whole, /boot/efi
# first; without the device tree's name, the FAT filesystem there.
esp_node="$test_tmp/esp-partuuid"
mounts="$test_tmp/mounts"
cat >"$stub_bin/findmnt" <<'SH'
#!/bin/bash
[[ "${*:1:5}" == "-n -r -o FSTYPE,FSROOT,PARTUUID --mountpoint" ]] || exit 1
awk -v target="$6" '$1 == target { print $2, $3, $4; found = 1 } END { exit !found }' "$TEST_MOUNTS"
SH
chmod +x "$stub_bin/findmnt"
find_esp() {
  OMARCHY_ESP_PARTUUID_FILE="$esp_node" TEST_MOUNTS="$mounts" PATH="$stub_bin:$PATH" bash "$ROOT/bin/omarchy-mac-esp" 2>"$test_tmp/err"
}
printf '5F2B0C3E-0002\0' >"$esp_node"
printf '/boot/efi vfat / 5f2b0c3e-0002\n/boot btrfs /@/boot x\n' >"$mounts"
[[ $(find_esp) == /boot/efi ]] || fail "the device tree's ESP at /boot/efi is found"
printf '/boot vfat / 5f2b0c3e-0002\n' >"$mounts"
[[ $(find_esp) == /boot ]] || fail "the device tree's ESP at /boot is found (an older install)"
printf '/boot/efi vfat / 11111111-0001\n/boot vfat / 5f2b0c3e-0002\n' >"$mounts"
[[ $(find_esp) == /boot ]] || fail "another FAT filesystem at /boot/efi is not the system ESP"
printf '/boot/efi vfat /EFI 5f2b0c3e-0002\n' >"$mounts"
! find_esp >/dev/null || fail "a bind of part of the ESP is not the ESP"
grep -Fq 'PARTUUID=5f2b0c3e-0002' "$test_tmp/err" || fail "the missing ESP is named" "$(cat "$test_tmp/err")"
printf '/boot/efi autofs / \n/boot/efi vfat / 5f2b0c3e-0002\n' >"$mounts"
[[ $(find_esp) == /boot/efi ]] || fail "an ESP mounted over its automount point is found"
rm -f "$esp_node"
printf '/boot vfat / 11111111-0001\n' >"$mounts"
[[ $(find_esp) == /boot ]] || fail "without a device tree name the FAT filesystem at /boot is the ESP"
printf '/boot ext4 / 11111111-0001\n' >"$mounts"
! find_esp >/dev/null || fail "an ext4 /boot is not an ESP"
pass "omarchy-mac-esp finds the system ESP at /boot/efi or /boot"

# omarchy-mac-limine-deploy writes the Limine the tooling's ESP_PATH names.
esp="$test_tmp/boot"
mkdir -p "$esp/EFI/BOOT" "$test_tmp/share"
printf 'LIMINE\n' >"$test_tmp/share/BOOTAA64.EFI"
: >"$gate"
printf 'ESP_PATH="%s"\n' "$esp" >"$limine_default"
printf '#!/bin/bash\n[[ "$*" == "-no TARGET %s" ]]\n' "$esp" >"$stub_bin/findmnt"
rm -f "$stub_bin/cmp"
OMARCHY_LIMINE_GATE="$gate" OMARCHY_LIMINE_DEFAULT="$limine_default" OMARCHY_LIMINE_EFI="$test_tmp/share/BOOTAA64.EFI" \
  PATH="$stub_bin:$PATH" bash "$ROOT/bin/omarchy-mac-limine-deploy" >/dev/null || fail "Limine deploys to ESP_PATH"
cmp -s "$test_tmp/share/BOOTAA64.EFI" "$esp/EFI/BOOT/BOOTAA64.EFI" || fail "the U-Boot slot on ESP_PATH holds Limine"
pass "omarchy-mac-limine-deploy follows ESP_PATH"
