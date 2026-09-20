#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

stub_bin="$tmp/bin"
calls="$tmp/calls"
next="$tmp/next"
device="$tmp/luks-device"
boot_key="$tmp/boot/omarchy/luks-key"
grub_live="$tmp/live/default/grub"
mkdir -p "$stub_bin" "$next/var/lib/omarchy/provisioning" "$tmp/boot/omarchy" "$tmp/live/default" "$next/etc"
: >"$calls"
: >"$device"

printf 'GRUB_CMDLINE_LINUX="rd.luks.name=abcd-ef=root root=/dev/mapper/root quiet"\n' >"$grub_live"
printf 'root UUID=abcd-ef none luks\n' >"$tmp/live/crypttab"
# The live crypttab is copied from /etc/crypttab; tests point GRUB_DEFAULT at
# the live copy and install a fake /etc via a stub `install`.

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/gum" <<SH
#!/bin/bash
printf 'gum %s\n' "\$*" >>"$calls"
if [[ \$1 == input ]]; then
  printf '%s' "current-pass"
  exit 0
fi
exit 0
SH

cat >"$stub_bin/cryptsetup" <<SH
#!/bin/bash
printf 'cryptsetup %s\n' "\$*" >>"$calls"
case "\$1" in
  open) exit 0 ;;
  luksAddKey) exit 0 ;;
  luksUUID) echo abcd-ef; exit 0 ;;
  *) exit 1 ;;
esac
SH

cat >"$stub_bin/chroot" <<SH
#!/bin/bash
printf 'chroot %s\n' "\$*" >>"$calls"
shift
"\$@"
SH

cat >"$stub_bin/mkinitcpio" <<SH
#!/bin/bash
printf 'mkinitcpio %s\n' "\$*" >>"$calls"
exit 0
SH

cat >"$stub_bin/update-grub" <<SH
#!/bin/bash
printf 'update-grub %s\n' "\$*" >>"$calls"
exit 0
SH

cat >"$stub_bin/update-m1n1" <<SH
#!/bin/bash
printf 'update-m1n1 %s\n' "\$*" >>"$calls"
exit 0
SH

cat >"$stub_bin/mount" <<SH
#!/bin/bash
printf 'mount %s\n' "\$*" >>"$calls"
exit 0
SH

cat >"$stub_bin/umount" <<SH
#!/bin/bash
printf 'umount %s\n' "\$*" >>"$calls"
exit 0
SH

cat >"$stub_bin/btrfs" <<SH
#!/bin/bash
printf 'btrfs %s\n' "\$*" >>"$calls"
exit 0
SH

cat >"$stub_bin/passwd" <<SH
#!/bin/bash
exit 0
SH

