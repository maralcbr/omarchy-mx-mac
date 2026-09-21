#!/bin/bash
#
# The GRUB console leaf renders a larger font for GRUB, points GRUB_FONT at
# it, appends the unbounded root-device wait to GRUB_CMDLINE_LINUX, and runs
# update-grub once; a Mac already configured is left alone.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/grub-console.sh"
migration="$ROOT/migrations/1790030337.sh"
grep -Fq 'hardware/apple/grub-console.sh' "$ROOT/install/hardware/all.sh" || fail "the leaf is a deferred hardware step"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fonts"
export CALL_LOG="$tmp/calls"
export PATH="$tmp/bin:$ROOT/bin:$PATH"
printf '#!/bin/bash\nexit "${APPLE:-0}"\n' >"$tmp/bin/omarchy-hw-apple-silicon"
printf '#!/bin/bash\nexec "$@"\n' >"$tmp/bin/sudo"
printf '#!/bin/bash\necho "mkfont $*" >>"$CALL_LOG"; while (( $# > 1 )); do [[ $1 == -o ]] && printf font >"$2"; shift; done\n' >"$tmp/bin/grub-mkfont"
printf '#!/bin/bash\necho update-grub >>"$CALL_LOG"\n' >"$tmp/bin/update-grub"
chmod +x "$tmp/bin"/*
: >"$tmp/source.ttf"

run_leaf() {
  : >"$CALL_LOG"
  OMARCHY_GRUB_CONSOLE_PENDING="$tmp/pending" \
  OMARCHY_GRUB_DEFAULT="$tmp/grub" OMARCHY_GRUB_FONT="$tmp/fonts/omarchy.pf2" OMARCHY_GRUB_FONT_SOURCE="$tmp/source.ttf" \
    bash -euo pipefail -c 'source "$1"' _ "$leaf" >"$tmp/out" 2>&1
}

printf 'GRUB_TIMEOUT="1"\nGRUB_CMDLINE_LINUX="zswap.enabled=0 rootfstype=btrfs"\n' >"$tmp/grub"
run_leaf || fail "the leaf runs: $(<"$tmp/out")"
grep -Fq "mkfont -s 28 -o $tmp/fonts/omarchy.pf2 $tmp/source.ttf" "$CALL_LOG" || fail "the font is rendered from Liberation Mono at 28px: $(<"$CALL_LOG")"
grep -Fxq "GRUB_FONT=\"$tmp/fonts/omarchy.pf2\"" "$tmp/grub" || fail "GRUB_FONT names the rendered font: $(<"$tmp/grub")"
grep -Fxq 'GRUB_CMDLINE_LINUX="zswap.enabled=0 rootfstype=btrfs rootflags=x-systemd.device-timeout=0"' "$tmp/grub" ||
  fail "the root-device wait is appended to GRUB_CMDLINE_LINUX: $(<"$tmp/grub")"
grep -Fxq 'GRUB_VIDEO_BACKEND="efi_gop"' "$tmp/grub" || fail "the video backend is pinned to efi_gop so GRUB stops asking for efi_uga"
[[ $(grep -c update-grub "$CALL_LOG") == 1 ]] || fail "grub.cfg is regenerated once"
pass "the leaf renders the font, sets GRUB_FONT and the root wait, and regenerates GRUB once"

run_leaf || fail "a second run passes"
[[ ! -s $CALL_LOG ]] || fail "a configured Mac renders nothing and runs no update-grub: $(<"$CALL_LOG")"
pass "the leaf is idempotent"

# A duplicate or commented assignment: one authoritative line survives with
# the effective (last) value extended.
printf '#GRUB_CMDLINE_LINUX="old"\nGRUB_CMDLINE_LINUX="first"\nGRUB_TIMEOUT="1"\nGRUB_CMDLINE_LINUX='"'"'zswap.enabled=0'"'"'\n' >"$tmp/grub"
run_leaf || fail "duplicate assignments are handled: $(<"$tmp/out")"
[[ $(grep -c "GRUB_CMDLINE_LINUX=" "$tmp/grub") == 1 ]] || fail "one GRUB_CMDLINE_LINUX line remains: $(<"$tmp/grub")"
grep -Fxq 'GRUB_CMDLINE_LINUX="zswap.enabled=0 rootflags=x-systemd.device-timeout=0"' "$tmp/grub" ||
  fail "the effective (last, single-quoted) value is the one extended: $(<"$tmp/grub")"
pass "the leaf leaves one authoritative assignment carrying the effective value"

# A failed update-grub leaves the regeneration owed: the next run retries it
# even though the defaults already read as configured.
printf '#!/bin/bash\necho update-grub >>"$CALL_LOG"; exit 1\n' >"$tmp/bin/update-grub"
printf 'GRUB_CMDLINE_LINUX="zswap.enabled=0"\n' >"$tmp/grub"
if run_leaf; then fail "a failed update-grub must fail the leaf"; fi
[[ -e $tmp/pending ]] || fail "a failed regeneration is recorded as pending"
printf '#!/bin/bash\necho update-grub >>"$CALL_LOG"\n' >"$tmp/bin/update-grub"
run_leaf || fail "the retry runs: $(<"$tmp/out")"
grep -q update-grub "$CALL_LOG" || fail "the retry regenerates GRUB although the defaults were already set"
[[ ! -e $tmp/pending ]] || fail "a successful regeneration clears the pending marker"
pass "a failed regeneration is retried on the next run"

printf 'GRUB_CMDLINE_LINUX="zswap.enabled=0"\n' >"$tmp/grub"
APPLE=1 run_leaf || fail "a non-Apple machine passes"
[[ ! -s $CALL_LOG ]] && grep -Fxq 'GRUB_CMDLINE_LINUX="zswap.enabled=0"' "$tmp/grub" || fail "a non-Apple machine is untouched"
pass "the leaf gates itself to Apple Silicon"

# The migration sources the leaf.
grep -Fq 'hardware/apple/grub-console.sh' "$migration" || fail "the migration runs the leaf"
pass "installed Macs get the same through the migration"
