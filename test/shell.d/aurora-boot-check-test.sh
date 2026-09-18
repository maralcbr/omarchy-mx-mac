#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command gzip
require_command realpath

check="$ROOT/bin/omarchy-update-aurora-boot-check"
grep -Fq '# omarchy:hidden=true' "$check" || fail "the boot check is hidden from command listings"
! grep -Eq '^[[:space:]]*(sudo[[:space:]]+)?(update-m1n1|/usr/bin/update-m1n1|"?\$script"?)([[:space:];]|$)' "$check" ||
  fail "the boot check never runs update-m1n1"
pass "the boot check is hidden and never runs update-m1n1"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
root="$test_tmp/root"
calls="$test_tmp/calls"
kver=6.17.0-aurora1-ARCH
modules="$root/usr/lib/modules/$kver"
esp="$root/boot/efi"
esp_device="$test_tmp/esp-device"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$TEST_CALLS"
exec "$@"
SH
# pacman lists linux-aurora's files from the fixture.
cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
[[ $* == "-Qlq linux-aurora" ]] || exit 1
cat "$TEST_OWNED"
SH
cat >"$stub_bin/lsinitcpio" <<'SH'
#!/bin/bash
[[ $1 == -l && -f $2 ]] || exit 1
cat "$TEST_INITRAMFS_LIST"
SH
# mount copies what it would mount; -o ro can be made to fail the way a
# second read-only mount of a read-write superblock does.
cat >"$stub_bin/mount" <<'SH'
#!/bin/bash
printf 'mount %s\n' "$*" >>"$TEST_CALLS"
target=${@: -1}
if [[ $* == *remount* ]]; then
  exit 0
fi
if [[ ${TEST_RO_BUSY:-0} == 1 && $* == *"-o ro"* ]]; then
  echo "mount: $target: cannot mount read-only" >&2
  exit 32
fi
if [[ " $* " == *" --bind "* ]]; then
  source=${@: -2:1}
else
  [[ ${@: -2:1} == "PARTUUID=$TEST_PARTUUID" ]] || exit 32
  source=$TEST_ESP_DEVICE
