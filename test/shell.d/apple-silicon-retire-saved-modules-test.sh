#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command gzip
require_command realpath

retire="$ROOT/bin/omarchy-apple-silicon-retire-saved-modules"
check="$ROOT/bin/omarchy-apple-silicon-boot-check"
grep -Fq '# omarchy:hidden=true' "$retire" || fail "the helper is hidden from command listings"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
root="$test_tmp/root"
esp="$root/boot/efi"
calls="$test_tmp/calls"
mounts="$test_tmp/mounts"
files="$test_tmp/files"
modules="$root/usr/lib/modules"
# The M2 Max's move from edge back to rc.
rc=7.1.12-2-6-ARCH
edge=7.1.12-2.2-1-ARCH
names=(s5l8960x-j71.dtb t6020-j414s.dtb t8103-j274.dtb)
mkdir -p "$stub_bin"

stub() {
  cat >"$stub_bin/$1"
  chmod +x "$stub_bin/$1"
}

# TEST_SLOW=<step> holds rsync or the removal until $TEST_SLOW_DIR/go exists,
# after recording the helper's pid, so a signal can land mid-move.
slow() {
  [[ ${TEST_SLOW:-} == "$1" ]] || return 0
  echo "$PPID" >"$TEST_SLOW_DIR/pid"
  : >"$TEST_SLOW_DIR/started"
  for _ in {1..200}; do
    [[ ! -e $TEST_SLOW_DIR/go ]] || return 0
    sleep 0.05
  done
}
lock_state() {
  [[ -e $TEST_ROOT/var/lib/pacman/db.lck ]] && echo locked || echo unlocked
}
export -f slow lock_state
# Taking pacman's lock can be raced by a transaction that reinstalls the saved
# release, and removing the saved modules can be made to fail.
stub sudo <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$TEST_CALLS"
if [[ $1 == bash && ${TEST_REINSTALLED_BEFORE_LOCK:-0} == 1 ]]; then
  printf '/usr/lib/modules/%s/\n' "$TEST_RUNNING" >"$TEST_FILES/linux-aurora-edge"
fi
if [[ $1 == rm && $2 == -f && ${3:-} == */db.lck ]]; then
  slow release
  "$@"
  # Another transaction takes the lock as soon as it is free.
  [[ ${TEST_SLOW:-} != release ]] || echo other >"$3"
  exit
fi
if [[ $1 == rm && $2 == -rf ]]; then
  [[ ${TEST_RM_FAILS:-0} != 1 ]] || exit 1
  slow rm
  "$@"
  printf 'rm-done %s\n' "$(lock_state)" >>"$TEST_CALLS"
  exit
fi
exec "$@"
SH
stub uname <<'SH'
#!/bin/bash
[[ $* == -r ]] || exec /usr/bin/uname "$@"
echo "$TEST_RUNNING"
SH
# Owners come from each package's file list, as pacman -Qo answers them. With
# --root, only the fixture's root and database are accepted, file lists carry the
# root, and -Qo takes paths under it, as pacman's do.
stub pacman <<'SH'
#!/bin/bash
prefix=""
if [[ $1 == --root ]]; then
  [[ $2 == "$TEST_ROOT" && $3 == --dbpath && $4 == "$TEST_ROOT/var/lib/pacman/" ]] || { echo "pacman: wrong root $*" >&2; exit 2; }
  prefix=$TEST_ROOT
  shift 4
fi
case "$1" in
  -Qq) cat "$TEST_FILES/installed" ;;
  -Qlq) [[ -f $TEST_FILES/$2 ]] && sed "s|^|$prefix|" "$TEST_FILES/$2" ;;
  -Qqo)
    [[ -n $prefix || $2 != "$TEST_ROOT"/* ]] || { echo "pacman: a fixture path without --root" >&2; exit 2; }
    [[ $2 == "$prefix"/* ]] || exit 2
    for list in "$TEST_FILES"/*; do
      [[ ${list##*/} != installed ]] || continue
      if grep -Fxq -- "${2#"$prefix"}/" "$list"; then
        echo "${list##*/}"
        exit 0
      fi
    done
    echo "error: No package owns $2" >&2
    exit 1
    ;;
  *) exit 1 ;;
