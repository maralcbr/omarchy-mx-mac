#!/bin/bash
#
# The grub-btrfs migration installs the package on Apple Silicon Macs from
# before it joined the default set, then writes the GRUB snapshot menu once.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1790009252.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
export CALL_LOG="$tmp/calls"
export PATH="$tmp/bin:$PATH"
printf '#!/bin/bash\nexit "${APPLE:-0}"\n' >"$tmp/bin/omarchy-hw-apple-silicon"
printf '#!/bin/bash\nexec "$@"\n' >"$tmp/bin/sudo"
printf '#!/bin/bash\necho "pkg-add $*" >>"$CALL_LOG"; exit "${PKG_STATUS:-0}"\n' >"$tmp/bin/omarchy-pkg-add"
printf '#!/bin/bash\necho "menu $*" >>"$CALL_LOG"; exit "${MENU_STATUS:-0}"\n' >"$tmp/bin/omarchy-mac-snapshot-menu"
chmod +x "$tmp/bin"/*

run() { : >"$CALL_LOG"; bash -euo pipefail "$migration" >"$tmp/out" 2>&1; }

run || fail "the migration runs: $(<"$tmp/out")"
[[ $(<"$CALL_LOG") == $'pkg-add grub-btrfs\nmenu refresh' ]] || fail "grub-btrfs is installed, then the menu refreshed: $(<"$CALL_LOG")"
pass "an installed Mac gets grub-btrfs and its snapshot menu"

if PKG_STATUS=1 run; then fail "a failed install must fail the migration"; fi
[[ $(<"$CALL_LOG") == 'pkg-add grub-btrfs' ]] || fail "no menu refresh without the package"
if MENU_STATUS=1 run; then fail "a failed refresh must fail the migration"; fi
pass "the migration retries later when the package or the menu fails"

APPLE=1 run || fail "a non-Apple machine passes"
[[ ! -s $CALL_LOG ]] || fail "a non-Apple machine is untouched"
pass "the migration gates itself to Apple Silicon"
