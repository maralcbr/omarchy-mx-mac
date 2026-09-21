#!/bin/bash
#
# omarchy-mac-snapshot-restore swaps the root subvolume of an Apple Silicon
# Mac to a writable clone of a snapper snapshot. The real script runs against
# a fake top-level mount: btrfs, findmnt, mount and the privileged calls are
# stubbed, and every refusal, the recovery record, the /.snapshots move and
# the rename order are checked.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

restore="$ROOT/bin/omarchy-mac-snapshot-restore"
finish="$ROOT/bin/omarchy-mac-snapshot-restore-finish"
unit="$ROOT/install/provisioning/omarchy-mac-snapshot-restore-finish.service"

grep -Fxq 'ConditionPathExists=/var/lib/omarchy/snapshot-restore/pending' "$unit" &&
  grep -Fxq 'Before=sysinit.target shutdown.target' "$unit" &&
  grep -Fxq 'ExecStart=/usr/bin/omarchy-mac-snapshot-restore-finish' "$unit" ||
  fail "the finish unit is armed by the pending marker and runs before sysinit"
grep -Fq 'sudo omarchy-mac-snapshot-restore "${@:2}"' "$ROOT/bin/omarchy-snapshot" ||
  fail "omarchy-snapshot restore dispatches to the Mac restore on Apple Silicon"
grep -Fq 'sudo limine-snapper-restore' "$ROOT/bin/omarchy-snapshot" ||
  fail "omarchy-snapshot restore keeps Limine's restore elsewhere"
pass "omarchy-snapshot dispatches restore by platform and ships the finish unit"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
stub_bin="$tmp/bin"
top="$tmp/top"
state="$tmp/state"
record="$tmp/boot/omarchy/snapshot-restore.state"
modules="$tmp/modules"
mkdir -p "$stub_bin" "$top/@/.snapshots/1/snapshot$modules/6.16.0-aurora" "$tmp/boot/omarchy" \
  "$modules/6.16.0-aurora" "$tmp/prov" "$tmp/first-boot" "$tmp/units" "$tmp/lock"
export CALL_LOG="$tmp/calls" TOP="$top" SNAPSHOTS="$top/@/.snapshots"
export PATH="$stub_bin:$PATH"

printf 'linux-aurora\n' >"$modules/6.16.0-aurora/pkgbase"
printf 'kernel-image-6.16\n' >"$modules/6.16.0-aurora/vmlinuz"
mkdir -p "$top/@/.snapshots/1/snapshot/usr/bin"
printf '#!/bin/bash\n' >"$top/@/.snapshots/1/snapshot/usr/bin/omarchy-mac-snapshot-restore-finish"
chmod +x "$top/@/.snapshots/1/snapshot/usr/bin/omarchy-mac-snapshot-restore-finish"
: >"$top/@/.snapshots/1/snapshot$modules/6.16.0-aurora/modules.dep"
printf '<snapshot><num>1</num><description>4.0.3-mac.4</description></snapshot>\n' >"$top/@/.snapshots/1/info.xml"
cp "$unit" "$tmp/units/"

# The real /.snapshots is what the script inspects; point it at the fake top.
# btrfs: a path is a subvolume when it carries a .subvol marker (the clone
# gets one; its nested .snapshots is a plain directory like a real snapshot).
cat >"$stub_bin/btrfs" <<'STUB'
#!/bin/bash
printf 'btrfs %s\n' "$*" >>"$CALL_LOG"
case "$1 $2" in
  "subvolume show")
    path=$3
    [[ $path == / ]] && path=$TOP/@
    [[ $path == /.snapshots* ]] && path=$SNAPSHOTS${path#/.snapshots}
    [[ -f $path/.subvol ]] || exit 1
    printf 'Subvolume ID: \t\t%s\n' "$(cat "$path/.subvol")"
    ;;
  "subvolume snapshot")
    src=$3; dst=$4
    [[ $src == /.snapshots* ]] && src=$SNAPSHOTS${src#/.snapshots}
    cp -a "$src" "$dst"
    printf '%s\n' "$RANDOM" >"$dst/.subvol"
    mkdir -p "$dst/.snapshots"
    ;;
  "subvolume delete")
    [[ ${DELETE_FAILS:-0} == 1 ]] && exit 1
    printf 'delete %s\n' "${*: -1}" >>"$CALL_LOG.deletes"
    rm -rf "${*: -1}"
    ;;
