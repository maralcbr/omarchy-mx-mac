#!/bin/bash
#
# The busybox kernel line repair puts back what 1790003445 and the GRUB
# console leaf took from a Mac booting mkinitcpio's busybox init: the second
# rootflags= comes off, and an encrypted root gets its cryptdevice= back
# (the one this boot unlocked with, or one traced from the live mapping).
# grub.cfg is regenerated once and verified: one rootflags= carrying subvol=
# and the cryptdevice= on every kernel entry. A systemd initramfs, a Mac
# already right, a Limine Mac and a non-Apple machine are left alone.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1790226002.sh"
damaged="$ROOT/test/fixtures/grub/default-legacy-luks-damaged"
busybox="$ROOT/test/fixtures/mkinitcpio/busybox-encrypt.conf"
systemd="$ROOT/test/fixtures/mkinitcpio/systemd.conf"
luks_uuid=0422663f-9969-4953-900f-b342703b7e84

grep -Fq "1790226002.sh) printf 'run" "$ROOT/bin/omarchy-migrate" || fail "Apple Silicon runs the repair migration"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/conf.d"
export CALL_LOG="$tmp/calls"
export PATH="$tmp/bin:$ROOT/bin:$PATH"
printf '#!/bin/bash\nexit "${APPLE:-0}"\n' >"$tmp/bin/omarchy-hw-apple-silicon"
printf '#!/bin/bash\n[[ ${TEST_MV_FAIL:-0} == 1 && $1 == mv ]] && exit 1\nexec "$@"\n' >"$tmp/bin/sudo"
printf '#!/bin/bash\nexit 0\n' >"$tmp/bin/grub-probe"
printf '#!/bin/bash\nexit 0\n' >"$tmp/bin/grub-mkconfig"
# update-grub renders the entries the way 10_linux does: rootflags=subvol=
# in front of GRUB_CMDLINE_LINUX for a subvolume root, and a recovery entry
# without GRUB_CMDLINE_LINUX_DEFAULT.
cat >"$tmp/bin/update-grub" <<'SH'
#!/bin/bash
echo update-grub >>"$CALL_LOG"
source "$OMARCHY_GRUB_DEFAULT"
line=$GRUB_CMDLINE_LINUX
[[ ${TEST_FSROOT:-/} == / ]] || line="rootflags=subvol=${TEST_FSROOT#/} $line"
[[ -z ${TEST_EXTRA_ROOTFLAGS:-} ]] || line="$line $TEST_EXTRA_ROOTFLAGS"
# Another installation's entry (os-prober) is not this root's to judge.
[[ -z ${TEST_FOREIGN:-} ]] || printf "menuentry 'Other Linux' {\n\tlinux\t/Image root=UUID=0ther000-0000-4000-8000-000000000002 rw rootflags=subvol=@ rootflags=noatime\n}\n" >>"$OMARCHY_GRUB_CFG.foreign"
{
  printf "menuentry 'Arch Linux' {\n\tlinux\t/vmlinuz-linux-asahi root=UUID=5e1c0d3a-0000-4000-8000-000000000001 rw %s %s\n\tinitrd\t/initramfs-linux-asahi.img\n}\n" "$line" "$GRUB_CMDLINE_LINUX_DEFAULT"
  printf "menuentry 'Arch Linux (fallback)' {\n\tlinux\t/vmlinuz-linux-asahi root=UUID=5e1c0d3a-0000-4000-8000-000000000001 rw %s single\n}\n" "$line"
} >"$OMARCHY_GRUB_CFG"
[[ ! -f $OMARCHY_GRUB_CFG.foreign ]] || { cat "$OMARCHY_GRUB_CFG.foreign" >>"$OMARCHY_GRUB_CFG"; rm "$OMARCHY_GRUB_CFG.foreign"; }
SH
cat >"$tmp/bin/findmnt" <<'SH'
#!/bin/bash
case "$*" in
  "-no SOURCE /") echo "$TEST_ROOT_SOURCE[${TEST_FSROOT:-/}]" ;;
  "-no FSROOT /") echo "${TEST_FSROOT:-/}" ;;
  "-no UUID /") echo 5e1c0d3a-0000-4000-8000-000000000001 ;;
  *) exit 1 ;;
esac
SH
cat >"$tmp/bin/lsblk" <<'SH'
#!/bin/bash
case "$*" in
  "-nsrpo NAME,TYPE,FSTYPE $TEST_ROOT_SOURCE") printf '%b' "$TEST_CHAIN" ;;
  "-ndo UUID /dev/nvme0n1p5") echo "${TEST_LUKS_UUID:-}" ;;
  *) exit 1 ;;
