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

for migration in 1778623107.sh 1780057136.sh 1781984677.sh 1784809451.sh 1784961000.sh 1785013000.sh 1785090473.sh 1786782461.sh 1786952219.sh 1787133200.sh 1787399318.sh 1787481315.sh 1787494718.sh 1787580187.sh 1787618700.sh; do
  cat >"$test_root/migrations/$migration" <<SH
printf '%s\n' '$migration' >>"\$TEST_CALLS"
SH
done

HOME="$test_home" OMARCHY_PATH="$test_root" TEST_CALLS="$calls" \
  "$ROOT/bin/omarchy-migrate" >"$test_tmp/migrate.out"

state_dir="$test_home/.local/state/omarchy/migrations"
[[ $(<"$calls") == $'1780057136.sh\n1784809451.sh\n1786782461.sh\n1787133200.sh\n1787481315.sh\n1787494718.sh\n1787580187.sh\n1787618700.sh' ]] || fail "Asahi migration policy runs only reviewed architecture-neutral migrations"
[[ -f $state_dir/1780057136.sh ]] || fail "Asahi migration policy records normal completion"
[[ -f $state_dir/1784809451.sh ]] || fail "Asahi migration policy runs reviewed locate migration"
[[ -f $state_dir/1778623107.sh.skipped ]] || fail "Asahi migration policy records handled transitions"
[[ -f $state_dir/1781984677.sh.skipped ]] || fail "Asahi migration policy records inapplicable transitions"
[[ -f $state_dir/1784961000.sh.skipped && -f $state_dir/1785013000.sh.skipped ]] || fail "Asahi migration policy settles zram tuning"
[[ -f $state_dir/1785090473.sh.skipped ]] || fail "Asahi migration policy skips unsupported fingerprint replacement"
[[ -f $state_dir/1786782461.sh ]] || fail "Asahi migration policy runs the Foot config repair"
[[ -f $state_dir/1786952219.sh.skipped ]] || fail "Asahi migration policy keeps the validated mise package"
[[ -f $state_dir/1787133200.sh ]] || fail "Asahi migration policy installs Qt image formats"
[[ -f $state_dir/1787399318.sh.skipped ]] || fail "Asahi migration policy keeps the validated Quickshell package"
[[ -f $state_dir/1787481315.sh ]] || fail "Asahi migration policy restages the active theme"
[[ -f $state_dir/1787494718.sh ]] || fail "Asahi migration policy runs the FIDO2 authfile repair"
[[ -f $state_dir/1787580187.sh ]] || fail "Asahi migration policy runs Docker group hardening"
[[ -f $state_dir/1787618700.sh ]] || fail "Asahi migration policy runs the input-device state repair"
grep -Fq $'handled\tmpv-mpris installed' "$state_dir/1778623107.sh.skipped" || fail "handled marker records its reason"
grep -Fq $'skipped\tSnapper and Limine' "$state_dir/1781984677.sh.skipped" || fail "skipped marker records its reason"
grep -Fq $'handled\tzram config and reclaim tuning ship' "$state_dir/1784961000.sh.skipped" || fail "zram marker records its reason"
grep -Fq $'skipped\tfingerprint hardware is unsupported' "$state_dir/1785090473.sh.skipped" || fail "fingerprint marker records its reason"
grep -Fq $'skipped\tmise-bin is unavailable' "$state_dir/1786952219.sh.skipped" || fail "mise migration records its Apple Silicon reason"
grep -Fq $'skipped\tvalidated quickshell-git remains' "$state_dir/1787399318.sh.skipped" || fail "Quickshell migration records its Apple Silicon reason"
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

for migration in 1787215483.sh 1787760281.sh 1787843905.sh 1788577553.sh 1788619462.sh 1788662350.sh 1788724825.sh 1788745941.sh 1788848726.sh 1789172112.sh; do
  [[ -f $state_dir/$migration && ! -e $state_dir/$migration.skipped ]] || fail "4.0.3 migration $migration runs on Apple Silicon"
done
pass "Asahi runs the reviewed 4.0.3 migrations"

for migration in 1785273276.sh 1785424256.sh 1785944594.sh 1786137597.sh 1786391100.sh 1786482992.sh; do
  [[ -f $state_dir/$migration.skipped ]] || fail "Asahi migration policy skips $migration"
