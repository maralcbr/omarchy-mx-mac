#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

update="$ROOT/bin/omarchy-mac-boot-update"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls"
gate="$test_tmp/limine.enabled"
limine_default="$test_tmp/limine"
grub_default="$test_tmp/grub"
fstab="$test_tmp/fstab"
mkdir -p "$stub_bin"

for name in update-grub limine-update omarchy-mac-limine-deploy; do
  cat >"$stub_bin/$name" <<SH
#!/bin/bash
echo "$name \$*" >>"$calls"
[[ -z \${FAIL_$(tr - _ <<<"$name")-} ]] || exit 1
SH
  chmod +x "$stub_bin/$name"
done
cat >"$stub_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$stub_bin/omarchy-hw-apple-silicon"
ln -s "$ROOT/bin/omarchy-mac-limine-active" "$stub_bin/omarchy-mac-limine-active"
ln -s "$ROOT/bin/omarchy-mac-limine-cmdline" "$stub_bin/omarchy-mac-limine-cmdline"

printf 'GRUB_CMDLINE_LINUX="rd.luks.name=abc=root"\nGRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n' >"$grub_default"
printf 'UUID=root-uuid / btrfs subvol=@ 0 0\n' >"$fstab"

run() {
  OMARCHY_LIMINE_GATE="$gate" OMARCHY_LIMINE_DEFAULT="$limine_default" OMARCHY_GRUB_DEFAULT="$grub_default" \
    OMARCHY_FSTAB="$fstab" PATH="$stub_bin:$PATH" bash "$update"
}

# A GRUB Mac: no gate, no Limine defaults.
: >"$calls"
run || fail "boot update on a GRUB Mac succeeds"
[[ $(cat "$calls") == "update-grub " ]] || fail "a GRUB Mac only regenerates GRUB" "$(cat "$calls")"
pass "a GRUB Mac regenerates GRUB only"

# A Limine Mac: GRUB, then the command line, the UKI and the ESP's Limine.
: >"$gate"
printf 'ESP_PATH="/boot/efi"\nKERNEL_CMDLINE[default]="stale"\n' >"$limine_default"
: >"$calls"
run || fail "boot update on a Limine Mac succeeds"
[[ $(cat "$calls") == $'limine-update \nomarchy-mac-limine-deploy ' ]] ||
  fail "a Limine Mac rebuilds Limine and deploys it, and never runs update-grub" "$(cat "$calls")"
grep -Fxq 'KERNEL_CMDLINE[default]="root=UUID=root-uuid rw rootflags=subvol=@ rd.luks.name=abc=root quiet splash"' "$limine_default" ||
  fail "the Limine command line is re-derived from GRUB's defaults before limine-update" "$(cat "$limine_default")"
pass "a Limine Mac rebuilds Limine from GRUB's defaults file"

: >"$calls"
FAIL_limine_update=1 run && fail "a failed limine-update fails the boot update"
! grep -q omarchy-mac-limine-deploy "$calls" || fail "Limine is not deployed after a failed limine-update"
pass "a failed limine-update stops the boot update"
