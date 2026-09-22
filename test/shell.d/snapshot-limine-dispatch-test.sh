#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

snapshot="$ROOT/bin/omarchy-snapshot"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
calls="$test_tmp/calls"
mkdir -p "$fake_bin"

printf '#!/bin/bash\nexec "$@"\n' >"$fake_bin/sudo"
printf '#!/bin/bash\nexit 1\n' >"$fake_bin/omarchy-cmd-missing"
printf '#!/bin/bash\necho 4.0.4\n' >"$fake_bin/omarchy-version"
printf '#!/bin/bash\nexit 0\n' >"$fake_bin/omarchy-hw-apple-silicon"
cat >"$fake_bin/omarchy-mac-limine-active" <<'SH'
#!/bin/bash
[[ -e $TEST_LIMINE ]]
SH
cat >"$fake_bin/snapper" <<'SH'
#!/bin/bash
echo "snapper $*" >>"$TEST_CALLS"
[[ "$*" == *list-configs* ]] && printf 'config,subvolume\nroot,/\n'
exit 0
SH
for name in omarchy-mac-snapshot-menu omarchy-mac-snapshot-restore limine-snapper-restore; do
  printf '#!/bin/bash\necho "%s $*" >>"$TEST_CALLS"\n' "$name" >"$fake_bin/$name"
done
chmod +x "$fake_bin"/*

run() {
  TEST_CALLS="$calls" TEST_LIMINE="$test_tmp/limine" PATH="$fake_bin:$PATH" bash "$snapshot" "$@"
}

# A GRUB Mac.
: >"$calls"
run create >/dev/null || fail "create succeeds on a GRUB Mac"
grep -q '^omarchy-mac-snapshot-menu refresh$' "$calls" || fail "a GRUB Mac refreshes the grub-btrfs menu" "$(cat "$calls")"
: >"$calls"
run restore 7 >/dev/null || fail "restore succeeds on a GRUB Mac"
grep -q '^omarchy-mac-snapshot-restore 7$' "$calls" || fail "a GRUB Mac restores with the Mac tool" "$(cat "$calls")"
pass "a GRUB Mac keeps the GRUB snapshot tools"

# A Limine Mac: the x86 tooling.
: >"$test_tmp/limine"
: >"$calls"
run create >/dev/null || fail "create succeeds on a Limine Mac"
grep -q '^snapper -c root create ' "$calls" || fail "the snapshot is created"
! grep -q 'omarchy-mac-snapshot-menu' "$calls" || fail "a Limine Mac does not refresh the grub-btrfs menu (the snapper plugin syncs Limine)" "$(cat "$calls")"
: >"$calls"
run restore >/dev/null || fail "restore succeeds on a Limine Mac"
[[ $(cat "$calls") == "limine-snapper-restore " ]] || fail "a Limine Mac restores with limine-snapper-restore" "$(cat "$calls")"
set +e
run restore 7 >/dev/null 2>&1
status=$?
run prune-previous >/dev/null 2>&1
prune=$?
set -e
(( status == 64 )) || fail "a snapshot number is refused on a Limine Mac (limine-snapper-restore picks it)"
(( prune != 0 )) || fail "prune-previous does not apply to a Limine restore"
pass "a Limine Mac uses the x86 snapshot tooling"
