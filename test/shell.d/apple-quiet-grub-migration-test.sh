#!/bin/bash
#
# The quiet-boot migration edits /etc/default/grub the way mac-image-finalize
# writes new images, then runs update-grub once; a Mac already quiet is left
# alone, and a non-Apple machine does nothing.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1790003445.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
export CALL_LOG="$tmp/calls"
export PATH="$tmp/bin:$PATH"
printf '#!/bin/bash\nexit "${APPLE:-0}"\n' >"$tmp/bin/omarchy-hw-apple-silicon"
printf '#!/bin/bash\nexec "$@"\n' >"$tmp/bin/sudo"
printf '#!/bin/bash\necho update-grub >>"$CALL_LOG"\n' >"$tmp/bin/update-grub"
# GRUB's own tools are what says GRUB is installed: update-grub ships with
# asahi-scripts even on a Mac that has no GRUB.
printf '#!/bin/bash\nexit 0\n' >"$tmp/bin/grub-probe"
printf '#!/bin/bash\nexit 0\n' >"$tmp/bin/grub-mkconfig"
chmod +x "$tmp/bin"/*

run() {
  : >"$CALL_LOG"
  OMARCHY_GRUB_DEFAULT="$tmp/grub" bash -euo pipefail "$migration" >"$tmp/out" 2>&1
}

printf 'GRUB_DISTRIBUTOR="Omarchy"\nGRUB_TIMEOUT="3"\nGRUB_TIMEOUT_STYLE="menu"\nGRUB_CMDLINE_LINUX="zswap.enabled=0 rootfstype=btrfs"\nGRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 splash"\n' >"$tmp/grub"
run || fail "the migration runs: $(<"$tmp/out")"
grep -Fxq 'GRUB_TIMEOUT="1"' "$tmp/grub" && grep -Fxq 'GRUB_TIMEOUT_STYLE="hidden"' "$tmp/grub" &&
  grep -Fxq 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=0 systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0"' "$tmp/grub" ||
  fail "the GRUB defaults match the finalizer: $(<"$tmp/grub")"
grep -Fxq 'GRUB_CMDLINE_LINUX="zswap.enabled=0 rootfstype=btrfs"' "$tmp/grub" || fail "GRUB_CMDLINE_LINUX is untouched"
[[ $(<"$CALL_LOG") == update-grub ]] || fail "grub.cfg is regenerated once"
pass "an installed Mac gets the finalizer's quiet GRUB defaults and one update-grub"

run || fail "a second run passes"
[[ ! -s $CALL_LOG ]] || fail "a Mac already quiet does not run update-grub again"
pass "the migration is idempotent"

printf 'GRUB_TIMEOUT="3"\n' >"$tmp/grub"
APPLE=1 run || fail "a non-Apple machine passes"
grep -Fxq 'GRUB_TIMEOUT="3"' "$tmp/grub" && [[ ! -s $CALL_LOG ]] || fail "a non-Apple machine is untouched"
pass "the migration gates itself to Apple Silicon"