esac
SH
cat >"$tmp/bin/cryptsetup" <<'SH'
#!/bin/bash
[[ $* == "status root" ]] || exit 1
printf '/dev/mapper/root is active and is in use.\n  type:    LUKS2\n  cipher:  aes-xts-plain64\n'
[[ ${TEST_DISCARDS:-0} == 1 ]] && printf '  flags:   discards \n'
exit 0
SH
printf '#!/bin/bash\nexit 1\n' >"$tmp/bin/blkid"
printf '#!/bin/bash\nexit 0\n' >"$tmp/bin/limine-update"
chmod +x "$tmp/bin"/*
rm "$tmp/bin/limine-update"

export TEST_ROOT_SOURCE=/dev/mapper/root
export TEST_CHAIN="/dev/mapper/root crypt btrfs\n/dev/nvme0n1p5 part crypto_LUKS\n/dev/nvme0n1 disk \n"
export TEST_LUKS_UUID=$luks_uuid
export TEST_FSROOT=/@

run() {
  : >"$CALL_LOG"
  OMARCHY_GRUB_DEFAULT="$tmp/grub" OMARCHY_GRUB_CFG="$tmp/grub.cfg" OMARCHY_GRUB_BACKUP_DIR="$tmp/backups" \
  OMARCHY_PROC_CMDLINE="$tmp/cmdline" OMARCHY_MKINITCPIO_CONF="${MKINITCPIO_CONF:-$busybox}" \
  OMARCHY_MKINITCPIO_CONF_DIR="$tmp/conf.d" OMARCHY_MKINITCPIO_PRESET_DIR="$tmp/presets" \
  OMARCHY_MKINITCPIO_KERNEL=linux-asahi \
  OMARCHY_LIMINE_GATE="$tmp/limine.enabled" OMARCHY_LIMINE_DEFAULT="$tmp/limine" \
    bash -euo pipefail "$migration" >"$tmp/out" 2>&1
}

kernel_lines() {
  grep -E '^[[:space:]]*linux[[:space:]]' "$tmp/grub.cfg"
}

# The damaged legacy Mac: busybox encrypt, a LUKS root, the wait added.
cp "$damaged" "$tmp/grub"
printf 'BOOT_IMAGE=/vmlinuz-linux-asahi root=UUID=5e1c0d3a-0000-4000-8000-000000000001 rw quiet\n' >"$tmp/cmdline"
TEST_DISCARDS=1 run || fail "the repair runs: $(<"$tmp/out")"
grep -Fxq "GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$luks_uuid:root:allow-discards\"" "$tmp/grub" ||
  fail "the wait comes off and cryptdevice= comes back, with the mapping's discards: $(<"$tmp/grub")"
grep -Fxq 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=0 systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0 plymouth.ignore-serial-consoles"' "$tmp/grub" ||
  fail "GRUB_CMDLINE_LINUX_DEFAULT is untouched: $(<"$tmp/grub")"
diff <(grep -v '^GRUB_CMDLINE_LINUX=' "$damaged") <(grep -v '^GRUB_CMDLINE_LINUX=' "$tmp/grub") >/dev/null ||
  fail "nothing else in the defaults changes: $(<"$tmp/grub")"
cmp -s "$damaged" "$tmp/backups/grub.pre-cmdline-repair" || fail "the damaged defaults are backed up"
[[ $(<"$CALL_LOG") == update-grub ]] || fail "grub.cfg is regenerated once: $(<"$CALL_LOG")"
[[ $(kernel_lines | wc -l) == 2 ]] || fail "grub.cfg has both kernel entries: $(<"$tmp/grub.cfg")"
while read -r entry; do
  [[ $(grep -o 'rootflags=' <<<"$entry" | wc -l) == 1 ]] && [[ $entry == *" rootflags=subvol=@ "* ]] ||
    fail "every entry carries one rootflags=, subvol=@: $entry"
  [[ $entry == *" cryptdevice=UUID=$luks_uuid:root:allow-discards"* ]] || fail "every entry unlocks the root: $entry"
done < <(kernel_lines)
pass "a damaged busybox Mac gets one rootflags=subvol=@ and its cryptdevice= back"

cp "$tmp/grub" "$tmp/repaired"
TEST_DISCARDS=1 run || fail "a second run passes: $(<"$tmp/out")"
[[ ! -s $CALL_LOG ]] && cmp -s "$tmp/grub" "$tmp/repaired" || fail "a repaired Mac is left alone: $(<"$CALL_LOG")"
pass "the repair is idempotent"

# The cryptdevice= this boot unlocked with (typed at the GRUB menu) keeps
# its options when it names the same partition and mapping.
cp "$damaged" "$tmp/grub"
rm -rf "$tmp/backups"
printf 'BOOT_IMAGE=/vmlinuz-linux-asahi root=UUID=x rw rootflags=subvol=@ cryptdevice=UUID=%s:root:allow-discards,no-read-workqueue\n' "$luks_uuid" >"$tmp/cmdline"
run || fail "the repair runs with a booted cryptdevice=: $(<"$tmp/out")"
grep -Fxq "GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$luks_uuid:root:allow-discards,no-read-workqueue\"" "$tmp/grub" ||
  fail "the booted cryptdevice= is the one restored: $(<"$tmp/grub")"
printf 'BOOT_IMAGE=/vmlinuz-linux-asahi cryptdevice=UUID=11111111-2222-3333-4444-555555555555:root:allow-discards\n' >"$tmp/cmdline"
cp "$damaged" "$tmp/grub"
run || fail "the repair runs with a foreign booted cryptdevice=: $(<"$tmp/out")"
grep -Fxq "GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$luks_uuid:root\"" "$tmp/grub" ||
  fail "a booted cryptdevice= for another partition is not copied: $(<"$tmp/grub")"
pass "the booted cryptdevice= is kept only when it names this root"

# Verification: a grub.cfg that still passes two rootflags= is refused and
# the defaults go back as they were.
cp "$damaged" "$tmp/grub"
: >"$tmp/cmdline"
if TEST_EXTRA_ROOTFLAGS=rootflags=noatime run; then fail "a grub.cfg with two rootflags= fails the repair"; fi
cmp -s "$damaged" "$tmp/grub" || fail "a failed verification restores the defaults: $(<"$tmp/grub")"
[[ $(grep -c update-grub "$CALL_LOG") == 2 ]] || fail "the restored defaults are regenerated: $(<"$CALL_LOG")"
grep -Fq 'will retry later' "$tmp/out" || fail "the failure says it retries: $(<"$tmp/out")"
pass "a regeneration that does not verify is rolled back and retried"

# A step that fails after the backup (the rename into place) rolls back too.
cp "$damaged" "$tmp/grub"
if TEST_MV_FAIL=1 run; then fail "a failed rename fails the repair"; fi
cmp -s "$damaged" "$tmp/grub" || fail "a failed rename leaves the defaults whole: $(<"$tmp/grub")"
grep -Fq 'will retry later' "$tmp/out" || fail "the failed step is reported: $(<"$tmp/out")"
pass "any failure after the first edit rolls back"

# Another installation's entry in grub.cfg does not fail the verification.
cp "$damaged" "$tmp/grub"
TEST_FOREIGN=1 run || fail "a foreign entry does not fail the repair: $(<"$tmp/out")"
grep -Fq 'Other Linux' "$tmp/grub.cfg" && grep -Fxq "GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$luks_uuid:root\"" "$tmp/grub" ||
  fail "the repair lands beside a foreign entry: $(<"$tmp/grub")"
pass "only this root's kernel entries are verified"

# A busybox Mac without encryption: only the wait comes off.
printf 'HOOKS=(base asahi udev autodetect modconf kms keyboard block filesystems fsck)\n' >"$tmp/plain.conf"
printf 'GRUB_CMDLINE_LINUX="zswap.enabled=0 rootflags=x-systemd.device-timeout=0"\nGRUB_CMDLINE_LINUX_DEFAULT="quiet"\n' >"$tmp/grub"
TEST_ROOT_SOURCE=/dev/nvme0n1p6 TEST_CHAIN="/dev/nvme0n1p6 part btrfs\n/dev/nvme0n1 disk \n" \
  MKINITCPIO_CONF="$tmp/plain.conf" run || fail "an unencrypted busybox Mac runs: $(<"$tmp/out")"
grep -Fxq 'GRUB_CMDLINE_LINUX="zswap.enabled=0"' "$tmp/grub" || fail "only the wait comes off: $(<"$tmp/grub")"
pass "an unencrypted busybox Mac loses the second rootflags= and gains nothing"

# The encrypt hook with a root that does not trace to LUKS: no cryptdevice= is guessed.
printf 'GRUB_CMDLINE_LINUX="rootflags=x-systemd.device-timeout=0"\n' >"$tmp/grub"
TEST_ROOT_SOURCE=/dev/nvme0n1p6 TEST_CHAIN="/dev/nvme0n1p6 part btrfs\n" run || fail "an untraceable root runs: $(<"$tmp/out")"
grep -Fxq 'GRUB_CMDLINE_LINUX=""' "$tmp/grub" || fail "no cryptdevice= is guessed: $(<"$tmp/grub")"
grep -Fq 'does not trace to a LUKS partition' "$tmp/out" || fail "the skip is explained: $(<"$tmp/out")"
pass "cryptdevice= is restored only for a root traced to its LUKS partition"

# Left alone: a systemd initramfs (the wait belongs there), a busybox Mac
# already carrying its cryptdevice= and no wait, a Limine Mac, a non-Apple one.
cp "$damaged" "$tmp/grub"
MKINITCPIO_CONF=$systemd run || fail "a systemd Mac runs: $(<"$tmp/out")"
cmp -s "$damaged" "$tmp/grub" && [[ ! -s $CALL_LOG ]] || fail "a systemd initramfs keeps the wait: $(<"$tmp/grub")"
printf 'HOOKS=(base systemd block sd-encrypt filesystems)\n' >"$tmp/conf.d/91-test.conf"
run || fail "a drop-in systemd Mac runs: $(<"$tmp/out")"
cmp -s "$damaged" "$tmp/grub" && [[ ! -s $CALL_LOG ]] || fail "a drop-in that makes the initramfs systemd is honoured"
rm "$tmp/conf.d/91-test.conf"
mkdir -p "$tmp/presets"
printf 'PRESETS=(default)\ndefault_config=%s\n' "$systemd" >"$tmp/presets/linux-asahi.preset"
run || fail "a preset systemd Mac runs: $(<"$tmp/out")"
cmp -s "$damaged" "$tmp/grub" && [[ ! -s $CALL_LOG ]] || fail "the preset's configuration decides"
rm -rf "$tmp/presets"
MKINITCPIO_CONF="$tmp/missing.conf" run || fail "an unreadable configuration runs: $(<"$tmp/out")"
cmp -s "$damaged" "$tmp/grub" && [[ ! -s $CALL_LOG ]] || fail "an unreadable configuration proves nothing"
pass "a systemd initramfs (mkinitcpio.conf, drop-in or preset) or an unreadable one is left alone"

printf 'GRUB_CMDLINE_LINUX=""\nGRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 cryptdevice=UUID=%s:root:allow-discards quiet"\n' "$luks_uuid" >"$tmp/grub"
cp "$tmp/grub" "$tmp/correct"
run || fail "a correct Mac runs: $(<"$tmp/out")"
cmp -s "$tmp/correct" "$tmp/grub" && [[ ! -s $CALL_LOG ]] || fail "an already-correct Mac is untouched: $(<"$tmp/grub")"
printf 'GRUB_CMDLINE_LINUX="rd.luks.name=%s=root"\n' "$luks_uuid" >"$tmp/grub"
cp "$tmp/grub" "$tmp/correct"
run || fail "an rd.luks Mac runs: $(<"$tmp/out")"
cmp -s "$tmp/correct" "$tmp/grub" && [[ ! -s $CALL_LOG ]] || fail "an rd.luks unlock is not doubled with cryptdevice="
pass "an already-correct Mac is untouched"

cp "$damaged" "$tmp/grub"
: >"$tmp/limine.enabled"
: >"$tmp/limine"
printf '#!/bin/bash\nexit 0\n' >"$tmp/bin/limine-update"
chmod +x "$tmp/bin/limine-update"
run || fail "a Limine Mac runs: $(<"$tmp/out")"
cmp -s "$damaged" "$tmp/grub" && [[ ! -s $CALL_LOG ]] || fail "a Limine Mac is untouched: $(<"$tmp/grub")"
rm -f "$tmp/bin/limine-update" "$tmp/limine.enabled" "$tmp/limine"
pass "a Limine Mac is skipped"

APPLE=1 run || fail "a non-Apple machine passes"
cmp -s "$damaged" "$tmp/grub" && [[ ! -s $CALL_LOG ]] || fail "a non-Apple machine is untouched"
pass "the repair gates itself to Apple Silicon"
