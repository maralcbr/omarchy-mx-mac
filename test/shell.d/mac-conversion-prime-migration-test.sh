#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Migration 1790462702 primes the move onto Omarchy's packages: on Apple
# Silicon it runs omarchy-mac-migrate-bootstrap --prime as root for the channel
# the Mac follows, passes its deferral (75) or failure on, and writes the marker
# omarchy update converts on only once the package is ready.
migration=$ROOT/migrations/1790462702.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
printf '#!/bin/bash\n[[ $(cat "$FIXTURE/platform") == apple-silicon ]]\n' >"$tmp/bin/omarchy-hw-apple-silicon"
printf '#!/bin/bash\n[[ $1 == current ]] && cat "$FIXTURE/channel"\n' >"$tmp/bin/omarchy-apple-silicon-channel"
printf '#!/bin/bash\necho "bootstrap $*" >>"$FIXTURE/ran"\nexit "$(cat "$FIXTURE/status")"\n' >"$tmp/bin/omarchy-mac-migrate-bootstrap"
cat >"$tmp/bin/sudo" <<'SH'
#!/bin/bash
echo "sudo $*" >>"$FIXTURE/ran"
exec "$@"
SH
chmod 755 "$tmp/bin"/*
marker=$tmp/state/1790462702

run_migration() {
  rm -f "$tmp/ran"
  FIXTURE=$tmp PATH="$tmp/bin:$PATH" OMARCHY_PATH=$ROOT OMARCHY_MAC_CONVERSION_MARKER=$marker bash -euo pipefail "$migration"
}

[[ $(stat -c %a "$migration") == 644 ]] || fail "the migration is mode 644"
head -n 1 "$migration" | grep -q '^echo ' || fail "the migration starts with an echo"

echo generic >"$tmp/platform"
echo 0 >"$tmp/status"
echo rc >"$tmp/channel"
run_migration >/dev/null || fail "another platform: the migration completes"
[[ ! -e $tmp/ran && ! -e $marker ]] || fail "another platform: nothing runs"
pass "anything but an Apple Silicon Mac completes the migration and runs nothing"

echo apple-silicon >"$tmp/platform"
for status in 75 1; do
  echo "$status" >"$tmp/status"
  result=0
  run_migration >/dev/null 2>&1 || result=$?
  (( result == status )) && [[ ! -e $marker ]] || fail "a bootstrap exiting $status leaves the migration pending with that status" "status $result"
done
echo 0 >"$tmp/status"
run_migration >/dev/null || fail "a Mac: the migration completes once the package is primed"
[[ $(sed -n 1,2p "$tmp/ran") == $'sudo omarchy-mac-migrate-bootstrap --prime --channel rc\nbootstrap --prime --channel rc' && -e $marker ]] ||
  fail "a Mac primes its own channel's package as root, then writes the marker" "$(cat "$tmp/ran")"
run_migration >/dev/null && [[ ! -e $tmp/ran ]] || fail "another account: nothing runs once the Mac is primed"
rm "$marker"
echo unknown >"$tmp/channel"
run_migration >/dev/null && grep -qx "bootstrap --prime --channel stable" "$tmp/ran" || fail "a Mac whose channel is unknown primes stable" "$(cat "$tmp/ran")"
pass "a Mac primes the official package for its own channel, stays pending while that defers or fails, and marks it once"

# The conversion comes first in omarchy update, before any fork update, and
# the update stops once it has run.
update=$ROOT/bin/omarchy-update
conversion=$(grep -n 'sudo omarchy-mac-migrate-bootstrap || conversion_status' "$update" | cut -d: -f1)
dev=$(grep -n '^  omarchy-update-dev$' "$update" | cut -d: -f1)
bundle=$(grep -n 'omarchy-update-asahi-bundle --yes' "$update" | cut -d: -f1)
[[ -n $conversion && $conversion -lt $dev && $conversion -lt $bundle ]] || fail "omarchy update converts a primed Mac before any fork update"
grep -q '/var/lib/omarchy/migrations/1790462702' "$update" || fail "omarchy update converts only a primed Mac"
awk -v from="$conversion" 'NR > from && /conversion_status == 0/ { found = 1 } found && /exit 0/ { ok = 1; exit } END { exit !ok }' "$update" ||
  fail "a converted Mac's update stops there"
pass "omarchy update converts a primed Mac before any fork update and stops there"
