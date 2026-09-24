#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command vercmp

migration="$ROOT/migrations/1790055026.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls"
omarchy="$test_tmp/omarchy"
versions="$test_tmp/versions"
repository="$test_tmp/repository"
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
# pacman: installed versions in $TEST_VERSIONS, the repository's in
# $TEST_REPOSITORY; -S installs the repository's version.
cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
echo "pacman $*" >>"$TEST_CALLS"
case "$1" in
  -Q) cat "$TEST_VERSIONS" ;;
  -Si)
    version=$(awk -v name="$2" '$1 == name { print $2 }' "$TEST_REPOSITORY")
    [[ -n $version ]] || exit 1
    if [[ ${LC_ALL:-} == C ]]; then
      printf 'Repository      : omarchy\nName            : %s\nVersion         : %s\n' "$2" "$version"
    else
      printf 'Repositório     : omarchy\nNome            : %s\nVersão          : %s\n' "$2" "$version"
    fi
    ;;
  -S)
    [[ -z ${TEST_INSTALL_FAILS:-} ]] || exit 1
    shift
    for arg; do
      [[ $arg == -* ]] && continue
      version=$(awk -v name="$arg" '$1 == name { print $2 }' "$TEST_REPOSITORY")
      sed -i "/^$arg /d" "$TEST_VERSIONS"
      echo "$arg ${version:-1-1}" >>"$TEST_VERSIONS"
    done
    ;;
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
  [[ ${OMARCHY_BOOT_CHECK_ALLOW_PENDING_REBOOT:-0} == 1 ]] || exit 1
  echo "Apple Silicon boot check: running kernel is 7.1.13-1-1-ARCH; linux-asahi 7.1.13-3-2-ARCH is installed from the installed linux-asahi, reboot pending"
  exit 0
