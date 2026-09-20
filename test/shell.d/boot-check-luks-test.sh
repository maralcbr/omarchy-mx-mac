#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command gzip
require_command realpath

check="$ROOT/bin/omarchy-apple-silicon-boot-check"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
root="$test_tmp/root"
calls="$test_tmp/calls"
mounts="$test_tmp/mounts"
esp="$root/boot/efi"
esp_device="$test_tmp/esp-device"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$TEST_CALLS"
exec "$@"
SH
cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
case "$*" in
  -Qq) cat "$TEST_FILES/installed" ;;
  "-Qlq "*) [[ -f $TEST_FILES/$2 ]] && cat "$TEST_FILES/$2" ;;
  *) exit 1 ;;
esac
SH
cat >"$stub_bin/lsinitcpio" <<'SH'
#!/bin/bash
[[ $1 == -l && -f $2 ]] || exit 1
cat "$TEST_INITRAMFS_LIST"
SH
cat >"$stub_bin/mount" <<'SH'
#!/bin/bash
printf 'mount %s\n' "$*" >>"$TEST_CALLS"
options="" bind=0 positional=()
while (($#)); do
  case "$1" in
    -o) options=$2; shift 2 ;;
    --bind) bind=1; shift ;;
    *) positional+=("$1"); shift ;;
  esac
done
target=${positional[-1]}
if [[ ,$options, == *,remount,* ]]; then
  sed -i "\|^$target |d" "$TEST_MOUNTS"
  echo "$target ro" >>"$TEST_MOUNTS"
  exit 0
fi
state=rw
[[ ,$options, != *,ro,* ]] || state=ro
if (( bind )); then
  source=${positional[0]}
else
  source=$TEST_ESP_DEVICE
fi
cp -a "$source/." "$target/"
echo "$target $state" >>"$TEST_MOUNTS"
SH
cat >"$stub_bin/umount" <<'SH'
#!/bin/bash
printf 'umount %s\n' "$*" >>"$TEST_CALLS"
find "$1" -mindepth 1 -delete
sed -i "\|^$1 |d" "$TEST_MOUNTS"
SH
cat >"$stub_bin/findmnt" <<'SH'
#!/bin/bash
case "$*" in
  "-n -o VFS-OPTIONS --mountpoint "*)
    state=$(awk -v target="${@: -1}" '$1 == target { print $2 }' "$TEST_MOUNTS")
    [[ -n $state ]] || exit 1
    echo "$state,relatime"
    ;;
  *) exit 1 ;;
esac
SH
chmod +x "$stub_bin"/*

write_update_m1n1() {
  mkdir -p "$root/usr/bin"
  cat >"$root/usr/bin/update-m1n1" <<'SH'
#!/bin/sh
set -e
[ -e /etc/default/update-m1n1 ] && . /etc/default/update-m1n1
[ -n "$M1N1_UPDATE_DISABLED" ] && exit 0
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

system() {
  local kernel=linux-aurora
  kver=6.17.0-aurora1-ARCH
  modules="$root/usr/lib/modules/$kver"
  dtbs=("/usr/lib/modules/$kver/dtbs/t6000-j314s.dtb")
  rm -rf "$root"
  mkdir -p "$modules/dtbs" "$root/boot/grub" "$root/usr/lib/asahi-boot" "$root/etc/default" "$root/run" "$esp/m1n1" "$test_tmp/files"
  : >"$mounts"
  ln -s usr/lib "$root/lib"
  printf '%s kernel %s\n' "$kernel" "$kver" >"$modules/vmlinuz"
  cp "$modules/vmlinuz" "$root/boot/vmlinuz-$kernel"
  printf 'initramfs\n' >"$root/boot/initramfs-$kernel.img"
  printf 'linux /vmlinuz-%s root=UUID=x\ninitrd /initramfs-%s.img\n' "$kernel" "$kernel" >"$root/boot/grub/grub.cfg"
  for dtb in "${dtbs[@]}"; do
    mkdir -p "$(dirname "$root$dtb")"
    printf 'device tree %s\n' "${dtb##*/}" >"$root$dtb"
  done
  printf 'm1n1 stage 2 from m1n1-aurora\n' >"$root/usr/lib/asahi-boot/m1n1.bin"
  printf 'u-boot\n' >"$root/usr/lib/asahi-boot/u-boot-nodtb.bin"
  printf '# options\nchosen.asahi,efi-system-partition=1234\ndisplay=2560x1600\n   mitigations=off\nunknown=1\n\n' >"$root/etc/m1n1.conf"
  write_update_m1n1
  printf '%s\n' linux-aurora linux-aurora-headers m1n1-aurora >"$test_tmp/files/installed"
  {
    printf '/usr/\n/usr/lib/\n/usr/lib/modules/\n/usr/lib/modules/%s/\n/usr/lib/modules/%s/vmlinuz\n' "$kver" "$kver"
    printf '/usr/lib/modules/%s/dtbs/\n' "$kver"
    printf '%s\n' "${dtbs[@]}"
  } >"$test_tmp/files/linux-aurora"
  printf '/usr/lib/asahi-boot/\n/usr/lib/asahi-boot/m1n1.bin\n' >"$test_tmp/files/m1n1-aurora"
  printf 'usr/lib/modules/%s/kernel/drivers/gpu/drm/apple/appledrm.ko.zst\nusr/bin/init\n' "$kver" >"$test_tmp/initramfs"
  write_boot_bin "${dtbs[@]}"
}

