#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/limine-boot.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls"
esp="$test_tmp/esp"
etc="$test_tmp/etc"
mkdir -p "$stub_bin" "$esp/EFI/BOOT" "$etc" "$test_tmp/share/limine" "$test_tmp/boot/grub"

printf '#!/bin/bash\nexec "$@"\n' >"$stub_bin/sudo"
printf '#!/bin/bash\nexit 0\n' >"$stub_bin/omarchy-hw-apple-silicon"
printf '#!/bin/bash\necho linux-aurora\n' >"$stub_bin/omarchy-hw-apple-kernel"
printf '#!/bin/bash\necho "systemctl $*" >>"$TEST_CALLS"\n' >"$stub_bin/systemctl"
printf '#!/bin/bash\necho "limine-snapper-sync $*" >>"$TEST_CALLS"\n' >"$stub_bin/limine-snapper-sync"
cat >"$stub_bin/findmnt" <<'SH'
#!/bin/bash
case "$*" in
  "-no TARGET $TEST_ESP") echo "$TEST_ESP" ;;
  "-no UUID /") echo mounted-root ;;
  *) exit 1 ;;
esac
SH
# The Asahi update-grub writes its EFI image to TARGET from /etc/default/update-grub.
cat >"$stub_bin/update-grub" <<'SH'
#!/bin/bash
echo "update-grub" >>"$TEST_CALLS"
target=$(sed -n 's/^TARGET="\(.*\)"$/\1/p' "$TEST_UPDATE_GRUB_DEFAULT")
[[ -n $target ]] || target=$TEST_ESP/EFI/BOOT/BOOTAA64.EFI
printf 'GRUB image\n' >"$target"
SH
# limine-update builds the UKI and writes the Omarchy block, keeping other top-level entries.
cat >"$stub_bin/limine-update" <<'SH'
#!/bin/bash
echo "limine-update" >>"$TEST_CALLS"
[[ -z ${FAIL_LIMINE_UPDATE:-} ]] || exit 1
mkdir -p "$TEST_ESP/EFI/Linux"
printf 'UKI\n' >"$TEST_ESP/EFI/Linux/omarchy_linux-aurora.efi"
if ! grep -q '^/+Omarchy' "$TEST_ESP/limine.conf"; then
  cmdline=$(sed -n 's/^KERNEL_CMDLINE\[default\]="\(.*\)"$/\1/p' "$TEST_LIMINE_DEFAULT")
  printf '/+Omarchy\n  //linux-aurora\n  protocol: efi\n  path: boot():/EFI/Linux/omarchy_linux-aurora.efi\n  cmdline: %s\n' "$cmdline" >>"$TEST_ESP/limine.conf"