fi
echo "Apple Silicon boot check: running linux-asahi 7.1.13-3-2-ARCH from the installed linux-asahi"
SH
chmod +x "$stub_bin"/*
ln -s "$ROOT/bin/omarchy-mac-limine-active" "$stub_bin/omarchy-mac-limine-active"
ln -s "$ROOT/bin/omarchy-mac-limine-enable" "$stub_bin/omarchy-mac-limine-enable"
ln -s "$ROOT/bin/omarchy-cmd-present" "$stub_bin/omarchy-cmd-present"

gate="$test_tmp/limine.enabled"
limine_default="$test_tmp/etc/limine"
pending="$test_tmp/limine-activation.pending"
mkinitcpio_conf="$test_tmp/etc/mkinitcpio.conf"
preset_dir="$test_tmp/etc/mkinitcpio.d"
reboot_blocked="$test_tmp/reboot-blocked"
mkdir -p "$mkinitcpio_conf.d" "$preset_dir"

# A Mac ready for Limine: an sd-encrypt initramfs, today's packages in the
# repository, the old limine-mkinitcpio-hook installed.
ready() {
  printf 'HOOKS=(base udev autodetect)\n' >"$mkinitcpio_conf"
  printf 'HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)\n' >"$mkinitcpio_conf.d/90-omarchy-mac.conf"
  printf 'omarchy-mac-boot 20260921-10\nlimine-mkinitcpio-hook 1.36.0-3\nlinux-asahi 7.1.13.asahi3-2\n' >"$versions"
  printf 'limine-mkinitcpio-hook 1.36.0-4\nlimine 12.9.0-1\nlimine-snapper-sync 1.30.1-1\nuboot-asahi 2026.07.asahi2-1\n' >"$repository"
  printf 'ALL_kver="/boot/vmlinuz-linux-asahi"\nPRESETS=(default fallback)\nfallback_options="-S autodetect"\n' >"$preset_dir/linux-asahi.preset"
  rm -f "$pending" "$reboot_blocked" "$stub_bin/omarchy-hw-apple-initramfs-hooks"
}

run_migration() {
  : >"$calls"
  rm -f "$gate" "$limine_default"
  status=0
  TEST_CALLS="$calls" TEST_VERSIONS="$versions" TEST_REPOSITORY="$repository" OMARCHY_PATH="$omarchy" \
    OMARCHY_LIMINE_GATE="$gate" OMARCHY_LIMINE_DEFAULT="$limine_default" OMARCHY_LIMINE_PENDING="$pending" \
    OMARCHY_MKINITCPIO_CONF="$mkinitcpio_conf" OMARCHY_MKINITCPIO_ALPM="$stub_bin/mkinitcpio-alpm" \
    OMARCHY_MKINITCPIO_PRESET_DIR="$preset_dir" OMARCHY_REBOOT_BLOCKED="$reboot_blocked" \
    PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >"$test_tmp/out" 2>"$test_tmp/err" || status=$?
}

run_migration_keeping_block() {
  : >"$calls"
  status=0
  TEST_CALLS="$calls" TEST_VERSIONS="$versions" TEST_REPOSITORY="$repository" OMARCHY_PATH="$omarchy" \
    OMARCHY_LIMINE_GATE="$gate" OMARCHY_LIMINE_DEFAULT="$limine_default" OMARCHY_LIMINE_PENDING="$pending" \
    OMARCHY_MKINITCPIO_CONF="$mkinitcpio_conf" OMARCHY_MKINITCPIO_ALPM="$stub_bin/mkinitcpio-alpm" \
    OMARCHY_MKINITCPIO_PRESET_DIR="$preset_dir" OMARCHY_REBOOT_BLOCKED="$reboot_blocked" \
    PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >"$test_tmp/out" 2>"$test_tmp/err" || status=$?
}

# Every case where the Mac is not ready: GRUB stays, the migration succeeds so
# the ones after it run, and the marker makes omarchy update try again.
expect_wait() {
  local description=$1 reason=$2
  (( status == 0 )) || fail "$description does not fail the migration" "$(cat "$test_tmp/err")"
  grep -Fq "Limine waits: $reason" "$test_tmp/err" || fail "$description says why Limine waits" "$(cat "$test_tmp/err")"
  [[ -e $pending ]] || fail "$description leaves the activation to retry"
}
expect_untouched() {
  [[ ! -e $gate ]] && ! grep -q '^pacman -S \|^leaf' "$calls" ||
    fail "$1 installs nothing and writes no gate" "$(cat "$calls")"
}

# Issue #238: an ESP neither at /boot/efi nor at /boot.
ready
run_migration
expect_wait "a Mac without a system ESP" "the system ESP is not mounted"
expect_untouched "a Mac without a system ESP"
pass "a Mac without a system ESP keeps GRUB and waits"

export TEST_FOUND_ESP="$test_tmp/boot"

# A busybox initramfs unlocks the disk with encrypt; Limine's UKI needs sd-encrypt.
ready
printf 'HOOKS=(base udev autodetect modconf block keyboard keymap encrypt filesystems fsck)\n' >"$mkinitcpio_conf.d/90-omarchy-mac.conf"
run_migration
expect_wait "a busybox encrypt initramfs" "the encrypted disk is unlocked by a busybox initramfs"
expect_untouched "a busybox encrypt initramfs"
ready
rm -f "$mkinitcpio_conf" "$mkinitcpio_conf.d"/*
run_migration
expect_wait "unreadable initramfs HOOKS" "the mkinitcpio HOOKS of this Mac's initramfs cannot be read"
expect_untouched "unreadable initramfs HOOKS"
# Limine's UKI takes mkinitcpio.conf's HOOKS, GRUB's initramfs the preset's:
# encrypt in either waits, and a preset that adds hooks or names its own
# configuration cannot be read without omarchy-hw-apple-initramfs-hooks.
ready
printf 'default_options="-A encrypt"\n' >>"$preset_dir/linux-asahi.preset"
run_migration
expect_wait "a preset that adds hooks" "the mkinitcpio HOOKS of this Mac's initramfs cannot be read"
ready
printf 'default_config="/etc/mkinitcpio-busybox.conf"\n' >>"$preset_dir/linux-asahi.preset"
run_migration
expect_wait "a preset with its own configuration" "the mkinitcpio HOOKS of this Mac's initramfs cannot be read"
ready
printf 'default_options=(-c /etc/mkinitcpio-busybox.conf)\n' >>"$preset_dir/linux-asahi.preset"
run_migration
expect_wait "a preset array naming its own configuration" "the mkinitcpio HOOKS of this Mac's initramfs cannot be read"
ready
chmod 000 "$preset_dir/linux-asahi.preset"
run_migration
chmod 644 "$preset_dir/linux-asahi.preset"
expect_wait "an unreadable preset" "the mkinitcpio HOOKS of this Mac's initramfs cannot be read"
for assignment in 'export default_options="-c /etc/mkinitcpio-busybox.conf"' 'default_options+=(-c /etc/mkinitcpio-busybox.conf)' 'PRESETS+=(busybox)\nbusybox_options="-A encrypt"'; do
  ready
  printf "$assignment\n" >>"$preset_dir/linux-asahi.preset"
  run_migration
  expect_wait "a preset with $assignment" "the mkinitcpio HOOKS of this Mac's initramfs cannot be read"
done
# A value that goes on past its first line is read whole.
ready
printf 'default_options="-S autodetect\n  -c /etc/mkinitcpio-busybox.conf"\n' >>"$preset_dir/linux-asahi.preset"
run_migration
expect_wait "a preset option on a second line" "the mkinitcpio HOOKS of this Mac's initramfs cannot be read"
# Arch's own preset settings: no options, empty ones, the fallback's -S autodetect.
for assignment in 'default_options=""' 'default_options=()' "default_options=('')" 'fallback_options=(-S autodetect)'; do
  ready
  printf '%s\n' "$assignment" >>"$preset_dir/linux-asahi.preset"
  run_migration
  (( status == 0 )) && [[ -e $gate && ! -e $pending ]] || fail "a preset with $assignment activates Limine" "$(cat "$test_tmp/err")"
done
# A drop-in the check cannot read (it runs as root; this one fails for anyone).
ready
printf 'HOOKS=(base udev block encrypt filesystems)\n' >"$mkinitcpio_conf.d/95-local.conf"
chmod 000 "$mkinitcpio_conf.d/95-local.conf"
run_migration
rm -f "$mkinitcpio_conf.d/95-local.conf"
expect_wait "an unreadable drop-in" "the mkinitcpio HOOKS of this Mac's initramfs cannot be read"
# mkinitcpio reads drop-ins in version order: 100-local.conf comes last.
ready
printf 'HOOKS=(base udev block encrypt filesystems)\n' >"$mkinitcpio_conf.d/100-local.conf"
run_migration
rm -f "$mkinitcpio_conf.d/100-local.conf"
expect_wait "a busybox drop-in sorted after Omarchy's by version" "the encrypted disk is unlocked by a busybox initramfs"
ready
printf '#!/bin/bash\necho "base udev block encrypt filesystems"\n' >"$stub_bin/omarchy-hw-apple-initramfs-hooks"
chmod +x "$stub_bin/omarchy-hw-apple-initramfs-hooks"
run_migration
expect_wait "a busybox encrypt preset" "the encrypted disk is unlocked by a busybox initramfs"
expect_untouched "a busybox encrypt preset"
ready
printf '#!/bin/bash\necho "base systemd block sd-encrypt filesystems"\n' >"$stub_bin/omarchy-hw-apple-initramfs-hooks"
chmod +x "$stub_bin/omarchy-hw-apple-initramfs-hooks"
printf 'HOOKS=(base udev block encrypt filesystems)\n' >"$mkinitcpio_conf.d/90-omarchy-mac.conf"
run_migration
expect_wait "a busybox encrypt mkinitcpio.conf under an sd-encrypt preset" "the encrypted disk is unlocked by a busybox initramfs"
pass "a busybox encrypt Mac keeps GRUB, and unknown HOOKS wait too"

# Packages: the repository must carry limine-mkinitcpio-hook 1.36.0-4 (which
# leaves mkinitcpio's kernel hook in place) and omarchy-mac-boot
# 20260921-10 must be installed, by exact name.
ready
printf 'limine-mkinitcpio-hook 1.36.0-3\n' >"$repository"
run_migration
expect_wait "an old limine-mkinitcpio-hook in the repository" "the package repository has no limine-mkinitcpio-hook 1.36.0-4"
expect_untouched "an old limine-mkinitcpio-hook in the repository"
ready
sed -i 's/^omarchy-mac-boot .*/omarchy-mac-boot 20260921-9/' "$versions"
run_migration
expect_wait "an old omarchy-mac-boot" "omarchy-mac-boot 20260921-10 or newer is not installed (20260921-9)"
expect_untouched "an old omarchy-mac-boot"
ready
sed -i 's/^omarchy-mac-boot .*/omarchy-apple-boot 20260921-10/' "$versions"
run_migration
expect_wait "a package that is not omarchy-mac-boot" "omarchy-mac-boot 20260921-10 or newer is not installed (none)"
ready
TEST_INSTALL_FAILS=1 run_migration
expect_wait "a failed package install" "the Limine packages did not install"
[[ ! -e $gate ]] || fail "a failed package install writes no gate"
# An installed 1.36.0-4 stays out of the transaction, so a repository pinned
# to an older snapshot cannot downgrade it.
ready
sed -i 's/^limine-mkinitcpio-hook .*/limine-mkinitcpio-hook 1.36.0-4/' "$versions"
printf 'limine-mkinitcpio-hook 1.36.0-3\nlimine 12.9.0-1\n' >"$repository"
run_migration
(( status == 0 )) && [[ -e $gate && ! -e $pending ]] || fail "an installed 1.36.0-4 activates Limine" "$(cat "$test_tmp/err")"
grep -q '^pacman -S .*limine-mkinitcpio-hook' "$calls" && fail "an installed 1.36.0-4 is not reinstalled" "$(cat "$calls")"
grep -Fxq 'limine-mkinitcpio-hook 1.36.0-4' "$versions" || fail "limine-mkinitcpio-hook is never downgraded"
pass "Limine waits for limine-mkinitcpio-hook 1.36.0-4 and omarchy-mac-boot 20260921-10"