run_check() {
  : >"$calls"
  set +e
  env -u LC_ALL -u LC_COLLATE LANG=C \
    TEST_CALLS="$calls" \
    TEST_FILES="$test_tmp/files" \
    TEST_INITRAMFS_LIST="$test_tmp/initramfs" \
    TEST_MOUNTS="$mounts" \
    TEST_ESP_DEVICE="$esp_device" \
    OMARCHY_BOOT_CHECK_ROOT="$root" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$check" linux-aurora >"$test_tmp/out" 2>"$test_tmp/err"
  status=$?
  set -e
}

expect_pass() {
  (( status == 0 )) || fail "$1 passes" "status $status: $(cat "$test_tmp/err")"
}

expect_fail() {
  local description=$1 message=$2
  (( status == 1 )) || fail "$description fails the check" "status $status: $(cat "$test_tmp/err")"
  grep -Fq "$message" "$test_tmp/err" || fail "$description is explained" "$(cat "$test_tmp/err")"
}

encrypt_root() {
  mkdir -p "$root/etc" "$root/var/lib/omarchy/provisioning"
  printf 'root UUID=abcd-ef none luks\n' >"$root/etc/crypttab"
  printf 'linux /vmlinuz-linux-aurora rd.luks.name=abcd-ef=root root=/dev/mapper/root\ninitrd /initramfs-linux-aurora.img\n' \
    >"$root/boot/grub/grub.cfg"
  printf 'usr/lib/modules/%s/kernel/x.ko\nusr/lib/systemd/systemd-cryptsetup\nusr/lib/initcpio/install/sd-encrypt\n' "$kver" \
    >"$test_tmp/initramfs"
}

# Unencrypted roots keep the existing expectations; missing install.conf is fine.
system
[[ ! -e $root/boot/efi/omarchy/install.conf ]] || fail "the fixture has no install.conf"
run_check
expect_pass "an unencrypted root with no install.conf"
pass "unencrypted roots are unchanged when install.conf is absent"

system
encrypt_root
run_check
expect_pass "an encrypted root after provisioning"
pass "encrypted roots expect rd.luks.name=, root=/dev/mapper/root, crypttab and sd-encrypt"

system
encrypt_root
printf 'linux /vmlinuz-linux-aurora root=/dev/mapper/root\ninitrd /initramfs-linux-aurora.img\n' >"$root/boot/grub/grub.cfg"
run_check
expect_fail "an encrypted root without rd.luks.name=" "does not set rd.luks.name="

system
encrypt_root
printf 'linux /vmlinuz-linux-aurora rd.luks.name=abcd-ef=root\ninitrd /initramfs-linux-aurora.img\n' >"$root/boot/grub/grub.cfg"
run_check
expect_fail "an encrypted root without mapper root" "does not set root=/dev/mapper/root"

system
encrypt_root
printf 'usr/lib/modules/%s/kernel/x.ko\nusr/bin/init\n' "$kver" >"$test_tmp/initramfs"
run_check
expect_fail "an encrypted root without sd-encrypt" "does not contain sd-encrypt"

system
encrypt_root
printf 'linux /vmlinuz-linux-aurora rd.luks.name=abcd-ef=root rd.luks.key=abcd-ef=/omarchy/luks-key:UUID=4F4D-5801 root=/dev/mapper/root\ninitrd /initramfs-linux-aurora.img\n' \
  >"$root/boot/grub/grub.cfg"
run_check
expect_fail "rd.luks.key= after provisioning" "still has rd.luks.key= after provisioning"

system
encrypt_root
printf 'linux /vmlinuz-linux-aurora rd.luks.name=abcd-ef=root rd.luks.key=abcd-ef=/omarchy/luks-key:UUID=4F4D-5801 root=/dev/mapper/root\ninitrd /initramfs-linux-aurora.img\n' \
  >"$root/boot/grub/grub.cfg"
mkdir -p "$root/boot/efi/omarchy"
printf 'throwaway' >"$root/boot/efi/omarchy/luks-key"
run_check
expect_pass "rd.luks.key= during the provisioning auto-unlock window"
pass "boot-check accepts rd.luks.key= only while a staged luks-key remains"
