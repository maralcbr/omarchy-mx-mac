#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1789879296.sh"
grep -Eq "^[[:space:]]*1789879296\.sh\) printf 'run" "$ROOT/bin/omarchy-migrate" ||
  fail "the Aurora leftover headers migration is reviewed to run on Apple Silicon"
! grep -Eq '^[[:space:]]*pacman -Q linux-asahi([[:space:]]|$)' "$migration" ||
  fail "the migration never queries linux-asahi by provides"
pass "Aurora leftover headers migration is reviewed and avoids linux-asahi provides"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
installed="$tmp/installed"
calls="$tmp/calls"
pending="$tmp/pending"
script="$tmp/update-m1n1"
config="$tmp/m1n1-default"
status_file="$tmp/channel-status"

export PATH="$tmp/bin:$ROOT/bin:$PATH"
export INSTALLED_PACKAGES="$installed" TEST_CALLS="$calls"
export OMARCHY_AURORA_ASAHI_HEADERS_PENDING="$pending"
export OMARCHY_UPDATE_M1N1_SCRIPT="$script"
export OMARCHY_UPDATE_M1N1_CONFIG="$config"
export TEST_CHANNEL_STATUS="$status_file" TEST_CHANNEL_EXIT=0
export TEST_BOOT_STATUS=0 TEST_INSTALL_FAIL=0 TEST_REMOVE_FAIL=0 TEST_M1N1_FAIL=0

cat >"$tmp/bin/omarchy-apple-silicon-channel" <<'SH'
#!/bin/bash
[[ $1 == status ]] || exit 2
cat "$TEST_CHANNEL_STATUS"
exit "${TEST_CHANNEL_EXIT:-0}"
SH
cat >"$tmp/bin/pacman" <<'SH'
#!/bin/bash
case "$1" in
  -Qq) cat "$INSTALLED_PACKAGES" ;;
  -Q)
    echo "pacman -Q must not be used for package presence" >&2
    exit 2
    ;;
  -Rdd)
    printf 'pacman %s\n' "$*" >>"$TEST_CALLS"
    [[ ${TEST_REMOVE_FAIL:-0} == 0 ]] || exit 1
    shift
    [[ $1 == --noconfirm ]] && shift
    for pkg in "$@"; do
      grep -Fxv -- "$pkg" "$INSTALLED_PACKAGES" >"$INSTALLED_PACKAGES.tmp"
      mv "$INSTALLED_PACKAGES.tmp" "$INSTALLED_PACKAGES"
    done
    ;;
  -S)
    printf 'pacman %s\n' "$*" >>"$TEST_CALLS"
    [[ ${TEST_INSTALL_FAIL:-0} == 0 ]] || exit 1
    shift
    while (($#)); do
      case "$1" in
        --noconfirm | --needed) shift ;;
        */*) printf '%s\n' "${1#*/}" >>"$INSTALLED_PACKAGES"; shift ;;
        *) printf '%s\n' "$1" >>"$INSTALLED_PACKAGES"; shift ;;
      esac
    done
    ;;
  *) exit 1 ;;
esac
SH
cat >"$tmp/bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$TEST_CALLS"
exec "$@"
SH
cat >"$tmp/bin/update-m1n1" <<'SH'
#!/bin/bash
printf 'update-m1n1\n' >>"$TEST_CALLS"
[[ ${TEST_M1N1_FAIL:-0} == 0 ]]
SH
cat >"$tmp/bin/omarchy-apple-silicon-boot-check" <<'SH'
#!/bin/bash
printf 'boot-check %s\n' "$*" >>"$TEST_CALLS"
[[ ${TEST_BOOT_STATUS:-0} == 0 ]]
SH
cat >"$tmp/bin/install" <<'SH'
#!/bin/bash
exec /usr/bin/install "$@"
SH
chmod +x "$tmp/bin/"*

printf ': ${DTBS:=$(/bin/ls -d /lib/modules/*-ARCH | sort -rV | head -1)/dtbs/*.dtb}\n' >"$script"
printf 'format=1\nchannel=rc\nkernel=linux-aurora\n' >"$status_file"

run() {
  : >"$calls"
  bash -euo pipefail "$migration" >/dev/null
}

reset_packages() {
  printf '%s\n' "$@" >"$installed"
  rm -f "$pending" "$config"
}

reset_packages linux-aurora linux-asahi-headers m1n1-aurora
run
grep -Fxq linux-aurora-headers "$installed" || fail "Aurora headers are installed from omarchy-aurora"
! grep -Fxq linux-asahi-headers "$installed" || fail "Asahi headers are removed"
grep -Fq 'pacman -Rdd --noconfirm linux-asahi-headers' "$calls" || fail "Asahi headers are removed with -Rdd" "$(<"$calls")"
grep -Fq 'pacman -S --noconfirm --needed omarchy-aurora/linux-aurora-headers' "$calls" ||
  fail "Aurora headers are taken from [omarchy-aurora]" "$(<"$calls")"
grep -qx update-m1n1 "$calls" || fail "m1n1 is rebuilt from the default DTBS" "$(<"$calls")"
grep -qx 'boot-check linux-aurora' "$calls" || fail "boot check runs after the swap" "$(<"$calls")"
[[ ! -e $pending ]] || fail "the pending marker is cleared after a verified swap"
! grep -q 'pacman -Q ' "$calls" || fail "exact names are listed with pacman -Qq" "$(<"$calls")"
pass "Aurora Mac with leftover Asahi headers is swapped, rebuilt and checked"

: >"$calls"
run
[[ ! -s $calls ]] || fail "a clean Aurora Mac is a no-op after the swap" "$(<"$calls")"
pass "Aurora Mac without leftover Asahi headers is a no-op"

reset_packages linux-aurora linux-asahi-headers m1n1-aurora
printf 'format=1\nchannel=stable\nkernel=linux-asahi\n' >"$status_file"
cp "$installed" "$tmp/before"
run
[[ ! -s $calls ]] || fail "a stable Mac is not touched" "$(<"$calls")"
cmp -s "$installed" "$tmp/before" || fail "a stable Mac's packages are unchanged"
pass "stable Asahi Mac is untouched"

printf 'format=1\nchannel=rc\nkernel=linux-aurora\n' >"$status_file"
reset_packages linux-aurora linux-asahi-headers m1n1-aurora
if TEST_BOOT_STATUS=1 run 2>/dev/null; then
  fail "a failed boot check must leave the migration pending"
fi
grep -Fxq linux-aurora-headers "$installed" || fail "headers stay swapped when the check fails"
! grep -Fxq linux-asahi-headers "$installed" || fail "Asahi headers stay removed when the check fails"
grep -qx update-m1n1 "$calls" || fail "m1n1 still rebuilt when the check fails"
grep -qx 'boot-check linux-aurora' "$calls" || fail "boot check ran"
[[ -f $pending ]] || fail "the pending marker remains after a failed check"
pass "a failed boot check keeps the leftover headers migration pending"