esac
exit 0
STUB
for path in "$top/@" "$top/@/.snapshots" "$top/@/.snapshots/1/snapshot"; do
  printf '%s\n' "$RANDOM" >"$path/.subvol"
done
cat >"$stub_bin/findmnt" <<'STUB'
#!/bin/bash
case "$*" in
  *"-no SOURCE /"*) echo "/dev/mapper/root[/@]" ;;
  *"-no FSTYPE /"*) echo "${FSTYPE:-btrfs}" ;;
  *"-no OPTIONS /"*) echo "rw,relatime,subvol=/${FAKE_ROOT_SUBVOL:-@}" ;;
  *"-no UUID /"*) echo "1111-2222" ;;
esac
STUB
cat >"$stub_bin/mount" <<'STUB'
#!/bin/bash
printf 'mount %s\n' "$*" >>"$CALL_LOG"
STUB
cat >"$stub_bin/mountpoint" <<'STUB'
#!/bin/bash
exit 0
STUB
for command in umount systemctl sync flock; do
  cat >"$stub_bin/$command" <<STUB
#!/bin/bash
printf '$command %s\n' "\$*" >>"\$CALL_LOG"
STUB
done
printf '#!/bin/bash\nexit 0\n' >"$stub_bin/omarchy-hw-apple-silicon"
printf '#!/bin/bash\necho linux-aurora\n' >"$stub_bin/omarchy-hw-apple-kernel"
# mv is real, except when a test asks the second root rename to fail.
cat >"$stub_bin/mv" <<'STUB'
#!/bin/bash
# Fails the first rename onto @ (the second swap step) once; the rollback
# rename onto @ that follows must succeed.
if [[ ${MV_FAIL_SECOND:-0} == 1 && ${*: -1} == "$TOP/@" && ! -e $TOP/.mv-failed-once ]]; then
  : >"$TOP/.mv-failed-once"
  exit 1
