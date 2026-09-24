#!/bin/bash

# Migration 1790225826 removes the software-dsp.lua overlay that left WirePlumber
# spinning with no sinks on a J293 (#173). It must only remove a copy Omarchy
# shipped, never one the user edited, and only on Apple Silicon.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1790225826.sh"
fixtures="$ROOT/test/fixtures/software-dsp-overlay"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
home="$test_tmp/home"
sys_root="$test_tmp/usr/local/share"
sys_dsp="$sys_root/wireplumber/scripts/node/software-dsp.lua"
user_dsp="$home/.local/share/wireplumber/scripts/node/software-dsp.lua"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash

[[ ${APPLE_SILICON:-0} == "1" ]]
SH

# Stubbed rather than run: the real one would restart the running user's audio.
# SYSTEMCTL_HANG=until-kill makes a restart block, like a WirePlumber that
# ignores SIGTERM, until a SIGKILL has been sent; SYSTEMCTL_HANG=always blocks
# every restart. SYSTEMCTL_DEAD_AFTER_KILL=1 leaves the unit inactive once
# killed. The real timeout bounds each call.
cat >"$stub_bin/systemctl" <<'SH'
#!/bin/bash

printf 'systemctl' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
case $* in
  *is-active*)
    [[ ${SYSTEMCTL_DEAD_AFTER_KILL:-0} == 1 && -e $TEST_LOG.killed ]] && exit 3
    exit "${SYSTEMCTL_ACTIVE_STATUS:-0}"
    ;;
  *kill*) : >"$TEST_LOG.killed" ;;
  *restart*)
    case ${SYSTEMCTL_HANG:-} in
      always) exec sleep 30 ;;
      until-kill) [[ -e $TEST_LOG.killed ]] || exec sleep 30 ;;
    esac
    ;;
esac
exit 0
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

