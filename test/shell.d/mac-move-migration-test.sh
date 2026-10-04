#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The final release moves a Mac onto Omarchy's official packages: migration
# 1790462702 marks an Apple Silicon Mac once, machine-wide, and omarchy update
# then runs the vendored omarchy-mac-migrate before any fork update, stopping
# once it moved the Mac and going on as before while the move defers.
migration=$ROOT/migrations/1790462702.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
printf '#!/bin/bash\n[[ $(cat "$FIXTURE/platform") == apple-silicon ]]\n' >"$tmp/bin/omarchy-hw-apple-silicon"
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
run_migration >/dev/null || fail "another platform: the migration completes"
[[ ! -e $tmp/ran && ! -e $marker ]] || fail "another platform: nothing runs"
pass "anything but an Apple Silicon Mac completes the migration and marks nothing"

echo apple-silicon >"$tmp/platform"
run_migration >/dev/null || fail "a Mac: the migration completes"
[[ -e $marker ]] && grep -q "^sudo install -Dm644 /dev/null $marker$" "$tmp/ran" || fail "a Mac is marked as root" "$(cat "$tmp/ran" 2>/dev/null)"
run_migration >/dev/null && [[ ! -e $tmp/ran ]] || fail "another account: nothing runs once the Mac is marked"
pass "a Mac is marked for the move once, machine-wide"

# The vendored tool is omacom/omarchy-mac's release asset, byte for byte.
vendored_sha256=879faa6520e0e6d6dbdd7f9b7d086e34ab5f5822ab171c10db21a338042d72cc
[[ $(sha256sum "$ROOT/bin/omarchy-mac-migrate" | cut -d' ' -f1) == "$vendored_sha256" ]] ||
  fail "bin/omarchy-mac-migrate is the omacom/omarchy-mac mac-migrate-v1 release asset"
pass "bin/omarchy-mac-migrate is vendored byte for byte from omacom/omarchy-mac"

update=$ROOT/bin/omarchy-update
move=$(grep -n 'sudo "$OMARCHY_PATH/bin/omarchy-mac-migrate" run || conversion_status' "$update" | cut -d: -f1)
dev=$(grep -n '^  omarchy-update-dev$' "$update" | cut -d: -f1)
bundle=$(grep -n 'omarchy-update-asahi-bundle --yes' "$update" | cut -d: -f1)
[[ -n $move && -n $dev && -n $bundle ]] && (( move < dev && move < bundle )) || fail "omarchy update moves a marked Mac before any fork update" "move $move dev $dev bundle $bundle"
grep -q '/var/lib/omarchy/migrations/1790462702' "$update" || fail "omarchy update moves only a marked Mac"
awk -v from="$move" 'NR > from && /conversion_status == 0.*reboot-pending/ { found = 1 } found && /exit 0/ { ok = 1; exit } END { exit !ok }' "$update" ||
  fail "a moved Mac's update stops there, and only a moved one's"
awk -v from="$move" 'NR > from && /conversion_status == 75/ { found = 1 } found && /updating this Mac as before/ { ok = 1; exit } END { exit !ok }' "$update" ||
  fail "a deferred move lets the fork update go on"
pass "omarchy update moves a marked Mac before any fork update, stops once it moved, and goes on when the move defers"