fi
exec /usr/bin/mv "$@"
STUB
chmod +x "$stub_bin"/*
printf 'kernel-image-6.16\n' >"$tmp/boot/vmlinuz-linux-aurora"

# The fake top is a directory, so mount is a no-op and the script's
# /.snapshots checks are redirected by the btrfs stub. The script mounts at
# TOP_MNT; give it the fake top directly.
mkdir -p "$tmp/proc"
printf 'Filename\tType\tSize\tUsed\tPriority\n/dev/zram0 partition 4194300 0 100\n' >"$tmp/proc/swaps"
printf 'root=UUID=1111-2222 rw rootflags=subvol=@ quiet\n' >"$tmp/proc/cmdline"

run_restore() {
  : >"$CALL_LOG"
  OMARCHY_SNAPSHOT_RESTORE_PROC="$tmp/proc" \
  OMARCHY_SNAPSHOT_RESTORE_TOP="$top" \
  OMARCHY_SNAPSHOT_RESTORE_STATE_DIR="$state" \
  OMARCHY_SNAPSHOT_RESTORE_GATE="$tmp/gate" \
  OMARCHY_SNAPSHOT_RESTORE_RECORD="$record" \
  OMARCHY_PROVISIONING_DIR="$tmp/prov" \
  OMARCHY_MAC_FIRST_BOOT_DIR="$tmp/first-boot" \
  OMARCHY_ROOT_SWAP_LOCK="$tmp/lock/swap" \
  OMARCHY_SNAPSHOT_RESTORE_UNIT_SRC="$tmp/units" \
  OMARCHY_SNAPSHOT_RESTORE_MODULES="$modules" \
  OMARCHY_SNAPSHOT_RESTORE_BOOT="$tmp/boot" \
  OMARCHY_SNAPSHOTS_DIR="$top/@/.snapshots" \
    bash "$restore" "$@" >"$tmp/out" 2>&1
}

run_finish() {
  OMARCHY_SNAPSHOT_RESTORE_STATE_DIR="$top/@$state" OMARCHY_SNAPSHOT_RESTORE_RECORD="$record" \
    OMARCHY_SNAPSHOTS_DIR="$top/@/.snapshots" OMARCHY_SNAPSHOT_RESTORE_WANTS_DIR="$tmp/wants" \
    bash "$finish_runnable" >"$tmp/out" 2>&1
}

# The script insists on root; the sandbox copy drops that one line.
runnable="$tmp/omarchy-mac-snapshot-restore"
sed -e 's@^(( EUID == 0 )) || fail "run as root"$@true # test-only root boundary@' "$restore" >"$runnable"
grep -Fq 'test-only root boundary' "$runnable" || fail "the sandbox copy drops the root boundary"
restore=$runnable
finish_runnable="$tmp/omarchy-mac-snapshot-restore-finish"
sed -e 's@^if (( EUID != 0 )); then$@if false; then # test-only root boundary@' "$finish" >"$finish_runnable"
grep -Fq 'test-only root boundary' "$finish_runnable" || fail "the finish sandbox copy drops the root boundary"

# Without the gate nothing happens.
if run_restore 1 --yes --no-reboot; then fail "a restore without the opt-in gate must refuse"; fi
grep -Fq 'experimental' "$tmp/out" || fail "the refusal names the gate: $(<"$tmp/out")"
[[ ! -e $record ]] || fail "a refused restore writes no record"
pass "the restore refuses until the machine opted in"

# Refusals before anything is touched.
touch "$tmp/gate"
touch "$tmp/prov/pending"
if run_restore 1 --yes --no-reboot; then fail "a pending provisioning must refuse"; fi
grep -Fq 'provisioning or a factory reset is pending' "$tmp/out" || fail "pending provisioning is named: $(<"$tmp/out")"
rm -f "$tmp/prov/pending"
if FAKE_ROOT_SUBVOL=@factory run_restore 1 --yes --no-reboot; then fail "a root other than @ must refuse"; fi
grep -Fq 'not the @ subvolume' "$tmp/out" || fail "a foreign root subvolume is named: $(<"$tmp/out")"
if run_restore 2 --yes --no-reboot; then fail "a missing snapshot must refuse"; fi
grep -Fq 'has no info.xml' "$tmp/out" || fail "a missing snapshot is named: $(<"$tmp/out")"
# The image on /boot is a newer kernel whose modules the snapshot lacks.
mkdir -p "$modules/6.17.0-aurora"; printf 'linux-aurora\n' >"$modules/6.17.0-aurora/pkgbase"
printf 'kernel-image-6.17\n' >"$modules/6.17.0-aurora/vmlinuz"
printf 'kernel-image-6.17\n' >"$tmp/boot/vmlinuz-linux-aurora"
if run_restore 1 --yes --no-reboot; then fail "a snapshot without the kernel's modules must refuse"; fi
grep -Fq 'no modules for the kernel on /boot (6.17.0-aurora)' "$tmp/out" || fail "the kernel mismatch names the version: $(<"$tmp/out")"
rm -r "$modules/6.17.0-aurora"
printf 'kernel-image-6.16\n' >"$tmp/boot/vmlinuz-linux-aurora"
# An image on /boot that matches no modules directory is refused too.
printf 'kernel-image-unknown\n' >"$tmp/boot/vmlinuz-linux-aurora"
if run_restore 1 --yes --no-reboot; then fail "a /boot image matching no modules directory must refuse"; fi
grep -Fq 'matches the linux-aurora image' "$tmp/out" || fail "the unmatched image is named: $(<"$tmp/out")"
printf 'kernel-image-6.16\n' >"$tmp/boot/vmlinuz-linux-aurora"
# A snapshot from before the restore worker shipped cannot verify itself.
mv "$top/@/.snapshots/1/snapshot/usr/bin/omarchy-mac-snapshot-restore-finish" "$tmp/finish.bak"
if run_restore 1 --yes --no-reboot; then fail "a snapshot without the finish worker must refuse"; fi
grep -Fq 'predates the restore worker' "$tmp/out" || fail "the missing worker is named: $(<"$tmp/out")"
mv "$tmp/finish.bak" "$top/@/.snapshots/1/snapshot/usr/bin/omarchy-mac-snapshot-restore-finish"
mv "$tmp/boot/vmlinuz-linux-aurora" "$tmp/boot/vmlinuz-other"
if run_restore 1 --yes --no-reboot; then fail "a /boot without the Apple kernel package's image must refuse"; fi
grep -Fq 'not the installed Apple kernel package' "$tmp/out" || fail "the /boot kernel identity is checked: $(<"$tmp/out")"
mv "$tmp/boot/vmlinuz-other" "$tmp/boot/vmlinuz-linux-aurora"
printf 'Filename\tType\tSize\tUsed\tPriority\n/swapfile file 4194300 0 -2\n' >"$tmp/proc/swaps"
if run_restore 1 --yes --no-reboot; then fail "a swap file on the root must refuse"; fi
grep -Fq 'swap file' "$tmp/out" || fail "the swap refusal is named: $(<"$tmp/out")"
printf 'Filename\tType\tSize\tUsed\tPriority\n' >"$tmp/proc/swaps"
[[ ! -e $record && -z $(compgen -G "$top/@restore-*") ]] || fail "refusals stage nothing"
! grep -q 'btrfs subvolume snapshot' "$CALL_LOG" || fail "refusals clone nothing"
pass "the restore refuses pending provisioning, foreign roots, missing snapshots and kernel mismatches"

# A failure after the collection moved: the unit source is missing, so the
# install step fails. The collection must come back and the clone must go.
rm "$tmp/units/omarchy-mac-snapshot-restore-finish.service"
if run_restore 1 --yes --no-reboot; then fail "a failed unit install must fail the restore"; fi
[[ -f $top/@/.snapshots/.subvol && -f $top/@/.snapshots/1/info.xml ]] || fail "the collection is moved back on failure"
[[ -z $(compgen -G "$top/@restore-*") ]] || fail "the staging root is deleted on failure"
grep -Fq 'delete' "$CALL_LOG.deletes" || fail "the staging root deletion went through btrfs"
[[ ! -e $record ]] || fail "a failed restore removes its record"
[[ -d $top/@ ]] || fail "the root is untouched on failure"
cp "$unit" "$tmp/units/"
pass "a failure after the move restores /.snapshots and drops the staging root"

# The second rename fails: the current root gets its name back before anything
# else is unwound, so the machine still has an @ to boot.
rm -f "$CALL_LOG.deletes"
original_id=$(<"$top/@/.subvol")
if MV_FAIL_SECOND=1 run_restore 1 --yes --no-reboot; then fail "a failed second rename must fail the restore"; fi
[[ -d $top/@ && $(<"$top/@/.subvol") == "$original_id" ]] || fail "the current root is renamed back to @"
[[ -z $(compgen -G "$top/@omarchy-previous-*") ]] || fail "no previous root is left behind"
[[ -f $top/@/.snapshots/.subvol && -f $top/@/.snapshots/1/info.xml ]] || fail "the collection is back in the current root"
[[ -z $(compgen -G "$top/@restore-*") ]] || fail "the staging root is dropped"
[[ ! -e $record ]] || fail "a fully unwound restore leaves no record"
grep -Fq 'could not put the restored root in place' "$tmp/out" || fail "the failure is named: $(<"$tmp/out")"
rm -f "$top/.mv-failed-once"
pass "a failed second rename restores the root name before unwinding the rest"

# The happy path, without the reboot.
rm -f "$CALL_LOG.deletes"
run_restore 1 --yes --no-reboot || fail "the restore stages and swaps: $(<"$tmp/out")"
previous=$(compgen -G "$top/@omarchy-previous-*")
[[ -n $previous ]] || fail "the previous root is kept"
[[ -d $top/@ && -f $top/@/.subvol ]] || fail "the clone is the new @"
[[ $(<"$top/@/.subvol") != $(<"$previous/.subvol") ]] || fail "the new @ is the clone, not the old root"
[[ -f $top/@/.snapshots/.subvol && -f $top/@/.snapshots/1/info.xml ]] || fail "the live collection moved into the new root"
[[ ! -e $previous/.snapshots ]] || fail "the previous root no longer holds the collection"
[[ -f $top/@/etc/systemd/system/omarchy-mac-snapshot-restore-finish.service &&
   -L $top/@/etc/systemd/system/sysinit.target.wants/omarchy-mac-snapshot-restore-finish.service ]] ||
  fail "the finish unit is installed and enabled in the new root"
[[ -f $top/@$state/pending ]] || fail "the new root carries the pending marker"
grep -Fxq 'restored_from=1' "$top/@$state/restored-from" || fail "the new root records its snapshot"
grep -Fxq 'phase=swapped' "$record" && grep -Fxq 'snapshot=1' "$record" &&
  grep -Fq "previous=${previous##*/}" "$record" || fail "the record names the swap: $(<"$record")"