fi
cp -a "$source/." "$target/"
: >"$TEST_MOUNTED"
SH
cat >"$stub_bin/umount" <<'SH'
#!/bin/bash
printf 'umount %s\n' "$*" >>"$TEST_CALLS"
find "$1" -mindepth 1 -delete
rm -f "$TEST_MOUNTED"
SH
chmod +x "$stub_bin"/*

# update-m1n1 as asahi-scripts 20260127.1 ships it, with the DTBS default ALARM adds.
write_update_m1n1() {
  mkdir -p "$root/usr/bin"
  cat >"$root/usr/bin/update-m1n1" <<'SH'
#!/bin/sh
# SPDX-License-Identifier: MIT

set -e

[ -e /etc/default/update-m1n1 ] && . /etc/default/update-m1n1

[ -n "$M1N1_UPDATE_DISABLED" ] && exit 0

. /usr/share/asahi-scripts/functions.sh

: ${SOURCE:="/usr/lib/asahi-boot/"}
: ${M1N1:="$SOURCE/m1n1.bin"}
: ${U_BOOT:="$SOURCE/u-boot-nodtb.bin"}
: ${TARGET:="$1"}
: ${DTBS:=$(/bin/ls -d /lib/modules/*-ARCH | sort -rV | head -1)/dtbs/*.dtb}
: ${CONFIG:=/etc/m1n1.conf}

if [ -z "$DTBS" ]; then
    exit 1
fi

m1n1config=/run/m1n1.conf
>"$m1n1config"

if [ -e "$CONFIG" ]; then
    while read line; do
        case "$line" in
            "") ;;
            \#*) ;;
            chosen.*=*|display=*|mitigations=*)
                echo "$line" >> "$m1n1config"
                ;;
        esac
    done <$CONFIG
fi

cat "$M1N1" $DTBS >"${TARGET}.new"
gzip -c "$U_BOOT" >>"${TARGET}.new"
cat "$m1n1config" >>"${TARGET}.new"
SH
}

# boot.bin as update-m1n1 would have written it from the given device trees.
write_boot_bin() {
  local dtb paths=()
  for dtb; do
    paths+=("$root$dtb")
  done
  mkdir -p "$esp/m1n1"
  {
    cat "$root/usr/lib/asahi-boot/m1n1.bin" "${paths[@]}"
    gzip -c "$root/usr/lib/asahi-boot/u-boot-nodtb.bin"
    printf 'chosen.asahi,efi-system-partition=1234\ndisplay=2560x1600\nmitigations=off\n'
  } >"$esp/m1n1/boot.bin"
}

dtbs=("/usr/lib/modules/$kver/dtbs/t6000-j314s.dtb" "/usr/lib/modules/$kver/dtbs/t6020-j414s.dtb" "/usr/lib/modules/$kver/dtbs/t8103-j274.dtb")

healthy() {
  rm -rf "$root" "$esp_device"
  mkdir -p "$modules/dtbs" "$root/boot/grub" "$root/usr/lib/asahi-boot" "$root/etc" "$root/run" "$esp/m1n1"
  ln -s usr/lib "$root/lib"
  printf 'aurora kernel %s\n' "$kver" >"$modules/vmlinuz"
  cp "$modules/vmlinuz" "$root/boot/vmlinuz-linux-aurora"
  printf 'initramfs\n' >"$root/boot/initramfs-linux-aurora.img"
  printf 'linux /vmlinuz-linux-aurora root=UUID=x\ninitrd /initramfs-linux-aurora.img\n' >"$root/boot/grub/grub.cfg"
  for dtb in "${dtbs[@]}"; do
    printf 'device tree %s\n' "${dtb##*/}" >"$root$dtb"
  done
  printf 'm1n1 stage 2\n' >"$root/usr/lib/asahi-boot/m1n1.bin"
  printf 'u-boot\n' >"$root/usr/lib/asahi-boot/u-boot-nodtb.bin"
  printf '# options\nchosen.asahi,efi-system-partition=1234\ndisplay=2560x1600\n   mitigations=off\nunknown=1\n\n' >"$root/etc/m1n1.conf"
  write_update_m1n1
  {
    printf '/usr/\n/usr/lib/\n/usr/lib/modules/\n/usr/lib/modules/%s/\n/usr/lib/modules/%s/vmlinuz\n' "$kver" "$kver"
    printf '/usr/lib/modules/%s/dtbs/\n' "$kver"
    printf '%s\n' "${dtbs[@]}"
  } >"$test_tmp/owned"
  printf 'usr/lib/modules/%s/kernel/drivers/gpu/drm/apple/appledrm.ko.zst\nusr/bin/init\n' "$kver" >"$test_tmp/initramfs"
  write_boot_bin "${dtbs[@]}"
}

run_check() {
  : >"$calls"
  set +e
  TEST_CALLS="$calls" \
    TEST_OWNED="$test_tmp/owned" \
    TEST_INITRAMFS_LIST="$test_tmp/initramfs" \
    TEST_MOUNTED="$test_tmp/mounted" \
    TEST_PARTUUID=5f2b0c3e-0002 \
    TEST_ESP_DEVICE="$esp_device" \
    OMARCHY_AURORA_ROOT="$root" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$check" >"$test_tmp/out" 2>"$test_tmp/err"
  status=$?
  set -e
}

expect_pass() {
  (( status == 0 )) || fail "$1 passes" "status $status: $(cat "$test_tmp/err")"
  [[ ! -e $test_tmp/mounted ]] || fail "$1 unmounts the ESP"
  [[ -z $(ls -A "$root/run") ]] || fail "$1 leaves no mountpoint behind" "$(ls -A "$root/run")"
}

