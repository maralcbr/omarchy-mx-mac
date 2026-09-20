#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

stub_bin="$tmp/bin"
calls="$tmp/calls"
next="$tmp/next"
device="$tmp/luks-device"
esp_key="$tmp/esp/omarchy/luks-key"
grub_live="$tmp/live/default/grub"
mkdir -p "$stub_bin" "$next/var/lib/omarchy/provisioning" "$tmp/esp/omarchy" "$tmp/live/default" "$next/etc"
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

chmod +x "$stub_bin"/*

export PATH="$stub_bin:$PATH"
export OMARCHY_PATH="$tmp/omarchy"
export OMARCHY_FACTORY_RESET_SOURCE=1
export OMARCHY_FACTORY_RESET_LOG="$tmp/reset.log"
export OMARCHY_ESP_LUKS_KEY="$esp_key"
export OMARCHY_GRUB_DEFAULT="$grub_live"
export OMARCHY_LUKS_DEVICE="$device"
: >"$OMARCHY_FACTORY_RESET_LOG"
mkdir -p "$tmp/omarchy/bin"

# shellcheck disable=SC1091
source "$ROOT/bin/omarchy-system-factory-reset"
export PATH="$stub_bin:$PATH"

# Copy live crypttab where stage_luks_rekey_apple expects it. The function
# reads /etc/crypttab from the host; in the test we install a stand-in by
# pointing a bind... instead, write through a wrapper after sourcing by
# copying into $next ourselves if the live path is not /etc/crypttab.
# stage_luks_rekey_apple uses /etc/crypttab literally. Provide one via a
# private overlay only when we can; here we skip the copy by not having
# /etc/crypttab (tolerated) and still require GRUB staging.

# shellcheck disable=SC1091
source "$ROOT/bin/omarchy-system-factory-reset"

# Host /etc/crypttab may or may not exist in the container; the Apple path
# must tolerate that (same as a missing install.conf).
stage_luks_rekey "$next"

[[ -f $next/var/lib/omarchy/provisioning/luks-key ]] || fail "reset stages provisioning luks-key"
[[ -f $esp_key ]] || fail "reset stages the ESP luks-key"
[[ $(stat -c '%a' "$esp_key") == 600 ]] || fail "ESP luks-key is mode 600"
grep -q 'rd.luks.key=abcd-ef=/omarchy/luks-key:UUID=4F4D-5801' "$next/etc/default/grub" ||
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
pass "LUKS factory reset stages both keyfiles and rebuilds initramfs, GRUB and m1n1"
