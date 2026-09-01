#!/bin/bash

# Tests for preclean-m1.sh using its OMARCHY_PRECLEAN_SSH_SHIM hook.
# No ssh is run and no disk is touched: the shim feeds canned diskutil
# output and records every destructive command the script asks for.
#
# Run: bash iteration2/test/preclean-m1-test.sh

set -uo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
readonly PRECLEAN="$script_dir/../preclean-m1.sh"
[[ -x $PRECLEAN || -f $PRECLEAN ]] || { echo "cannot find preclean-m1.sh" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/preclean-test.XXXXXX")
trap 'rm -rf "$work"' EXIT

failures=0
current_test=""

fail() {
  echo "FAIL [$current_test] $*" >&2
  failures=$((failures + 1))
}

assert_contains() {
  local file=$1 needle=$2
  grep -qF -- "$needle" "$file" || fail "expected to find: $needle (in $(basename "$file"))"
}

assert_not_contains() {
  local file=$1 needle=$2
  ! grep -qF -- "$needle" "$file" || fail "expected NOT to find: $needle (in $(basename "$file"))"
}

assert_line_count() {
  local file=$1 pattern=$2 expected=$3 actual
  actual=$(grep -cF -- "$pattern" "$file" 2>/dev/null)
  [[ $actual == "$expected" ]] || fail "expected $expected lines matching '$pattern', got $actual"
}

# ---------------------------------------------------------------------------
# Shim
# ---------------------------------------------------------------------------

cat >"$work/shim.sh" <<'SHIM'
#!/bin/bash
op=$1
cmd=$2
# Emulate ssh's default stdin behavior: consume whatever is on stdin. This is
# what silently ate the erase loop's target list until ssh -n was added.
[[ -t 0 ]] || cat >/dev/null
case $op in
  identity) printf 'mina\nMacBookPro18,3\n' ;;
  partitions) cat "$SHIM_DATA_DIR/partitions.tsv" ;;
  containers) cat "$SHIM_DATA_DIR/containers.tsv" ;;
  app-support) printf 'present\t2048\t/Users/mina/Library/Application Support/com.omarchy.mx.installer\n' ;;
  old-apps) printf '/Applications/Omarchy MX Mac Installer.app\n' ;;
  recheck) printf '%s\n' "${SHIM_RECHECK_NAME:-}" ;;
  exists)
    for absent in ${SHIM_ABSENT_UUIDS:-}; do
      [[ $cmd == *"$absent"* ]] && exit 1
    done
    exit 0
    ;;
  delete-container|erase-volume|clear-app-support|remove-old-app)
    printf '%s\t%s\n' "$op" "$cmd" >>"$SHIM_LOG" ;;
  *) echo "shim: unexpected operation '$op'" >&2; exit 97 ;;
esac
SHIM
chmod +x "$work/shim.sh"

# Layout mirroring the M1 with TWO Omarchy installs: macOS (disk0s2),
# Recovery (disk0s7), ISC (disk0s1), and per install one APFS stub, one
# "EFI - OMARC" ESP, and boot+root Linux partitions.
write_two_install_layout() {
  local dir=$1
  mkdir -p "$dir"
  printf '%s\n' \
    $'disk0s1\tApple_APFS_ISC\tiSCPreboot\tUUID-ISC-0001\t524288000' \
    $'disk0s2\tApple_APFS\t-\tUUID-MACOS-0002\t494384795648' \
    $'disk0s3\tApple_APFS\t-\tUUID-STUB-0003\t2500000000' \
    $'disk0s4\tMicrosoft Basic Data\tEFI - OMARC\tUUID-ESP-0004\t524288000' \
    $'disk0s5\tLinux Filesystem\t-\tUUID-BOOT-0005\t1073741824' \
    $'disk0s6\tLinux Filesystem\t-\tUUID-ROOT-0006\t50000000000' \
    $'disk0s8\tApple_APFS\t-\tUUID-STUB-0008\t2500000000' \
    $'disk0s9\tMicrosoft Basic Data\tEFI - OMARC\tUUID-ESP-0009\t524288000' \
    $'disk0s10\tLinux Filesystem\t-\tUUID-BOOT-0010\t1073741824' \
    $'disk0s11\tLinux Filesystem\t-\tUUID-ROOT-0011\t50000000000' \
    $'disk0s7\tApple_APFS_Recovery\t-\tUUID-RECOV-0007\t5368664064' \
    >"$dir/partitions.tsv"
  printf '%s\n' \
    $'disk3\tCUUID-MACOS\tdisk0s2\tUUID-MACOS-0002\tMacintosh HD,Macintosh HD - Data,Preboot,Recovery,VM,Update,xART' \
    $'disk4\tCUUID-STUB-A\tdisk0s3\tUUID-STUB-0003\tOmarchy' \
    $'disk5\tCUUID-STUB-B\tdisk0s8\tUUID-STUB-0008\tOmarchy' \
    >"$dir/containers.tsv"
}

