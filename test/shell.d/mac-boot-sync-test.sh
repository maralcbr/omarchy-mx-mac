#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

sync_cmd="$ROOT/bin/omarchy-mac-boot-sync"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls"
boot="$test_tmp/boot"
modules="$test_tmp/modules"
cmdline="$test_tmp/cmdline"
marker="$test_tmp/snapshot-boot"
gate="$test_tmp/limine.enabled"
limine_default="$test_tmp/limine"
mkdir -p "$stub_bin" "$boot" "$modules/7.1.12-2-7-ARCH"

for name in mkinitcpio omarchy-mac-boot-update omarchy-mac-snapshot-menu limine-update; do
  cat >"$stub_bin/$name" <<SH
#!/bin/bash
echo "$name \$*" >>"$calls"
SH
  chmod +x "$stub_bin/$name"
done
printf '#!/bin/bash\nexit 0\n' >"$stub_bin/omarchy-hw-apple-silicon"
printf '#!/bin/bash\necho linux-aurora\n' >"$stub_bin/omarchy-hw-apple-kernel"
chmod +x "$stub_bin/omarchy-hw-apple-silicon" "$stub_bin/omarchy-hw-apple-kernel"
ln -s "$ROOT/bin/omarchy-mac-limine-active" "$stub_bin/omarchy-mac-limine-active"

echo linux-aurora >"$modules/7.1.12-2-7-ARCH/pkgbase"
echo running-kernel >"$modules/7.1.12-2-7-ARCH/vmlinuz"
echo older-kernel >"$boot/vmlinuz-linux-aurora"
echo 'root=UUID=x rw rootflags=subvol=@ quiet' >"$cmdline"
: >"$gate"
: >"$limine_default"

run() {
  OMARCHY_BOOT_DIR="$boot" OMARCHY_MODULES_DIR="$modules" OMARCHY_CMDLINE="$cmdline" \
    OMARCHY_SNAPSHOT_BOOT_MARKER="$marker" OMARCHY_RUNNING_KERNEL=7.1.12-2-7-ARCH \
    OMARCHY_LIMINE_GATE="$gate" OMARCHY_LIMINE_DEFAULT="$limine_default" OMARCHY_MKINITCPIO="$stub_bin/mkinitcpio" \
    PATH="$stub_bin:$PATH" bash "$sync_cmd"
}

: >"$calls"
run || fail "boot sync succeeds when /boot lags the running kernel"
[[ $(cat "$boot/vmlinuz-linux-aurora") == running-kernel ]] || fail "/boot gets the running kernel's image"
[[ $(cat "$calls") == $'mkinitcpio -P\nomarchy-mac-boot-update \nomarchy-mac-snapshot-menu refresh' ]] ||
  fail "the initramfs, both loaders and the GRUB snapshot menu are rebuilt, in that order" "$(cat "$calls")"
pass "a restored root gets /boot rebuilt for GRUB"

: >"$calls"
run || fail "boot sync succeeds when /boot is current"
[[ ! -s $calls ]] || fail "nothing is rebuilt when /boot already carries the running kernel" "$(cat "$calls")"
pass "a current /boot is left alone"

echo older-kernel >"$boot/vmlinuz-linux-aurora"
: >"$marker"
: >"$calls"
run || fail "boot sync succeeds during a snapshot boot"
[[ ! -s $calls && $(cat "$boot/vmlinuz-linux-aurora") == older-kernel ]] ||
  fail "a snapshot boot (overlay marker) writes nothing to /boot" "$(cat "$calls")"
rm -f "$marker"
echo 'root=UUID=x rw rootflags=subvol=/@/.snapshots/7/snapshot quiet' >"$cmdline"
run || fail "boot sync succeeds during a snapshot boot by cmdline"
[[ ! -s $calls ]] || fail "a snapshot boot (cmdline) writes nothing to /boot"
pass "snapshot boots never touch /boot"

# A kernel update with the reboot pending: /boot carries the new kernel and
# its modules are in this root (kernel-modules-hook kept the running ones).
echo 'root=UUID=x rw rootflags=subvol=@ quiet' >"$cmdline"
mkdir -p "$modules/7.2.0-1-1-ARCH"
echo linux-aurora >"$modules/7.2.0-1-1-ARCH/pkgbase"
echo newer-kernel >"$modules/7.2.0-1-1-ARCH/vmlinuz"
echo newer-kernel >"$boot/vmlinuz-linux-aurora"
: >"$calls"
run || fail "boot sync succeeds with a newer kernel on /boot"
[[ ! -s $calls && $(cat "$boot/vmlinuz-linux-aurora") == newer-kernel ]] ||
  fail "a newer kernel on /boot whose modules are present is never overwritten with the running one" "$(cat "$calls")"
rm -rf "$modules/7.2.0-1-1-ARCH"
pass "a pending kernel update is left alone"

echo older-kernel >"$boot/vmlinuz-linux-aurora"
rm -f "$gate"
run || fail "boot sync succeeds on a GRUB Mac"
[[ ! -s $calls && $(cat "$boot/vmlinuz-linux-aurora") == older-kernel ]] || fail "a GRUB Mac is left alone"
pass "a GRUB Mac is not resynced"