! grep -q 'reboot' "$CALL_LOG" || fail "--no-reboot does not reboot"
grep -q 'systemctl stop snapper-cleanup.timer' "$CALL_LOG" || fail "snapper cleanup is stopped during the swap"
! grep -q 'systemctl start snapper-cleanup.timer' "$CALL_LOG" || fail "cleanup stays stopped once the swap is done"
pass "a restore clones the snapshot, moves /.snapshots, swaps the roots and records it"

# A second restore waits for the kept root to be pruned; pruning needs the
# next boot's verification first: the record still says swapped and the
# pending marker sits in the restored root.
if run_restore 1 --yes --no-reboot; then fail "a kept previous root must block another restore"; fi
grep -Fq 'prune-previous' "$tmp/out" || fail "the refusal names prune-previous"
if run_restore --prune-previous; then fail "pruning before the verifying reboot must refuse"; fi
grep -Fq 'not verified (phase swapped)' "$tmp/out" || fail "the prune refusal names the unverified restore: $(<"$tmp/out")"
[[ -d $previous ]] || fail "the running root survives a refused prune"
pass "prune-previous refuses until the restore was verified by a reboot"

# The finish worker on the next boot: it runs inside the restored root.
mkdir -p "$tmp/wants"; ln -s /etc/systemd/system/omarchy-mac-snapshot-restore-finish.service "$tmp/wants/"
if run_finish; then fail "without snapper the verification must fail closed"; fi
[[ -f $top/@$state/pending ]] || fail "a failed verification keeps the pending marker"
grep -q $'\tfailed\t' "$top/@$state/last-result" || fail "the failure is recorded"
cat >"$stub_bin/snapper" <<'STUB'
#!/bin/bash
printf 'snapper %s\n' "$*" >>"$CALL_LOG"
exit 0
STUB
chmod +x "$stub_bin/snapper"
: >"$CALL_LOG"
run_finish || fail "the finish worker verifies the restore: $(<"$tmp/out")"
[[ ! -e $top/@$state/pending ]] || fail "verification clears the pending marker"
grep -Fxq 'phase=finished' "$record" || fail "verification marks the record finished"
grep -q 'snapper --no-dbus -c root create -c number -d Restored from 1 --userdata restored_from=1' "$CALL_LOG" ||
  fail "verification records a snapshot of the restored state"
