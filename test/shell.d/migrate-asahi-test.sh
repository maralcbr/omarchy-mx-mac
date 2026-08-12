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

for migration in 1778623107.sh 1780057136.sh 1781984677.sh 1784809451.sh 1784961000.sh 1785013000.sh 1785090473.sh; do
  cat >"$test_root/migrations/$migration" <<SH
printf '%s\n' '$migration' >>"\$TEST_CALLS"
SH
done

HOME="$test_home" OMARCHY_PATH="$test_root" TEST_CALLS="$calls" \
  "$ROOT/bin/omarchy-migrate" >"$test_tmp/migrate.out"

state_dir="$test_home/.local/state/omarchy/migrations"
[[ $(<"$calls") == $'1780057136.sh\n1784809451.sh' ]] || fail "Asahi migration policy runs only reviewed architecture-neutral migrations"
[[ -f $state_dir/1780057136.sh ]] || fail "Asahi migration policy records normal completion"
[[ -f $state_dir/1784809451.sh ]] || fail "Asahi migration policy runs reviewed locate migration"
[[ -f $state_dir/1778623107.sh.skipped ]] || fail "Asahi migration policy records handled transitions"
[[ -f $state_dir/1781984677.sh.skipped ]] || fail "Asahi migration policy records inapplicable transitions"
[[ -f $state_dir/1784961000.sh.skipped && -f $state_dir/1785013000.sh.skipped ]] || fail "Asahi migration policy holds zram tuning"
[[ -f $state_dir/1785090473.sh.skipped ]] || fail "Asahi migration policy skips unsupported fingerprint replacement"
grep -Fq $'handled\tmpv-mpris installed' "$state_dir/1778623107.sh.skipped" || fail "handled marker records its reason"
grep -Fq $'skipped\tSnapper and Limine' "$state_dir/1781984677.sh.skipped" || fail "skipped marker records its reason"
grep -Fq $'skipped\tzram tuning is held' "$state_dir/1784961000.sh.skipped" || fail "zram marker records its reason"
grep -Fq $'skipped\tfingerprint hardware is unsupported' "$state_dir/1785090473.sh.skipped" || fail "fingerprint marker records its reason"
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

rm -f "$test_root/migrations"/* "$state_dir"/*
for migration in "$ROOT"/migrations/*.sh; do
  filename=$(basename "$migration")
  printf ':\n' >"$test_root/migrations/$filename"
done
HOME="$test_home" OMARCHY_PATH="$test_root" TEST_CALLS="$calls" \
  "$ROOT/bin/omarchy-migrate" >"$test_tmp/all-reviewed.out"
pass "Asahi migration policy reviews every bundled migration"

for migration in 1785273276.sh 1785424256.sh 1785637426.sh 1785944594.sh 1786137597.sh 1786273938.sh 1786355450.sh 1786482992.sh; do
  [[ -f $state_dir/$migration.skipped ]] || fail "Asahi migration policy skips $migration"
done
grep -Fq $'skipped\tT2 Limine and mkinitcpio' "$state_dir/1785273276.sh.skipped" || fail "T2 migration records its Apple Silicon reason"
grep -Fq $'skipped\tsystemd-oomd reclaim tuning' "$state_dir/1785424256.sh.skipped" || fail "oomd migration records its Asahi reason"
grep -Fq $'skipped\tomacalc is unavailable' "$state_dir/1785637426.sh.skipped" || fail "omacalc migration records its repository reason"
grep -Fq $'skipped\tT2 Limine and mkinitcpio' "$state_dir/1785944594.sh.skipped" || fail "T2 defaults migration records its Apple Silicon reason"
grep -Fq $'skipped\therdr is unavailable' "$state_dir/1786273938.sh.skipped" || fail "herdr migration records its repository reason"
grep -Fq $'skipped\tttfx is unavailable' "$state_dir/1786355450.sh.skipped" || fail "ttfx migration records its repository reason"
grep -Fq $'skipped\tLimine boot image repair' "$state_dir/1786482992.sh.skipped" || fail "Limine repair migration records its Asahi reason"
pass "Asahi migration policy blocks unvalidated platform changes"

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