expect_fail() {
  local description=$1 message=$2
  (( status == 1 )) || fail "$description fails the check" "status $status: $(cat "$test_tmp/err")"
  grep -Fq "$message" "$test_tmp/err" || fail "$description is explained" "$(cat "$test_tmp/err")"
  [[ ! -e $test_tmp/mounted ]] || fail "$description unmounts the ESP"
  [[ -z $(ls -A "$root/run") ]] || fail "$description leaves no mountpoint behind" "$(ls -A "$root/run")"
}

healthy
run_check
expect_pass "a boot chain that matches linux-aurora"
grep -Eq "^mount -o ro --bind $esp $root/run/omarchy-esp\.[A-Za-z0-9]{6}\$" "$calls" ||
  fail "without an ESP in the device tree, /boot/efi is bind-mounted read-only at a private mountpoint" "$(cat "$calls")"
! grep -q 'update-m1n1' "$calls" || fail "update-m1n1 is not run" "$(cat "$calls")"
[[ ! -e $root/run/m1n1.conf ]] || fail "/run/m1n1.conf is not rewritten"
pass "a healthy boot chain passes: kernel, initramfs, GRUB and m1n1 rebuilt from the ALARM defaults"

healthy
mkdir -p "$root/proc/device-tree/chosen" "$esp_device"
printf '5f2b0c3e-0002\0' >"$root/proc/device-tree/chosen/asahi,efi-system-partition"
cp -a "$esp/." "$esp_device/"
rm -rf "$esp/m1n1"
run_check
expect_pass "an ESP named in the device tree"
grep -Eq "^mount -o ro PARTUUID=5f2b0c3e-0002 $root/run/omarchy-esp\.[A-Za-z0-9]{6}\$" "$calls" ||
  fail "the ESP the device tree names is mounted read-only" "$(cat "$calls")"
TEST_RO_BUSY=1 run_check
expect_pass "an ESP that is already mounted read-write"
grep -Eq '^mount -o remount,ro,bind ' "$calls" || fail "a mount that cannot start read-only is made read-only before it is read" "$(cat "$calls")"
: >"$root/boot/efi/.builder"
mkdir -p "$esp/m1n1"
cp "$esp_device/m1n1/boot.bin" "$esp/m1n1/"
run_check
expect_pass "a builder image"
grep -Eq "^mount -o ro --bind $esp " "$calls" || fail "a builder image uses /boot/efi like mount_sys_esp" "$(cat "$calls")"
pass "the system ESP is found the way mount_sys_esp finds it and only ever read through a read-only mount"

# What a failed hook after the transaction leaves behind.
healthy
printf 'the previous kernel\n' >"$root/boot/vmlinuz-linux-aurora"
run_check
expect_fail "a /boot kernel mkinitcpio did not replace" "/boot/vmlinuz-linux-aurora is not the $kver kernel"
healthy
printf 'usr/lib/modules/6.16.0-aurora9-ARCH/kernel/x.ko\n' >"$test_tmp/initramfs"
run_check
expect_fail "an initramfs built for the previous kernel" "does not hold the $kver modules"
healthy
printf 'linux /vmlinuz-linux-aurora\n' >"$root/boot/grub/grub.cfg"
run_check
expect_fail "a GRUB entry without the initramfs" "grub.cfg does not boot vmlinuz-linux-aurora with initramfs-linux-aurora.img"
healthy
write_boot_bin "${dtbs[@]:0:2}"
run_check
expect_fail "an m1n1 image update-m1n1 did not rebuild" "m1n1/boot.bin on the system ESP (/boot/efi) is not m1n1"
healthy
rm "$esp/m1n1/boot.bin"
run_check
expect_fail "an ESP without m1n1" "has no m1n1/boot.bin"
healthy
mkdir -p "$root/etc/default"
printf 'M1N1_UPDATE_DISABLED=1\n' >"$root/etc/default/update-m1n1"
run_check
expect_fail "m1n1 updates disabled" "M1N1_UPDATE_DISABLED is set"
healthy
printf 'stray\n' >"$modules/dtbs/zz-stray.dtb"
run_check
expect_fail "a device tree linux-aurora does not own" "device tree /lib/modules/$kver/dtbs/zz-stray.dtb is not owned by linux-aurora"
pass "a stale kernel, initramfs, GRUB entry or m1n1 image, disabled m1n1 updates and a stray device tree all fail"