ready
run_migration
(( status == 0 )) || fail "the migration activates Limine" "$(cat "$test_tmp/err")"
[[ -e $gate ]] && grep -q '^leaf$' "$calls" || fail "the migration writes the gate and runs the leaf" "$(cat "$calls")"
grep -Fxq 'limine-mkinitcpio-hook 1.36.0-4' "$versions" || fail "limine-mkinitcpio-hook is upgraded to 1.36.0-4"
[[ ! -e $pending ]] || fail "an activated, verified Mac has nothing left to retry"
pass "a ready Mac with its ESP at /boot activates Limine"

# Issue #235: the same update installed a new kernel. The Limine files are
# verified; the next update verifies again after the reboot.
ready
TEST_NEW_KERNEL=1 run_migration
(( status == 0 )) || fail "a kernel waiting for the reboot does not fail the migration" "$(cat "$test_tmp/err")"
grep -Fq 'boot-check linux-asahi pending=1' "$calls" || fail "the boot check allows the pending reboot" "$(cat "$calls")"
grep -Fq 'reboot to start the new kernel' "$test_tmp/out" || fail "the owner is told to reboot" "$(cat "$test_tmp/out")"
[[ -e $pending ]] || fail "the next update verifies again once the new kernel runs"
pass "a new kernel waiting for the reboot is not a failed migration"