done
grep -Fq $'skipped\tT2 Limine and mkinitcpio' "$state_dir/1785273276.sh.skipped" || fail "T2 migration records its Apple Silicon reason"
grep -Fq $'skipped\tsystemd-oomd reclaim tuning' "$state_dir/1785424256.sh.skipped" || fail "oomd migration records its Asahi reason"
grep -Fq $'skipped\tT2 Limine and mkinitcpio' "$state_dir/1785944594.sh.skipped" || fail "T2 defaults migration records its Apple Silicon reason"
for migration in 1781286586.sh 1785637426.sh 1786273938.sh 1786355450.sh; do
  [[ -f $state_dir/$migration ]] || fail "Asahi migration policy runs the package migration $migration now that the package is built for aarch64"
done
grep -Fq $'skipped\tIntel Mac Broadcom firmware quirk' "$state_dir/1786391100.sh.skipped" || fail "Broadcom migration records its Apple Silicon reason"
grep -Fq $'skipped\tLimine boot image repair' "$state_dir/1786482992.sh.skipped" || fail "Limine repair migration records its Asahi reason"
[[ -f $state_dir/1787560726.sh ]] || fail "package repository migration is reviewed to run on Apple Silicon"
pass "Asahi migration policy blocks unvalidated platform changes"

for migration in 1789325478.sh 1789444024.sh; do
  [[ -f $state_dir/$migration.skipped && ! -e $state_dir/$migration ]] || fail "4.0.4 kernel migration $migration is skipped on Apple Silicon"
done
grep -Fq $'skipped\tx86_64 linux-omarchy kernel and Limine boot order' "$state_dir/1789325478.sh.skipped" || fail "kernel migration records its Apple Silicon reason"
grep -Fq $'skipped\tlinux-omarchy and linux-t2 header repair' "$state_dir/1789444024.sh.skipped" || fail "header migration records its Apple Silicon reason"
pass "Asahi skips the reviewed 4.0.4 kernel migrations"

[[ -f $state_dir/1789879296.sh && ! -e $state_dir/1789879296.sh.skipped ]] ||
  fail "Aurora leftover headers migration runs on Apple Silicon"
pass "Asahi runs the Aurora leftover linux-asahi-headers repair"

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

# The real 4.0.4 kernel migrations must never execute on Apple Silicon, even
# where their own architecture checks would pass: every tool they could reach
# is a logging stub, and uname claims x86_64.
kernel_root="$test_tmp/kernel-omarchy"
kernel_home="$test_tmp/kernel-home"
kernel_stubs="$test_tmp/kernel-stubs"
mkdir -p "$kernel_root/bin" "$kernel_root/migrations" "$kernel_home" "$kernel_stubs"
cp "$test_root/bin/omarchy-hw-apple-silicon" "$kernel_root/bin/"
cp "$ROOT/migrations/1789325478.sh" "$ROOT/migrations/1789444024.sh" "$kernel_root/migrations/"
for tool in pacman sudo limine-mkinitcpio limine-entry-tool omarchy-pkg-add omarchy-pkg-present omarchy-state; do
  cat >"$kernel_stubs/$tool" <<SH
#!/bin/bash
printf '%s %s\n' '$tool' "\$*" >>"\$TEST_CALLS"
SH
done
cat >"$kernel_stubs/uname" <<'SH'
#!/bin/bash
case "$1" in
  -m) echo x86_64 ;;
  *) echo 7.2.5-arch1-1 ;;
esac
SH
chmod +x "$kernel_stubs"/*
: >"$calls"
HOME="$test_home" OMARCHY_PATH="$kernel_root" OMARCHY_MIGRATION_STATE="$kernel_home/state" \
  TEST_CALLS="$calls" PATH="$kernel_stubs:$PATH" \
  "$ROOT/bin/omarchy-migrate" >"$test_tmp/kernel.out"
[[ ! -s $calls ]] || fail "4.0.4 kernel migrations do not execute on Apple Silicon" "$(<"$calls")"
for migration in 1789325478.sh 1789444024.sh; do
  [[ -f $kernel_home/state/$migration.skipped && ! -e $kernel_home/state/$migration ]] ||
    fail "4.0.4 kernel migration $migration settles as skipped"
done
pass "Apple Silicon settles the 4.0.4 kernel migrations without touching packages or boot files"