chmod +x "$stub_bin"/*

# omarchy-migrate runs migrations under bash -euo pipefail.
run_migration() {
  : >"$calls"
  rm -f "$calls.killed"

  OMARCHY_WIREPLUMBER_RESTART_TIMEOUT=1 APPLE_SILICON="${APPLE_SILICON:-1}" HOME="$home" TEST_LOG="$calls" \
    PATH="$stub_bin:$PATH" OMARCHY_ASAHI_SPEAKER_DSP="$sys_dsp" \
    bash -euo pipefail "$migration"
}

reset_tree() {
  rm -rf "$home" "${test_tmp:?}/usr"
  mkdir -p "$home/.local/share" "$sys_root"
}

place() {
  mkdir -p "$(dirname "$2")"
  cp "$1" "$2"
}

# Every shipped revision is recognised, machine-wide and per user.
for shipped in "$fixtures"/*.lua; do
  reset_tree
  place "$shipped" "$sys_dsp"
  place "$shipped" "$user_dsp"

  output=$(run_migration)
  name=$(basename "$shipped")

  [[ ! -e $sys_dsp && ! -e $user_dsp ]] ||
    fail "the shipped overlay $name is removed" "$(ls -R "$home" "$test_tmp/usr" 2>&1)"
  grep -Fq $'sudo\trm\t-f\t'"$sys_dsp" "$calls" ||
    fail "the machine-wide overlay $name is removed with sudo" "$(cat "$calls")"
  [[ ! -e $sys_root/wireplumber && ! -e $home/.local/share/wireplumber ]] ||
    fail "the directories the overlay $name created are removed once empty" "$(ls -R "$home" "$test_tmp/usr" 2>&1)"
  [[ -d $sys_root && -d $home/.local/share ]] ||
    fail "pruning stops at the share directories" "$(ls -R "$home" "$test_tmp/usr" 2>&1)"
  grep -Fq $'systemctl\t--user\ttry-restart\twireplumber.service' "$calls" ||
    fail "WirePlumber restarts after the overlay $name is removed" "$(cat "$calls")"
  ! grep -Fq -- '--signal=KILL' "$calls" ||
    fail "a WirePlumber that restarts cleanly is not killed" "$(cat "$calls")"
  [[ $output != *"Leaving"* ]] ||
    fail "a shipped overlay $name is not reported as modified" "$output"
done
pass "an overlay identical to a shipped revision is removed and WirePlumber restarts"

# Other WirePlumber scripts the user keeps survive, and so do their directories.
reset_tree
place "$fixtures/pr83.lua" "$user_dsp"
printf -- '-- mine\n' >"$home/.local/share/wireplumber/scripts/node/mine.lua"
run_migration >/dev/null
[[ ! -e $user_dsp && -f $home/.local/share/wireplumber/scripts/node/mine.lua ]] ||
  fail "only the overlay is removed from a directory the user also uses" "$(ls -R "$home" 2>&1)"
pass "other WirePlumber scripts the user keeps are left alone"

# A user who edited the overlay owns it now.
reset_tree
place "$fixtures/pr83.lua" "$sys_dsp"
place "$fixtures/pr83.lua" "$user_dsp"
printf -- '-- tuned by hand\n' >>"$sys_dsp"
printf -- '-- tuned by hand\n' >>"$user_dsp"
cp "$sys_dsp" "$test_tmp/sys.expected"
output=$(run_migration)
for kept in "$sys_dsp" "$user_dsp"; do
  cmp -s "$kept" "$test_tmp/sys.expected" ||
    fail "a modified overlay is kept" "$(ls -R "$home" "$test_tmp/usr" 2>&1)"
done
[[ $output == *"Leaving $sys_dsp in place"* && $output == *"Leaving $user_dsp in place"* ]] ||
  fail "a kept overlay is reported" "$output"
! grep -Eq $'^(sudo\trm|systemctl)' "$calls" ||
  fail "nothing is removed or restarted when every overlay was modified" "$(cat "$calls")"
pass "a modified overlay is kept with a note"

# A modified machine-wide copy does not stop the shipped per-user copy going.
reset_tree
place "$fixtures/pr83.lua" "$sys_dsp"
printf -- '-- tuned by hand\n' >>"$sys_dsp"
place "$fixtures/pr83.lua" "$user_dsp"
run_migration >/dev/null
[[ -f $sys_dsp && ! -e $user_dsp ]] ||
  fail "each copy is judged on its own" "$(ls -R "$home" "$test_tmp/usr" 2>&1)"
pass "each copy of the overlay is judged on its own"

# A symlink is not a copy Omarchy installed; it and its target stay.
reset_tree
mkdir -p "$(dirname "$user_dsp")"
cp "$fixtures/pr83.lua" "$test_tmp/linked.lua"
ln -s "$test_tmp/linked.lua" "$user_dsp"
run_migration >/dev/null
[[ -L $user_dsp && -f $test_tmp/linked.lua && ! -s $calls ]] ||
  fail "a symlinked overlay is left alone" "$(cat "$calls"; ls -lR "$home" 2>&1)"
pass "a symlinked overlay is left alone"

# Nothing to remove: no restart, no sudo.
reset_tree
run_migration >/dev/null
[[ ! -s $calls ]] ||
  fail "an install without the overlay is left untouched" "$(cat "$calls")"
pass "an install without the overlay is left untouched"

# A WirePlumber stuck on the overlay ignores SIGTERM: the restart times out,
# so the migration kills it and restarts again, and still succeeds.
reset_tree
place "$fixtures/pr83.lua" "$user_dsp"
SECONDS=0
output=$(SYSTEMCTL_HANG=until-kill run_migration) ||
  fail "a hung WirePlumber does not fail the migration"
(( SECONDS < 10 )) ||
  fail "the restart of a hung WirePlumber is bounded by the timeout" "took ${SECONDS}s"
grep -Fq $'systemctl\t--user\tkill\t--signal=KILL\twireplumber.service' "$calls" ||
  fail "a WirePlumber that ignores the restart is killed" "$(cat "$calls")"
grep -Fq $'systemctl\t--user\trestart\twireplumber.service' "$calls" ||
  fail "WirePlumber is started again after the kill" "$(cat "$calls")"
[[ $output != *"did not restart"* ]] ||
  fail "a WirePlumber restarted after the kill is not reported as failed" "$output"
pass "a WirePlumber that ignores SIGTERM is killed and restarted"

# A WirePlumber that never comes back does not hold up the update either; the
# overlay is gone, so the next login recovers, and the user is told so.
reset_tree
place "$fixtures/pr83.lua" "$user_dsp"
SECONDS=0
output=$(SYSTEMCTL_HANG=always SYSTEMCTL_DEAD_AFTER_KILL=1 run_migration) ||
  fail "a WirePlumber that never restarts does not fail the migration"
(( SECONDS < 10 )) ||
  fail "every restart attempt is bounded by the timeout" "took ${SECONDS}s"
[[ ! -e $user_dsp ]] ||
  fail "the overlay is removed even when WirePlumber cannot restart"
[[ $output == *"log out and back in"* ]] ||
  fail "a WirePlumber that did not restart is reported" "$output"
pass "a WirePlumber that never restarts does not hold up the update"

# A restart that returns success is not proof WirePlumber is running: the
# unit can be left inactive after the kill, and the user still hears nothing.
reset_tree
place "$fixtures/pr83.lua" "$user_dsp"
output=$(SYSTEMCTL_HANG=until-kill SYSTEMCTL_DEAD_AFTER_KILL=1 run_migration) ||
  fail "an inactive WirePlumber after the fallback does not fail the migration"
[[ $output == *"log out and back in"* ]] ||
  fail "an inactive WirePlumber after a successful restart call is reported" "$output"
pass "WirePlumber's state is checked after the fallback, whatever the restart returned"

# Without a running WirePlumber (no user session) there is nothing to restart.
reset_tree
place "$fixtures/pr83.lua" "$user_dsp"
SYSTEMCTL_ACTIVE_STATUS=3 run_migration >/dev/null ||
  fail "a missing user session does not fail the migration"
[[ ! -e $user_dsp ]] ||
  fail "the overlay is removed without a user session" "$(ls -R "$home" 2>&1)"
! grep -Eq $'try-restart|kill' "$calls" ||
  fail "nothing is restarted without a running WirePlumber" "$(cat "$calls")"
pass "a missing user session is handled"

# Intel and T2 Macs and x86 PCs never had the overlay installed by Omarchy.
reset_tree
place "$fixtures/pr83.lua" "$sys_dsp"
place "$fixtures/pr83.lua" "$user_dsp"
APPLE_SILICON=0 run_migration >/dev/null
[[ -f $sys_dsp && -f $user_dsp && ! -s $calls ]] ||
  fail "the migration leaves hardware without Apple Silicon alone" "$(cat "$calls"; ls -R "$home" "$test_tmp/usr" 2>&1)"
pass "the migration leaves hardware without Apple Silicon alone"

# Running it again after a removal does nothing.
reset_tree
place "$fixtures/pr83.lua" "$user_dsp"
run_migration >/dev/null
run_migration >/dev/null
[[ ! -s $calls ]] ||
  fail "the migration is idempotent" "$(cat "$calls")"
pass "the migration is idempotent"

echo "apple-software-dsp-removal: all checks passed"
