#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_root="$test_tmp/omarchy"
test_home="$test_tmp/home"
calls="$test_tmp/calls"
mkdir -p "$test_root/bin" "$test_root/migrations" "$test_home"

cat >"$test_root/bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$test_root/bin/omarchy-hw-apple-silicon"

for migration in 1778623107.sh 1780057136.sh 1781984677.sh; do
  cat >"$test_root/migrations/$migration" <<SH
printf '%s\n' '$migration' >>"\$TEST_CALLS"
SH
done

HOME="$test_home" OMARCHY_PATH="$test_root" TEST_CALLS="$calls" \
  "$ROOT/bin/omarchy-migrate" >"$test_tmp/migrate.out"

state_dir="$test_home/.local/state/omarchy/migrations"
[[ $(<"$calls") == "1780057136.sh" ]] || fail "Asahi migration policy runs only reviewed architecture-neutral migrations"
[[ -f $state_dir/1780057136.sh ]] || fail "Asahi migration policy records normal completion"
[[ -f $state_dir/1778623107.sh.skipped ]] || fail "Asahi migration policy records handled transitions"
[[ -f $state_dir/1781984677.sh.skipped ]] || fail "Asahi migration policy records inapplicable transitions"
grep -Fq $'handled\tmpv-mpris installed' "$state_dir/1778623107.sh.skipped" || fail "handled marker records its reason"
grep -Fq $'skipped\tSnapper and Limine' "$state_dir/1781984677.sh.skipped" || fail "skipped marker records its reason"
[[ ! -f $state_dir/1778623107.sh && ! -f $state_dir/1781984677.sh ]] || fail "Asahi policy does not fabricate completion markers"
pass "Asahi migration policy records reviewed dispositions"

if HOME="$test_home" OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-migrate" --pending >"$test_tmp/pending.out"; then
  fail "settled Asahi migrations are not pending"
fi
[[ ! -s $test_tmp/pending.out ]] || fail "settled Asahi migration check stays quiet"
pass "Asahi skipped markers settle migrations"

: >"$state_dir/1778623107.sh.skipped"
HOME="$test_home" OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-migrate" --pending >"$test_tmp/malformed-pending.out"
grep -Fxq '1778623107.sh' "$test_tmp/malformed-pending.out" || fail "malformed Asahi marker remains pending"
HOME="$test_home" OMARCHY_PATH="$test_root" TEST_CALLS="$calls" \
  "$ROOT/bin/omarchy-migrate" >"$test_tmp/repair-marker.out"
grep -Fq $'handled\tmpv-mpris installed' "$state_dir/1778623107.sh.skipped" || fail "Asahi policy repairs malformed markers"
pass "Asahi migration policy rejects malformed skip markers"

cat >"$test_root/migrations/9999999999.sh" <<'SH'
printf '%s\n' unknown >>"$TEST_CALLS"
SH
if HOME="$test_home" OMARCHY_PATH="$test_root" TEST_CALLS="$calls" \
  "$ROOT/bin/omarchy-migrate" >"$test_tmp/unknown.out" 2>"$test_tmp/unknown.err"; then
  fail "unreviewed Apple Silicon migrations are blocked"
fi
grep -Fq 'has not been reviewed for Apple Silicon' "$test_tmp/unknown.err" || fail "unreviewed migration failure is actionable"
! grep -Fxq unknown "$calls" || fail "unreviewed Apple Silicon migration did not execute"
pass "Asahi migration policy fails closed for unknown migrations"