run_preclean() {
  local data_dir=$1 log=$2
  shift 2
  SHIM_DATA_DIR="$data_dir" SHIM_LOG="$log" \
    OMARCHY_PRECLEAN_SSH_SHIM="$work/shim.sh" \
    bash "$PRECLEAN" "$@"
}

# ---------------------------------------------------------------------------
# 1. Dry run with two installs: full plan, nothing executed
# ---------------------------------------------------------------------------

current_test="dry-run-two-installs"
data="$work/two"; write_two_install_layout "$data"
log="$work/log.$current_test"; : >"$log"
out="$work/out.$current_test"
run_preclean "$data" "$log" >"$out" 2>&1
status=$?
[[ $status == 0 ]] || fail "expected exit 0, got $status"
assert_contains "$out" "found 2 Omarchy APFS container(s)"
assert_contains "$out" "WOULD RUN: /usr/sbin/diskutil apfs deleteContainer CUUID-STUB-A"
assert_contains "$out" "WOULD RUN: /usr/sbin/diskutil apfs deleteContainer CUUID-STUB-B"
assert_contains "$out" "targets=8"
assert_contains "$out" "result=dry-run"
assert_contains "$out" "UUID-MACOS-0002"
assert_contains "$out" "UUID-RECOV-0007"
assert_not_contains "$out" "WOULD RUN: /usr/sbin/diskutil eraseVolume free none UUID-MACOS-0002"
assert_not_contains "$out" "WOULD RUN: /usr/sbin/diskutil eraseVolume free none UUID-RECOV-0007"
[[ ! -s $log ]] || fail "dry run executed destructive commands: $(cat "$log")"

# ---------------------------------------------------------------------------
# 2. Confirmed run with two installs: both containers and all 8 partitions
# ---------------------------------------------------------------------------

current_test="confirm-two-installs"
log="$work/log.$current_test"; : >"$log"
out="$work/out.$current_test"
run_preclean "$data" "$log" --confirm >"$out" 2>&1
status=$?
[[ $status == 0 ]] || fail "expected exit 0, got $status"
assert_contains "$out" "result=performed"
assert_contains "$out" "destructive_commands_run=12"
assert_line_count "$log" "delete-container" 2
assert_line_count "$log" "erase-volume" 8
assert_line_count "$log" "clear-app-support" 1
assert_line_count "$log" "remove-old-app" 1
assert_contains "$log" "deleteContainer CUUID-STUB-A"
assert_contains "$log" "deleteContainer CUUID-STUB-B"
for uuid in UUID-STUB-0003 UUID-ESP-0004 UUID-BOOT-0005 UUID-ROOT-0006 \
            UUID-STUB-0008 UUID-ESP-0009 UUID-BOOT-0010 UUID-ROOT-0011; do
  assert_contains "$log" "eraseVolume free none $uuid"
done
assert_not_contains "$log" "UUID-MACOS-0002"
assert_not_contains "$log" "UUID-RECOV-0007"
assert_not_contains "$log" "UUID-ISC-0001"

# ---------------------------------------------------------------------------
# 2b. Stores already removed by deleteContainer are skipped, not failed
# ---------------------------------------------------------------------------

current_test="confirm-store-already-removed"
log="$work/log.$current_test"; : >"$log"
out="$work/out.$current_test"
SHIM_ABSENT_UUIDS="UUID-STUB-0003 UUID-STUB-0008" \
  run_preclean "$data" "$log" --confirm >"$out" 2>&1