# update-m1n1's defaults: := fills unset and empty settings alike.
mkdir -p "$root/etc/default"
for config in '' 'DTBS=\nSOURCE=""\n' 'CONFIG=\nM1N1=\nU_BOOT=\n' 'M1N1_UPDATE_DISABLED=\n'; do
  healthy
  mkdir -p "$root/etc/default"
  if [[ -n $config ]]; then
    printf "$config" >"$root/etc/default/update-m1n1"
  fi
  run_check
  expect_pass "update-m1n1 configuration '$config'"
done
healthy
mkdir -p "$root/etc/default" "$root/usr/lib/modules/6.9.0-asahi-ARCH/dtbs"
printf 'old\n' >"$root/usr/lib/modules/6.9.0-asahi-ARCH/dtbs/t8103-j274.dtb"
run_check
expect_pass "the newest -ARCH kernel is linux-aurora's"
mkdir -p "$root/usr/lib/modules/6.18.0-asahi-ARCH/dtbs"
printf 'newer\n' >"$root/usr/lib/modules/6.18.0-asahi-ARCH/dtbs/t8103-j274.dtb"
run_check
expect_fail "a newer kernel's device trees picked by the default" "is not one of linux-aurora $kver's"
healthy
mkdir -p "$root/etc/default"
printf 'DTBS="%s %s"\n' "${dtbs[2]}" "${dtbs[0]}" >"$root/etc/default/update-m1n1"
write_boot_bin "${dtbs[2]}" "${dtbs[0]}"
run_check
expect_pass "an explicit DTBS list, in its own order"
printf 'DTBS="/usr/lib/modules/%s/dtbs/*.dtb"\nTARGET=/boot/efi/m1n1/boot.bin\n' "$kver" >"$root/etc/default/update-m1n1"
write_boot_bin "${dtbs[@]}"
run_check
expect_pass "a DTBS glob, with a TARGET that is not read"
[[ -f $esp/m1n1/boot.bin ]] && ! compgen -G "$esp/m1n1/boot.bin.*" >/dev/null || fail "a configured TARGET is never written"
printf 'M1N1=/opt/m1n1.bin\n' >"$root/etc/default/update-m1n1"
mkdir -p "$root/opt"
printf 'custom m1n1\n' >"$root/opt/m1n1.bin"
run_check
expect_fail "a configured m1n1 the ESP image was not built from" "is not m1n1"
{
  cat "$root/opt/m1n1.bin" "${dtbs[@]/#/$root}"
  gzip -c "$root/usr/lib/asahi-boot/u-boot-nodtb.bin"
  printf 'chosen.asahi,efi-system-partition=1234\ndisplay=2560x1600\nmitigations=off\n'
} >"$esp/m1n1/boot.bin"
run_check
expect_pass "a configured m1n1"
pass "update-m1n1 defaults apply to unset and empty settings, and DTBS, M1N1 and the -ARCH default are honoured"

healthy
sed -i '/DTBS:=/d' "$root/usr/bin/update-m1n1"
run_check
expect_fail "stock update-m1n1 without DTBS configured" "DTBS is unset or empty"
healthy
sed -i 's|^: ${SOURCE:=.*|: ${SOURCE:=$(asahi-boot-dir)}|' "$root/usr/bin/update-m1n1"
run_check
expect_fail "a default this check cannot read" "has a SOURCE default this check does not recognise"
healthy
sed -i '/^: ${CONFIG:=/d' "$root/usr/bin/update-m1n1"
run_check
expect_fail "a missing default" "has no CONFIG default this check recognises"
healthy
sed -i 's|^gzip -c "$U_BOOT"|xz -c "$U_BOOT"|' "$root/usr/bin/update-m1n1"
run_check
expect_fail "an update-m1n1 that builds its image differently" "does not build m1n1/boot.bin the way this check rebuilds it"
pass "an update-m1n1 whose defaults or assembly are not recognised fails closed"