fi
SH
chmod +x "$stub_bin"/*
for name in omarchy-mac-limine-cmdline omarchy-mac-limine-deploy omarchy-mac-limine-active; do
  ln -s "$ROOT/bin/$name" "$stub_bin/$name"
done

printf 'LIMINE v1\n' >"$test_tmp/share/limine/BOOTAA64.EFI"
printf 'GRUB image\n' >"$esp/EFI/BOOT/BOOTAA64.EFI"
printf 'GRUB_CMDLINE_LINUX=""\nGRUB_CMDLINE_LINUX_DEFAULT="quiet splash rootflags=x-systemd.device-timeout=0"\n' >"$etc/grub"
printf 'UUID=root-uuid / btrfs subvol=@ 0 0\n' >"$etc/fstab"

run() {
  TEST_CALLS="$calls" TEST_ESP="$esp" TEST_UPDATE_GRUB_DEFAULT="$etc/update-grub" TEST_LIMINE_DEFAULT="$etc/limine" \
  OMARCHY_PATH="$ROOT" OMARCHY_ESP="$esp" OMARCHY_LIMINE_EFI="$test_tmp/share/limine/BOOTAA64.EFI" \
  OMARCHY_GRUB_DEFAULT="$etc/grub" OMARCHY_UPDATE_GRUB_DEFAULT="$etc/update-grub" OMARCHY_LIMINE_DEFAULT="$etc/limine" \
  OMARCHY_GRUB_TARGET="$test_tmp/boot/grub/grub-aa64.efi" OMARCHY_LIMINE_BOOT_HOOKS_DIR="$etc/boot/hooks/pre.d" \
  OMARCHY_PACMAN_HOOKS_DIR="$etc/pacman.d/hooks" OMARCHY_SYSTEMD_DIR="$etc/systemd/system" \
  OMARCHY_LIMINE_GATE="$test_tmp/limine.enabled" OMARCHY_FSTAB="$etc/fstab" \
  PATH="$stub_bin:$PATH" bash -c "source '$leaf'"
}

# No gate: a GRUB Mac stays one.
: >"$calls"
run || fail "the leaf returns cleanly without the gate"
[[ ! -s $calls && ! -e $etc/limine && $(cat "$esp/EFI/BOOT/BOOTAA64.EFI") == "GRUB image" ]] ||
  fail "without the gate nothing changes" "$(cat "$calls")"
pass "Limine is opt-in"

: >"$test_tmp/limine.enabled"

# limine-update fails: GRUB keeps the U-Boot slot and the Mac is not a Limine Mac.
: >"$calls"
FAIL_LIMINE_UPDATE=1 run 2>"$test_tmp/err" || fail "the leaf returns cleanly when limine-update fails"
[[ $(cat "$esp/EFI/BOOT/BOOTAA64.EFI") == "GRUB image" ]] || fail "a failed UKI build leaves GRUB in the U-Boot slot"
[[ ! -e $etc/limine ]] || fail "a failed activation removes the Limine defaults it created"
[[ ! -e $etc/update-grub ]] || fail "a failed activation puts GRUB's update target back (none before)"
[[ $(tail -n 1 "$calls") == update-grub ]] || fail "GRUB is regenerated into the U-Boot slot after the rollback" "$(cat "$calls")"
grep -q 'GRUB stays the boot loader' "$test_tmp/err" || fail "the failure is reported" "$(cat "$test_tmp/err")"
pass "GRUB keeps the slot until the Limine menu boots the kernel"

# The full activation.
: >"$calls"
run || fail "the leaf activates Limine"
grep -Fxq "TARGET=\"$test_tmp/boot/grub/grub-aa64.efi\"" "$etc/update-grub" || fail "update-grub is retargeted away from the U-Boot slot"
[[ $(cat "$test_tmp/boot/grub/grub-aa64.efi") == "GRUB image" ]] || fail "update-grub wrote its image to the unused target"
[[ ! -e $esp/EFI/BOOT/grub-aa64.efi ]] || fail "no GRUB image is left on the ESP"
[[ $(cat "$esp/EFI/BOOT/BOOTAA64.EFI") == "LIMINE v1" ]] || fail "Limine takes the U-Boot slot"
grep -Fxq 'KERNEL_CMDLINE[default]="root=UUID=root-uuid rw rootflags=subvol=@,x-systemd.device-timeout=0 quiet splash"' "$etc/limine" ||
  fail "the Limine command line is derived from GRUB's defaults" "$(cat "$etc/limine")"
grep -Fxq 'BOOT_ORDER="linux-aurora, *, *fallback, Snapshots"' "$etc/limine" && grep -Fxq 'ENABLE_UKI=yes' "$etc/limine" ||
  fail "the Limine defaults name the kernel entry first and build a UKI"
[[ -L $etc/boot/hooks/pre.d/20-omarchy-mac-cmdline ]] || fail "the command line hook runs before every UKI rebuild"
[[ $(tr '\n' ' ' <"$calls") == "update-grub limine-update limine-snapper-sync "* ]] ||
  fail "GRUB is regenerated first, the UKI built before Limine is deployed, snapshots synced last" "$(cat "$calls")"
grep -Fxq 'timeout: 3' "$esp/limine.conf" && grep -Fq 'interface_branding: Omarchy Bootloader' "$esp/limine.conf" ||
  fail "Omarchy's Limine menu with a 3 s timeout"
! grep -q '^/GRUB' "$esp/limine.conf" || fail "the menu has no GRUB entry" "$(cat "$esp/limine.conf")"
grep -Fq 'Exec = /usr/bin/omarchy-mac-limine-deploy' "$etc/pacman.d/hooks/81-omarchy-mac-limine-deploy.hook" ||
  fail "a pacman hook redeploys Limine when the package changes"
grep -q 'systemctl enable --now limine-snapper-sync.service' "$calls" || fail "limine-snapper-sync.service (the watcher that writes snapshot entries) is enabled and started"
pass "Limine is activated the way x86 boots"

# Idempotent, and the experiment's GRUB recovery entry and resync unit are removed.
{ cat "$esp/limine.conf"; printf '\n/GRUB (recovery)\n    protocol: efi_chainload\n    path: boot():/EFI/BOOT/grub-aa64.efi\n'; } >"$test_tmp/conf"
cp "$test_tmp/conf" "$esp/limine.conf"
mkdir -p "$etc/systemd/system" && : >"$etc/systemd/system/omarchy-mac-boot-sync.service"
run || fail "a second run succeeds"
! grep -q '^/GRUB' "$esp/limine.conf" || fail "a leftover GRUB recovery entry is removed" "$(cat "$esp/limine.conf")"
grep -q '^/+Omarchy$' "$esp/limine.conf" || fail "the Omarchy block survives the cleanup"
[[ ! -e $etc/systemd/system/omarchy-mac-boot-sync.service ]] || fail "the experiment's resync unit is removed"
(( $(grep -c '^timeout: 3$' "$esp/limine.conf") == 1 )) || fail "one timeout line"
pass "re-running the leaf changes nothing that was right and cleans the experiment up"

# A newer Limine package: the ESP follows, and GRUB's recovery image is never
# overwritten with the old Limine.
printf 'LIMINE v2\n' >"$test_tmp/share/limine/BOOTAA64.EFI"
run || fail "the leaf runs after a Limine upgrade"
[[ $(cat "$esp/EFI/BOOT/BOOTAA64.EFI") == "LIMINE v2" ]] || fail "the ESP gets the new Limine"
[[ ! -e $esp/EFI/BOOT/grub-aa64.efi ]] || fail "no GRUB image appears on the ESP after a Limine upgrade"
pass "a Limine upgrade only replaces the U-Boot slot"