chmod +x "$stub_bin"/*

export PATH="$stub_bin:$PATH"
export OMARCHY_PATH="$tmp/omarchy"
export OMARCHY_FACTORY_RESET_SOURCE=1
export OMARCHY_FACTORY_RESET_LOG="$tmp/reset.log"
export OMARCHY_BOOT_LUKS_KEY="$boot_key"
export OMARCHY_GRUB_DEFAULT="$grub_live"
export OMARCHY_LUKS_DEVICE="$device"
: >"$OMARCHY_FACTORY_RESET_LOG"
mkdir -p "$tmp/omarchy/bin"

# shellcheck disable=SC1091
source "$ROOT/bin/omarchy-system-factory-reset"
export PATH="$stub_bin:$PATH"

stage_luks_rekey "$next"

[[ -f $next/var/lib/omarchy/provisioning/luks-key ]] || fail "reset stages provisioning luks-key"
[[ -f $boot_key ]] || fail "reset stages the Boot-partition luks-key"
[[ $(stat -c '%a' "$boot_key") == 600 ]] || fail "Boot-partition luks-key is mode 600"
grep -q 'rd.luks.key=abcd-ef=/omarchy/luks-key:UUID=4f4d5801-424f-4f54-8000-000000000001' "$next/etc/default/grub" ||
  fail "reset adds rd.luks.key= to the factory GRUB cmdline" "$(cat "$next/etc/default/grub")"
[[ ! -e $next/etc/omarchy/provisioning.key ]] || fail "Apple reset does not embed a Limine UKI keyfile"
[[ ! -e $next/etc/limine-entry-tool.d/99-omarchy-provisioning-unlock.conf ]] ||
  fail "Apple reset does not write limine-entry-tool drop-ins"
grep -F 'cryptsetup luksAddKey' "$calls" >/dev/null || fail "reset adds a throwaway LUKS key"

: >"$calls"
rebuild_next_boot "$next"
grep -F 'mkinitcpio -P' "$calls" >/dev/null || fail "reset rebuilds the initramfs" "$(cat "$calls")"
grep -F 'update-grub' "$calls" >/dev/null || fail "reset regenerates grub.cfg" "$(cat "$calls")"
grep -F 'update-m1n1' "$calls" >/dev/null || fail "reset regenerates m1n1" "$(cat "$calls")"
! grep -F 'limine-update' "$calls" >/dev/null || fail "Apple reset does not call limine-update"

factory="$tmp/factory"
mkdir -p "$factory/etc" \
  "$factory/var/lib/omarchy/mac-first-boot" \
  "$factory/var/lib/omarchy/provisioning" \
  "$factory/boot/efi/omarchy" \
  "$factory/boot/omarchy"
: >"$factory/etc/passwd"
: >"$factory/etc/machine-id"
touch "$factory/var/lib/omarchy/mac-first-boot/pending" \
  "$factory/var/lib/omarchy/mac-first-boot/install.conf" \
  "$factory/var/lib/omarchy/provisioning/pending" \
  "$factory/var/lib/omarchy/provisioning/wipe-pending" \
  "$factory/boot/efi/omarchy/install.conf"
printf 'format=1\nphase=finished\npartition=p\nluks_uuid=u\n' >"$factory/boot/omarchy/encrypt.state"
sanitize_factory_baseline "$factory"
[[ ! -e $factory/var/lib/omarchy/mac-first-boot/pending ]] || fail "@factory does not keep mac-first-boot/pending"
[[ ! -e $factory/var/lib/omarchy/mac-first-boot/install.conf ]] || fail "@factory does not keep install.conf"
[[ ! -e $factory/var/lib/omarchy/provisioning/pending ]] || fail "@factory does not keep provisioning/pending"
[[ ! -e $factory/var/lib/omarchy/provisioning/wipe-pending ]] || fail "@factory does not keep wipe-pending"
[[ ! -e $factory/boot/efi/omarchy/install.conf ]] || fail "@factory does not keep the ESP install.conf"
[[ ! -e $factory/boot/omarchy/encrypt.state ]] || fail "@factory does not keep encrypt.state"

cloned="$tmp/cloned"
mkdir -p "$cloned/var/lib/omarchy/mac-first-boot" "$cloned/boot/omarchy" "$cloned/boot/efi/omarchy"
touch "$cloned/var/lib/omarchy/mac-first-boot/pending" \
  "$cloned/var/lib/omarchy/mac-first-boot/install.conf" \
  "$cloned/boot/efi/omarchy/install.conf"
printf 'format=1\nphase=finished\n' >"$cloned/boot/omarchy/encrypt.state"
scrub_factory_boot_state "$cloned"
arm_reset_markers "$cloned"
[[ -f $cloned/var/lib/omarchy/mac-first-boot/pending ]] || fail "reset re-arms mac-first-boot/pending"
[[ -f $cloned/var/lib/omarchy/provisioning/pending ]] || fail "reset re-arms provisioning/pending"
[[ -f $cloned/var/lib/omarchy/provisioning/wipe-pending ]] || fail "reset re-arms wipe-pending"
[[ ! -e $cloned/var/lib/omarchy/mac-first-boot/install.conf ]] || fail "reset next root does not keep install.conf"
[[ ! -e $cloned/boot/efi/omarchy/install.conf ]] || fail "reset next root does not keep the ESP install.conf"
[[ ! -e $cloned/boot/omarchy/encrypt.state ]] || fail "reset next root does not keep encrypt.state"
pass "LUKS factory reset stages both keyfiles, re-arms both markers, and keeps @factory clean"