esac
SH
stub lsinitcpio <<'SH'
#!/bin/bash
printf 'usr/lib/modules/%s/kernel/drivers/gpu/drm/apple/appledrm.ko.zst\n' "$TEST_KVER"
SH
stub rsync <<'SH'
#!/bin/bash
printf 'rsync %s %s\n' "$(lock_state)" "$*" >>"$TEST_CALLS"
[[ ${TEST_RSYNC_FAILS:-0} != 1 && $1 == -AHXal && $# == 3 ]] || exit 1
slow rsync
mkdir -p "$3"
cp -a "$2" "$3"
printf 'rsync-done %s\n' "$(lock_state)" >>"$TEST_CALLS"
SH
# A read-only bind of /boot/efi, the way the check reads an ESP the device tree does not name.
stub mount <<'SH'
#!/bin/bash
[[ $1 == --bind && $2 == -o && $3 == ro ]] || exit 32
cp -a "$4/." "$5/"
echo "$5 ro" >>"$TEST_MOUNTS"
SH
stub umount <<'SH'
#!/bin/bash
find "$1" -mindepth 1 -delete
sed -i "\|^$1 |d" "$TEST_MOUNTS"
SH
stub findmnt <<'SH'
#!/bin/bash
[[ "$1 $2 $3 $4" == "-n -o VFS-OPTIONS --mountpoint" ]] || exit 1
state=$(awk -v target="$5" '$1 == target { print $2 }' "$TEST_MOUNTS")
[[ -n $state ]] && echo "$state,relatime"
SH
# update-m1n1 with ALARM's defaults, run against the fixture: its own
# environment and arguments are logged, and it writes TARGET when one is set.
stub update-m1n1 <<'SH'
#!/bin/bash
lock=unlocked
[[ ! -e $TEST_ROOT/var/lib/pacman/db.lck ]] || lock=locked
printf 'update-m1n1 %s args=%s TARGET=%s DTBS=%s\n' "$lock" "$*" "${TARGET-unset}" "${DTBS-unset}" >>"$TEST_CALLS"
[[ ${TEST_M1N1_FAILS:-0} != 1 ]] || exit 1
export LC_ALL=C
: ${TARGET:="$1"}
: ${DTBS:=$(/bin/ls -d "$TEST_ROOT"/lib/modules/*-ARCH | sort -rV | head -1)/dtbs/*.dtb}
[[ -n $TARGET ]] || TARGET=$TEST_ROOT/boot/efi/m1n1/boot.bin
{
  cat "$TEST_ROOT/usr/lib/asahi-boot/m1n1.bin" $DTBS
  gzip -c "$TEST_ROOT/usr/lib/asahi-boot/u-boot-nodtb.bin"
  cat "$TEST_ROOT/etc/m1n1.conf"
} >"$TARGET"
SH

# rc installed, edge running, and the edge modules kernel-modules-hook kept.
# m1n1 was built by the pacman hook from the newest -ARCH directory: edge's.
downgraded() {
  local kver dtb
  rm -rf "$root" "$files"
  mkdir -p "$root/boot/grub" "$root/usr/lib/asahi-boot" "$root/usr/bin" "$root/etc/default" "$root/run" "$esp/m1n1" "$files" \
    "$root/var/lib/pacman"
  : >"$mounts"
  ln -s usr/lib "$root/lib"
  for kver in "$rc" "$edge"; do
    mkdir -p "$modules/$kver/dtbs" "$modules/$kver/kernel"
    printf 'kernel %s\n' "$kver" >"$modules/$kver/vmlinuz"
    printf 'module %s\n' "$kver" >"$modules/$kver/kernel/apple-dcp.ko.zst"
    for dtb in "${names[@]}"; do
      printf 'device tree %s from %s\n' "$dtb" "$kver" >"$modules/$kver/dtbs/$dtb"
    done
  done
  cp "$modules/$rc/vmlinuz" "$root/boot/vmlinuz-linux-aurora"
  printf 'initramfs\n' >"$root/boot/initramfs-linux-aurora.img"
  printf 'linux /vmlinuz-linux-aurora\ninitrd /initramfs-linux-aurora.img\n' >"$root/boot/grub/grub.cfg"
  printf 'm1n1 stage 2\n' >"$root/usr/lib/asahi-boot/m1n1.bin"
  printf 'u-boot\n' >"$root/usr/lib/asahi-boot/u-boot-nodtb.bin"
  printf 'display=2560x1600\n' >"$root/etc/m1n1.conf"
  cat >"$root/usr/bin/update-m1n1" <<'SH'
#!/bin/sh
[ -e /etc/default/update-m1n1 ] && . /etc/default/update-m1n1
[ -n "$M1N1_UPDATE_DISABLED" ] && exit 0
: ${SOURCE:="/usr/lib/asahi-boot/"}
: ${M1N1:="$SOURCE/m1n1.bin"}
: ${U_BOOT:="$SOURCE/u-boot-nodtb.bin"}
: ${TARGET:="$1"}
: ${DTBS:=$(/bin/ls -d /lib/modules/*-ARCH | sort -rV | head -1)/dtbs/*.dtb}
: ${CONFIG:=/etc/m1n1.conf}
            chosen.*=*|display=*|mitigations=*)
cat "$M1N1" $DTBS >"${TARGET}.new"
gzip -c "$U_BOOT" >>"${TARGET}.new"
SH
  printf '%s\n' linux-aurora linux-aurora-headers m1n1-aurora uboot-asahi kernel-modules-hook rsync >"$files/installed"
  {
    printf '/usr/lib/modules/%s/\n/usr/lib/modules/%s/vmlinuz\n/usr/lib/modules/%s/dtbs/\n' "$rc" "$rc" "$rc"
    printf "/usr/lib/modules/$rc/dtbs/%s\n" "${names[@]}"
  } >"$files/linux-aurora"
  printf '/usr/lib/asahi-boot/\n/usr/lib/asahi-boot/m1n1.bin\n' >"$files/m1n1-aurora"
  TEST_CALLS=/dev/null TEST_ROOT="$root" "$stub_bin/update-m1n1"
}

in_env() {
  env TEST_CALLS="$calls" TEST_FILES="$files" TEST_MOUNTS="$mounts" TEST_ROOT="$root" TEST_KVER="$rc" \
    TEST_RUNNING="${running:-$edge}" OMARCHY_SAVED_MODULES_ROOT="$root" OMARCHY_BOOT_CHECK_ROOT="$root" \
    OMARCHY_SAVED_MODULES_REBUILD="$stub_bin/update-m1n1" \
    PATH="$stub_bin:$ROOT/bin:$PATH" "$@"
}

run_retire() {
  : >"$calls"
  set +e
  in_env TARGET="$test_tmp/elsewhere" DTBS="$modules/$edge/dtbs/*.dtb" \
    bash "$retire" linux-aurora >"$test_tmp/out" 2>"$test_tmp/err"
  status=$?
  set -e
}

run_retire_without_rebuild() {
  : >"$calls"
  set +e
  in_env env -u OMARCHY_SAVED_MODULES_REBUILD bash "$retire" linux-aurora >"$test_tmp/out" 2>"$test_tmp/err"
  status=$?
  set -e
}

run_check() {
  set +e
  in_env env TEST_CALLS=/dev/null bash "$check" linux-aurora >"$test_tmp/check.out" 2>"$test_tmp/check.err"
  check_status=$?
  set -e
}

expect_check_passes() {
  run_check
  (( check_status == 0 )) || fail "$1: the boot check passes" "status $check_status: $(cat "$test_tmp/check.err")"
}

expect_check_refuses_edge_dtbs() {
  run_check
  (( check_status == 1 )) && grep -Fq "device tree /lib/modules/$edge/dtbs/${names[0]} is not one of linux-aurora $rc's" "$test_tmp/check.err" ||
    fail "$1: the boot check still refuses edge's device trees" "status $check_status: $(cat "$test_tmp/check.err")"
}

expect_left_alone() {
  (( status == 0 )) || fail "$1 exits 0" "status $status: $(cat "$test_tmp/err")"
  [[ ! -s $calls && ! -s $test_tmp/out && -d $modules/$edge && ! -e $modules/.old && ! -e $root/var/lib/pacman/db.lck ]] ||
    fail "$1 moves nothing and runs nothing" "$(cat "$calls" "$test_tmp/out")"
  expect_check_refuses_edge_dtbs "$1"
}

# The image the installed kernel's device trees make, as update-m1n1 builds it.
rc_image() {
  {
    cat "$root/usr/lib/asahi-boot/m1n1.bin" "${names[@]/#/$modules/$rc/dtbs/}"
    gzip -c "$root/usr/lib/asahi-boot/u-boot-nodtb.bin"
    cat "$root/etc/m1n1.conf"
  } >"$test_tmp/rc-image"
  cmp -s "$test_tmp/rc-image" "$esp/m1n1/boot.bin"
}

downgraded
[[ $(printf '%s\n' "$rc" "$edge" | sort -rV | head -1) == "$edge" ]] || fail "the fixture's edge release sorts above rc"
expect_check_refuses_edge_dtbs "after the downgrade"
pass "after an edge to rc downgrade the hook built m1n1 with edge's device trees, and the boot check refuses them"

run_retire
(( status == 0 )) || fail "the downgrade is repaired" "status $status: $(cat "$test_tmp/err")"
[[ ! -e $modules/$edge && -d $modules/$rc ]] || fail "the running kernel's saved modules leave /usr/lib/modules" "$(ls -A "$modules")"
cmp -s "$modules/.old/$edge/kernel/apple-dcp.ko.zst" <(printf 'module %s\n' "$edge") &&
  cmp -s "$modules/.old/$edge/dtbs/${names[0]}" <(printf 'device tree %s from %s\n' "${names[0]}" "$edge") ||
  fail "they are kept in /usr/lib/modules/.old, as linux-modules-cleanup keeps them" "$(find "$modules/.old")"
grep -Fxq "rsync locked -AHXal $modules/$edge $modules/.old/" "$calls" &&
  grep -Fxq "sudo rm -rf $modules/$edge" "$calls" && grep -Fxq "sudo bash -c set -C; : >\"\$1\" _ $root/var/lib/pacman/db.lck" "$calls" ||
  fail "they are copied the way linux-modules-cleanup copies them, holding pacman's lock taken the way libalpm takes it" "$(cat "$calls")"
(( $(grep -c '^update-m1n1 ' "$calls") == 1 )) && grep -Fxq 'update-m1n1 unlocked args= TARGET=unset DTBS=unset' "$calls" ||
  fail "update-m1n1 runs once, after the lock is released, without TARGET, DTBS or arguments" "$(cat "$calls")"
[[ ! -e $root/var/lib/pacman/db.lck ]] || fail "the lock it took is released"
[[ ! -e $test_tmp/elsewhere ]] || fail "a TARGET in the caller's environment is never written"
awk '/^rsync /{ r = NR } /^sudo rm -rf /{ d = NR } /^update-m1n1 /{ u = NR } END { exit !(r && d && u && r < d && d < u) }' "$calls" ||
  fail "the modules are copied, then removed, then m1n1 rebuilt" "$(cat "$calls")"
grep -Fq "Moving the running kernel's saved modules ($edge) to /usr/lib/modules/.old" "$test_tmp/out" &&
  grep -Fq "Reboot soon" "$test_tmp/out" || fail "the move and its cost are explained" "$(cat "$test_tmp/out")"
rc_image || fail "m1n1 now carries rc's device trees"
expect_check_passes "after the repair"
pass "a downgrade's saved running-kernel modules are moved to .old, m1n1 is rebuilt with the installed kernel's device trees, and the check passes"

run_retire
(( status == 0 )) && [[ ! -s $calls && ! -s $test_tmp/out ]] || fail "a second run finds nothing to do" "$(cat "$calls" "$test_tmp/out")"
in_env "$stub_bin/update-m1n1"
rc_image || fail "a later transaction's m1n1 hook, before the reboot, still takes rc's device trees"
expect_check_passes "after a later m1n1 hook"
pass "a rerun does nothing, and a later m1n1 hook before the reboot still builds the installed kernel's image"

downgraded
printf '/usr/lib/modules/%s/\n' "$edge" >"$files/linux-aurora-edge"
printf 'linux-aurora-edge\n' >>"$files/installed"
run_retire
expect_left_alone "a newer modules directory a package owns"
downgraded
running=$rc run_retire
expect_left_alone "a newer unowned directory while rc itself runs"
running=7.1.11-1-ARCH run_retire
expect_left_alone "a newer unowned directory that is not the running kernel's"
pass "a newer modules directory a package owns, or one that is not the running kernel's, is left for the check to refuse"

downgraded
mkdir -p "$modules/7.1.13-3-2-ARCH/build"
printf '/usr/lib/modules/7.1.13-3-2-ARCH/\n' >"$files/linux-asahi-headers"
printf 'linux-asahi-headers\n' >>"$files/installed"
run_retire
(( status == 0 )) || fail "saved modules plus leftover headers exit 0" "status $status: $(cat "$test_tmp/err")"
[[ ! -s $calls && ! -s $test_tmp/out && -d $modules/$edge && -d $modules/7.1.13-3-2-ARCH && ! -e $modules/.old ]] ||
  fail "saved modules plus leftover headers move nothing" "$(cat "$calls" "$test_tmp/out")"
rm -rf "$modules/7.1.13-3-2-ARCH"
rm -f "$files/linux-asahi-headers"
grep -Fxv linux-asahi-headers "$files/installed" >"$files/installed.tmp"
mv "$files/installed.tmp" "$files/installed"
run_retire
(( status == 0 )) || fail "removing leftover headers lets the saved copy be retired" "status $status: $(cat "$test_tmp/err")"
[[ ! -e $modules/$edge && -d $modules/$rc && -d $modules/.old/$edge ]] ||
  fail "once the headers tree is gone the saved copy moves to .old"
expect_check_passes "after leftover headers are gone"
pass "saved modules plus leftover headers stay put; removing the headers lets the next update retire them"

downgraded
sed -i '/^kernel-modules-hook$/d' "$files/installed"
run_retire
expect_left_alone "no kernel-modules-hook"
downgraded
mkdir -p "$modules/7.1.12-2.1-1-ARCH/dtbs"
run_retire
expect_left_alone "another directory between the running and installed kernels"
downgraded
printf 'DTBS="/lib/modules/%s/dtbs/*.dtb"\n' "$edge" >"$root/etc/default/update-m1n1"
run_retire
expect_left_alone "DTBS set in /etc/default/update-m1n1"
downgraded
printf 'M1N1_UPDATE_DISABLED=1\n' >"$root/etc/default/update-m1n1"
run_retire
(( status == 0 )) && [[ ! -s $calls && -d $modules/$edge ]] || fail "m1n1 updates disabled leave everything alone" "$(cat "$calls")"
downgraded
sed -i '/DTBS:=/d' "$root/usr/bin/update-m1n1"
run_retire
(( status == 0 )) && [[ ! -s $calls && -d $modules/$edge ]] || fail "an update-m1n1 without the -ARCH default leaves everything alone" "$(cat "$calls")"
pass "without kernel-modules-hook, with another kernel in between, or with DTBS not from the -ARCH default, nothing moves"

# pacman's lock: held by someone else, raced, and kept through a failed move.
expect_nothing_removed() {
  (( status == 1 )) && grep -Fq "$2" "$test_tmp/err" || fail "$1 fails and says why" "status $status: $(cat "$test_tmp/err")"
  [[ -d $modules/$edge ]] && ! grep -q '^update-m1n1 ' "$calls" || fail "$1 removes nothing and rebuilds nothing" "$(cat "$calls")"
}
downgraded
printf 'pacman\n' >"$root/var/lib/pacman/db.lck"
run_retire
expect_nothing_removed "a lock pacman holds" "pacman's database is locked ($root/var/lib/pacman/db.lck)"
! grep -Eq '^(rsync|sudo rm -rf)' "$calls" && [[ $(cat "$root/var/lib/pacman/db.lck") == pacman && ! -e $modules/.old ]] ||
  fail "a lock pacman holds is left exactly as it is, and nothing is copied" "$(cat "$calls")"
downgraded
TEST_REINSTALLED_BEFORE_LOCK=1 run_retire
(( status == 0 )) && [[ -d $modules/$edge && ! -e $modules/.old && ! -e $root/var/lib/pacman/db.lck ]] &&
  ! grep -Eq '^(rsync|sudo rm -rf|update-m1n1)' "$calls" ||
  fail "a directory a transaction took ownership of before the lock is left alone and the lock released" "$(cat "$calls")"
expect_check_refuses_edge_dtbs "a directory reinstalled before the lock"
downgraded
TEST_RSYNC_FAILS=1 run_retire
expect_nothing_removed "a failed copy" "could not copy /usr/lib/modules/$edge to /usr/lib/modules/.old; nothing was removed"
! grep -q '^sudo rm -rf' "$calls" && [[ ! -e $root/var/lib/pacman/db.lck ]] || fail "a failed copy deletes nothing and releases the lock" "$(cat "$calls")"
downgraded
TEST_RM_FAILS=1 run_retire
expect_nothing_removed "a failed removal" "could not remove /usr/lib/modules/$edge; m1n1 was not rebuilt"
[[ ! -e $root/var/lib/pacman/db.lck ]] || fail "a failed removal releases the lock"
downgraded
run_retire_without_rebuild
(( status == 1 )) && grep -Fq "an alternate root needs OMARCHY_SAVED_MODULES_REBUILD" "$test_tmp/err" && [[ ! -s $calls && -d $modules/$edge ]] ||
  fail "an alternate root never falls back to the host's update-m1n1" "status $status: $(cat "$test_tmp/err" "$calls")"
pass "a held lock, a transaction racing the lock, a failed copy or removal, and a root without its own rebuild move and rebuild nothing"

# SIGTERM mid-move: the lock stays until rsync or rm is done, and the move finishes under it.
# During the release itself, a lock another transaction takes right after must survive.
for step in rsync rm release; do
  downgraded
  : >"$calls"
  rm -rf "$test_tmp/slow"
  mkdir "$test_tmp/slow"
  in_env TEST_SLOW=$step TEST_SLOW_DIR="$test_tmp/slow" bash "$retire" linux-aurora >"$test_tmp/out" 2>"$test_tmp/err" &
  runner=$!
  for _ in {1..200}; do
    [[ ! -e $test_tmp/slow/started ]] || break
    sleep 0.05
  done
  [[ -e $test_tmp/slow/started ]] || fail "the slow $step starts"
  helper=$(cat "$test_tmp/slow/pid")
  kill -TERM "$helper"
  sleep 0.5
  kill -0 "$helper" 2>/dev/null && [[ -e $root/var/lib/pacman/db.lck ]] ||
    fail "SIGTERM during $step leaves the helper running and pacman's lock held" "$(cat "$calls" "$test_tmp/err")"
  : >"$test_tmp/slow/go"
  set +e
  wait "$runner"
  status=$?
  set -e
  (( status == 0 )) || fail "the move interrupted during $step finishes" "status $status: $(cat "$test_tmp/err")"
  grep -Fxq 'rsync-done locked' "$calls" && grep -Fxq 'rm-done locked' "$calls" ||
    fail "SIGTERM during $step never releases the lock before the copy and removal are done" "$(cat "$calls")"
  if [[ $step == release ]]; then
    [[ ! -e $modules/$edge && $(cat "$root/var/lib/pacman/db.lck" 2>/dev/null) == other ]] ||
      fail "SIGTERM during the release leaves the next transaction's lock alone"
    rm -f "$root/var/lib/pacman/db.lck"
  else
    [[ ! -e $modules/$edge && ! -e $root/var/lib/pacman/db.lck ]] || fail "the move interrupted during $step completes and releases the lock"
  fi
done
pass "SIGTERM during the copy, the removal or the release keeps pacman's lock exactly as long as the move owns it"

downgraded
TEST_M1N1_FAILS=1 run_retire
(( status == 1 )) && grep -Fq "update-m1n1 failed after /usr/lib/modules/$edge was moved to /usr/lib/modules/.old; run sudo update-m1n1, then omarchy update" "$test_tmp/err" ||
  fail "a failed rebuild fails and names the way on" "status $status: $(cat "$test_tmp/err")"
run_retire
(( status == 0 )) && [[ ! -s $test_tmp/out ]] || fail "after a failed rebuild the directory is gone and a rerun changes nothing"
in_env "$stub_bin/update-m1n1"
expect_check_passes "after sudo update-m1n1 by hand"
pass "a failed rebuild fails with the manual step, which then passes the check"