status=$?
[[ $status == 0 ]] || fail "expected exit 0, got $status"
assert_contains "$out" "result=performed"
assert_contains "$out" "already freed Omarchy APFS stub store"
assert_line_count "$log" "delete-container" 2
assert_line_count "$log" "erase-volume" 6
assert_not_contains "$log" "UUID-STUB-0003"
assert_not_contains "$log" "UUID-STUB-0008"
assert_contains "$out" "destructive_commands_run=10"

# ---------------------------------------------------------------------------
# 3. A container holding both Omarchy and Macintosh HD: hard abort
# ---------------------------------------------------------------------------

current_test="conflicted-container-aborts"
data="$work/conflicted"; write_two_install_layout "$data"
printf '%s\n' \
  $'disk3\tCUUID-WEIRD\tdisk0s2\tUUID-MACOS-0002\tMacintosh HD,Omarchy,Preboot' \
  $'disk4\tCUUID-STUB-A\tdisk0s3\tUUID-STUB-0003\tOmarchy' \
  >"$data/containers.tsv"
log="$work/log.$current_test"; : >"$log"
out="$work/out.$current_test"
run_preclean "$data" "$log" --confirm >"$out" 2>&1
status=$?
[[ $status != 0 ]] || fail "expected a hard abort, got exit 0"
assert_contains "$out" "HARD ABORT"
assert_contains "$out" "holds both"
[[ ! -s $log ]] || fail "abort still executed destructive commands: $(cat "$log")"

# ---------------------------------------------------------------------------
# 4. Single install still works (regression)
# ---------------------------------------------------------------------------

current_test="single-install"
data="$work/single"; write_two_install_layout "$data"
grep -v -e UUID-STUB-0008 -e UUID-ESP-0009 -e UUID-BOOT-0010 -e UUID-ROOT-0011 \
  "$work/two/partitions.tsv" >"$data/partitions.tsv"
grep -v CUUID-STUB-B "$work/two/containers.tsv" >"$data/containers.tsv"
log="$work/log.$current_test"; : >"$log"
out="$work/out.$current_test"
run_preclean "$data" "$log" >"$out" 2>&1
status=$?
[[ $status == 0 ]] || fail "expected exit 0, got $status"
assert_contains "$out" "found 1 Omarchy APFS container(s)"
assert_contains "$out" "targets=4"

# ---------------------------------------------------------------------------
# 5. No Omarchy at all: empty plan
# ---------------------------------------------------------------------------

current_test="no-omarchy"
data="$work/none"; write_two_install_layout "$data"
grep -Ev 'UUID-(STUB|ESP|BOOT|ROOT)-' "$work/two/partitions.tsv" >"$data/partitions.tsv"
grep -v CUUID-STUB "$work/two/containers.tsv" >"$data/containers.tsv"
log="$work/log.$current_test"; : >"$log"
out="$work/out.$current_test"
run_preclean "$data" "$log" >"$out" 2>&1
status=$?
[[ $status == 0 ]] || fail "expected exit 0, got $status"
assert_contains "$out" "No Omarchy partitions found"
assert_contains "$out" "targets=0"

# ---------------------------------------------------------------------------
# 6. Pre-erase recheck sees a protected name: abort before any eraseVolume
# ---------------------------------------------------------------------------

current_test="recheck-guard"
data="$work/two"
log="$work/log.$current_test"; : >"$log"
out="$work/out.$current_test"
SHIM_RECHECK_NAME="Macintosh HD" \
  run_preclean "$data" "$log" --confirm >"$out" 2>&1
status=$?
[[ $status != 0 ]] || fail "expected a hard abort, got exit 0"
assert_contains "$out" "refusing to erase it"
assert_line_count "$log" "delete-container" 2
assert_line_count "$log" "erase-volume" 0

# ---------------------------------------------------------------------------

echo
if (( failures == 0 )); then
  echo "preclean-m1-test: all tests passed"
  exit 0
fi
echo "preclean-m1-test: $failures assertion(s) failed" >&2
exit 1