# A kernel updated while the old limine-mkinitcpio-hook shadowed mkinitcpio's
# hook never reached /boot; mkinitcpio's hook script installs it before the
# check.
ready
TEST_STALE_BOOT=1 run_migration
(( status == 0 )) || fail "a stale /boot kernel is installed again" "$(cat "$test_tmp/err")"
grep -Fxq 'mkinitcpio-alpm install cwd=/ targets=usr/lib/modules/7.1.13-3-2-ARCH/vmlinuz' "$calls" ||
  fail "mkinitcpio's hook script gets the kernel image, from /" "$(cat "$calls")"
[[ $(grep -n '^mkinitcpio-alpm' "$calls" | cut -d: -f1) -lt $(grep -n '^boot-check' "$calls" | cut -d: -f1) ]] ||
  fail "the kernel is installed before the boot check" "$(cat "$calls")"
ready
run_migration
! grep -q '^mkinitcpio-alpm' "$calls" || fail "a current /boot kernel is left alone" "$(cat "$calls")"
ready
TEST_STALE_BOOT=1 TEST_MKINITCPIO_FAILS=1 run_migration
(( status == 0 )) && [[ -e $pending ]] && grep -Fxq 'Limine boots this Mac but is not verified: the linux-asahi kernel could not be installed under /boot' "$reboot_blocked" ||
  fail "a failed kernel install after deployment blocks the reboot and retries" "$(cat "$test_tmp/err")"
pass "a kernel the old hook kept from /boot is installed before the check"

# Past the leaf's point of no return the U-Boot slot holds Limine: a failure
# there blocks the reboot until an update verifies it.
ready
TEST_CHECK_FAILS=1 run_migration
(( status == 0 )) && [[ -e $pending ]] || fail "boot files that do not verify do not fail the migration"
grep -Fq 'Limine boots this Mac but is not verified: the Limine boot files did not verify. Do not reboot' "$test_tmp/err" ||
  fail "a deployed Limine that does not verify says not to reboot" "$(cat "$test_tmp/err")"
grep -Fxq 'Limine boots this Mac but is not verified: the Limine boot files did not verify' "$reboot_blocked" ||
  fail "a deployed Limine that does not verify blocks the reboot"
TEST_NEW_KERNEL=1 run_migration_keeping_block
(( status == 0 )) && [[ ! -e $reboot_blocked && -e $pending ]] ||
  fail "a retry verified up to a pending reboot lifts its block and verifies again later" "$(cat "$test_tmp/err")"
TEST_CHECK_FAILS=1 run_migration_keeping_block
run_migration_keeping_block
(( status == 0 )) && [[ ! -e $reboot_blocked && ! -e $pending ]] || fail "a verified retry lifts its reboot block" "$(cat "$test_tmp/err")"
ready
printf 'the Aurora kernel switch could not be verified\n' >"$reboot_blocked"
run_migration_keeping_block
grep -q 'Aurora' "$reboot_blocked" || fail "another step's reboot block is left alone"
ready
TEST_LEAF_DECLINES=1 run_migration
expect_wait "a leaf that declines" "Limine was not activated"
pass "failures never stop the migrations after this one, and the activation retries"
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
