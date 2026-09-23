#!/bin/bash
#
# The audio UCM migration installs alsa-ucm-conf-asahi on Apple Silicon Macs
# whose image lacked it, then restarts the user's audio services.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1790197726.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
export CALL_LOG="$tmp/calls"
export PATH="$tmp/bin:$PATH"
printf '#!/bin/bash\nexit "${APPLE:-0}"\n' >"$tmp/bin/omarchy-hw-apple-silicon"
printf '#!/bin/bash\nexit "${INSTALLED:-1}"\n' >"$tmp/bin/pacman"
printf '#!/bin/bash\necho "pkg-add $*" >>"$CALL_LOG"; exit "${PKG_STATUS:-0}"\n' >"$tmp/bin/omarchy-pkg-add"
printf '#!/bin/bash\necho "systemctl $*" >>"$CALL_LOG"; exit "${SYSTEMCTL_STATUS:-0}"\n' >"$tmp/bin/systemctl"
chmod +x "$tmp/bin"/*

run() { : >"$CALL_LOG"; bash -euo pipefail "$migration" >"$tmp/out" 2>&1; }

grep -Fxq alsa-ucm-conf-asahi "$ROOT/install/omarchy-base-asahi.packages" ||
  fail "fresh Apple Silicon installs list alsa-ucm-conf-asahi"
pass "the Apple Silicon base package set carries the audio UCM"

run || fail "the migration runs: $(<"$tmp/out")"
[[ $(<"$CALL_LOG") == $'pkg-add alsa-ucm-conf-asahi\nsystemctl --user try-restart wireplumber pipewire pipewire-pulse' ]] ||
  fail "the package is installed, then audio restarted: $(<"$CALL_LOG")"
pass "a Mac without the UCM gets it and its audio restarted"

INSTALLED=0 run || fail "an up-to-date Mac passes"
[[ ! -s $CALL_LOG ]] || fail "an up-to-date Mac is untouched: $(<"$CALL_LOG")"
pass "a Mac that has the UCM is untouched"

if PKG_STATUS=1 run; then fail "a failed install must fail the migration"; fi
[[ $(<"$CALL_LOG") == 'pkg-add alsa-ucm-conf-asahi' ]] || fail "no restart without the package"
SYSTEMCTL_STATUS=1 run || fail "a Mac without a user session still passes"
pass "the migration retries a failed install and tolerates a missing session"

APPLE=1 run || fail "a non-Apple machine passes"
[[ ! -s $CALL_LOG ]] || fail "a non-Apple machine is untouched"
pass "the migration gates itself to Apple Silicon"