grep -q $'\tfinished\t' "$top/@$state/last-result" || fail "verification records its result"
[[ ! -L $tmp/wants/omarchy-mac-snapshot-restore-finish.service ]] || fail "the finish unit disarms itself"
pass "the finish worker fails closed without snapper and verifies the collection otherwise"

# Now the kept root may go: the record is finished and the running root is
# the restored clone the record names.
run_restore --prune-previous || fail "pruning drops the kept root: $(<"$tmp/out")"
[[ -z $(compgen -G "$top/@omarchy-previous-*") ]] || fail "the kept root is deleted"
grep -Fq "delete $previous" "$CALL_LOG.deletes" || fail "the kept root deletion went through btrfs"
[[ ! -e $record ]] || fail "pruning clears the record"
pass "prune-previous drops the kept root only after verification"

# A restore refused for a kept root leaves an existing record alone.
run_restore 1 --yes --no-reboot || fail "a fresh restore after pruning runs: $(<"$tmp/out")"
if run_restore 1 --yes --no-reboot; then fail "a kept root must block another restore"; fi
[[ -f $record ]] && grep -Fxq 'phase=swapped' "$record" || fail "the refusal keeps the existing record"
mkdir -p "$tmp/wants"; ln -sf /etc/systemd/system/omarchy-mac-snapshot-restore-finish.service "$tmp/wants/"
run_finish || fail "verification after the second restore: $(<"$tmp/out")"
run_restore --prune-previous || fail "pruning after the second restore: $(<"$tmp/out")"
pass "a refusal for a kept root never removes the record of the restore that made it"

# Without a record the finish worker cannot prove anything: pending stays.
: >"$top/@$state/pending"
rm -f "$record"
if run_finish; then fail "a missing record must keep the restore pending"; fi
grep -q $'\tfailed\t' "$top/@$state/last-result" || fail "the missing record is recorded as a failure"
pass "the finish worker fails closed without a record"

# A restored root whose collection is missing stays pending.
: >"$top/@$state/pending"
printf 'format=1\nphase=swapped\n' >"$record"
rm "$top/@/.snapshots/.subvol"
if run_finish; then fail "a missing collection must keep the restore pending"; fi
[[ -f $top/@$state/pending ]] || fail "the pending marker stays"
grep -q $'\tfailed\t' "$top/@$state/last-result" || fail "the failure is recorded"
pass "a restored root without its collection stays pending"
