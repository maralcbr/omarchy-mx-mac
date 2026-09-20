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
kernel_version=7.1.12-2.5-1

export PATH="$tmp/bin:$ROOT/bin:$PATH"
export INSTALLED_PACKAGES="$installed" TEST_CALLS="$calls"
export OMARCHY_AURORA_ASAHI_HEADERS_PENDING="$pending"
export OMARCHY_UPDATE_M1N1_SCRIPT="$script"
export OMARCHY_UPDATE_M1N1_CONFIG="$config"
export TEST_CHANNEL_STATUS="$status_file" TEST_CHANNEL_EXIT=0
export TEST_BOOT_STATUS=0 TEST_INSTALL_FAIL=0 TEST_REMOVE_FAIL=0 TEST_M1N1_FAIL=0
export TEST_KERNEL_VERSION="$kernel_version" TEST_HEADERS_AVAILABLE="$kernel_version"
export TEST_HELD="" TEST_HELD_EXIT=0 TEST_SI_FAIL=0 TEST_SI_LOCALIZED=0 TEST_PACMAN_QQ_FAIL=0
export APPLE_SILICON=1

cat >"$tmp/bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
[[ ${APPLE_SILICON:-1} == 1 ]]
SH
cat >"$tmp/bin/omarchy-apple-silicon-channel" <<'SH'
#!/bin/bash
case "$1" in
  status)
    [[ ${TEST_CHANNEL_EXIT:-0} == 0 ]] || exit "${TEST_CHANNEL_EXIT}"
    cat "$TEST_CHANNEL_STATUS"
    ;;
  held)
    printf '%s\n' "${TEST_HELD:-}"
    exit "${TEST_HELD_EXIT:-0}"
    ;;
  *) exit 2 ;;
esac
SH
cat >"$tmp/bin/pacman" <<'SH'
#!/bin/bash
case "$1" in
  -Qq)
    [[ ${TEST_PACMAN_QQ_FAIL:-0} == 0 ]] || exit 1
    if (($# >= 2)); then
      shift
      for pkg in "$@"; do
        grep -Fxq "$pkg" "$INSTALLED_PACKAGES" || exit 1
        printf '%s\n' "$pkg"
      done
    else
      cat "$INSTALLED_PACKAGES"
    fi
    ;;
  -Q)
    if [[ $# == 2 && $2 == linux-aurora ]]; then
      echo "linux-aurora $TEST_KERNEL_VERSION"
      exit 0
    fi
    echo "pacman -Q must not be used for package presence" >&2
    exit 2
    ;;
  -Si)
    [[ ${TEST_SI_FAIL:-0} == 0 ]] || exit 1
    [[ $2 == omarchy-aurora/linux-aurora-headers ]] || exit 1
    if [[ ${TEST_SI_LOCALIZED:-0} == 1 && ${LC_ALL:-} != C ]]; then
      printf 'Repositorio     : omarchy-aurora\nNombre          : linux-aurora-headers\nVersión         : %s\n' "$TEST_HEADERS_AVAILABLE"
    else
      printf 'Repository      : omarchy-aurora\nName            : linux-aurora-headers\nVersion         : %s\n' "$TEST_HEADERS_AVAILABLE"
    fi
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
        */*)
          spec=${1#*/}
          printf '%s\n' "${spec%%=*}" >>"$INSTALLED_PACKAGES"
          shift
          ;;
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

run_fail() {
  local description=$1
  : >"$calls"
  set +e
  bash -euo pipefail "$migration" >"$tmp/out" 2>"$tmp/err"
  status=$?
  set -e
  (( status != 0 )) || fail "$description must leave the migration pending"
}

reset_flags() {
  TEST_BOOT_STATUS=0 TEST_INSTALL_FAIL=0 TEST_REMOVE_FAIL=0 TEST_M1N1_FAIL=0
  TEST_CHANNEL_EXIT=0 TEST_HELD="" TEST_HELD_EXIT=0 TEST_SI_FAIL=0 TEST_SI_LOCALIZED=0
  TEST_PACMAN_QQ_FAIL=0
  TEST_KERNEL_VERSION=$kernel_version TEST_HEADERS_AVAILABLE=$kernel_version
  APPLE_SILICON=1
  export TEST_BOOT_STATUS TEST_INSTALL_FAIL TEST_REMOVE_FAIL TEST_M1N1_FAIL
  export TEST_CHANNEL_EXIT TEST_HELD TEST_HELD_EXIT TEST_SI_FAIL TEST_SI_LOCALIZED
  export TEST_PACMAN_QQ_FAIL TEST_KERNEL_VERSION TEST_HEADERS_AVAILABLE APPLE_SILICON
}

reset_packages() {
  reset_flags
  printf '%s\n' "$@" >"$installed"
  rm -f "$pending" "$config"
  printf 'format=1\nchannel=rc\nkernel=linux-aurora\n' >"$status_file"
}

reset_packages linux-aurora linux-asahi-headers m1n1-aurora
run
grep -Fxq linux-aurora-headers "$installed" || fail "Aurora headers are installed from omarchy-aurora"
! grep -Fxq linux-asahi-headers "$installed" || fail "Asahi headers are removed"
grep -Fq 'pacman -Rdd --noconfirm linux-asahi-headers' "$calls" || fail "Asahi headers are removed with -Rdd" "$(<"$calls")"
grep -Fq "pacman -S --noconfirm --needed omarchy-aurora/linux-aurora-headers=$kernel_version" "$calls" ||
  fail "Aurora headers are taken from [omarchy-aurora] at linux-aurora's version" "$(<"$calls")"
grep -qx update-m1n1 "$calls" || fail "m1n1 is rebuilt from the default DTBS" "$(<"$calls")"
grep -qx 'boot-check linux-aurora' "$calls" || fail "boot check runs after the swap" "$(<"$calls")"
[[ ! -e $pending ]] || fail "the pending marker is cleared after a verified swap"
! grep -q 'pacman -Q linux-asahi' "$calls" || fail "exact names are listed with pacman -Qq" "$(<"$calls")"
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

reset_packages linux-aurora linux-asahi-headers m1n1-aurora
APPLE_SILICON=0
export APPLE_SILICON
TEST_CHANNEL_EXIT=2
export TEST_CHANNEL_EXIT
cp "$installed" "$tmp/before"
run
[[ ! -s $calls ]] || fail "a non-Apple machine is not touched" "$(<"$calls")"
cmp -s "$installed" "$tmp/before" || fail "a non-Apple machine's packages are unchanged"
[[ ! -e $pending ]] || fail "a non-Apple machine does not record a pending swap"
pass "non-Apple Silicon is a no-op"

reset_packages linux-aurora linux-asahi-headers m1n1-aurora
TEST_CHANNEL_EXIT=3
export TEST_CHANNEL_EXIT
run
grep -Fxq linux-aurora-headers "$installed" || fail "a missing record still installs Aurora headers"
! grep -Fxq linux-asahi-headers "$installed" || fail "a missing record still removes Asahi headers"
grep -Fq "pacman -S --noconfirm --needed omarchy-aurora/linux-aurora-headers=$kernel_version" "$calls" ||
  fail "a missing record still pins linux-aurora's version" "$(<"$calls")"
grep -qx 'boot-check linux-aurora' "$calls" || fail "a missing record still checks boot"
[[ ! -e $pending ]] || fail "a missing record still settles after a verified swap"
pass "an Apple Silicon Mac without a channel record still repairs leftover Asahi headers"

reset_packages linux-aurora linux-aurora-headers m1n1-aurora
TEST_CHANNEL_EXIT=3
export TEST_CHANNEL_EXIT
: >"$pending"
cp "$installed" "$tmp/before"
run_fail "a missing record with a pending leftover headers repair"
grep -Fq 'the Apple Silicon channel record is missing' "$tmp/err" ||
  fail "a pending missing-record repair says why it stays pending" "$(<"$tmp/err")"
cmp -s "$installed" "$tmp/before" || fail "a pending missing-record repair does not touch packages"
[[ -f $pending ]] || fail "a pending missing-record repair stays pending"
[[ ! -s $calls ]] || fail "a pending missing-record repair does not retry the swap" "$(<"$calls")"
pass "an Apple Silicon Mac without a channel record keeps an unfinished leftover headers repair pending"

reset_packages linux-asahi linux-asahi-headers
TEST_CHANNEL_EXIT=3
export TEST_CHANNEL_EXIT
cp "$installed" "$tmp/before"
run
[[ ! -s $calls ]] || fail "a pure Asahi Mac without a record is not touched" "$(<"$calls")"
cmp -s "$installed" "$tmp/before" || fail "a pure Asahi Mac without a record is unchanged"
[[ ! -e $pending ]] || fail "a pure Asahi Mac without a record does not record a pending swap"
pass "an Apple Silicon Mac without a channel record settles when it is pure Asahi"

reset_packages linux-aurora linux-asahi-headers m1n1-aurora
TEST_BOOT_STATUS=1
export TEST_BOOT_STATUS
run_fail "a failed boot check"
grep -Fxq linux-aurora-headers "$installed" || fail "headers stay swapped when the check fails"
! grep -Fxq linux-asahi-headers "$installed" || fail "Asahi headers stay removed when the check fails"
grep -qx update-m1n1 "$calls" || fail "m1n1 still rebuilt when the check fails"
grep -qx 'boot-check linux-aurora' "$calls" || fail "boot check ran"
[[ -f $pending ]] || fail "the pending marker remains after a failed check"
pass "a failed boot check keeps the leftover headers migration pending"

TEST_BOOT_STATUS=0
export TEST_BOOT_STATUS
run
[[ ! -e $pending ]] || fail "a retry after a failed check clears the pending marker"
grep -qx 'boot-check linux-aurora' "$calls" || fail "the retry rechecks boot"
pass "a successful retry after a failed first attempt settles the migration"

reset_packages linux-aurora linux-asahi-headers m1n1-aurora
TEST_CHANNEL_EXIT=3
export TEST_CHANNEL_EXIT
TEST_PACMAN_QQ_FAIL=1
export TEST_PACMAN_QQ_FAIL
cp "$installed" "$tmp/before"
run_fail "a failed package inventory"
grep -Fq 'cannot list installed packages' "$tmp/err" ||
  fail "a failed package inventory says why it stays pending" "$(<"$tmp/err")"
cmp -s "$installed" "$tmp/before" || fail "a failed package inventory does not touch packages"
[[ ! -e $pending ]] || fail "a failed package inventory does not record a pending swap"
[[ ! -s $calls ]] || fail "a failed package inventory does not mutate" "$(<"$calls")"
pass "a failed package inventory leaves the leftover headers migration pending"

reset_packages linux-aurora linux-asahi-headers m1n1-aurora
TEST_CHANNEL_EXIT=2
export TEST_CHANNEL_EXIT
cp "$installed" "$tmp/before"
run_fail "a failed channel read"
grep -Fq 'channel record could not be read' "$tmp/err" ||
  fail "a failed channel read says why it stays pending" "$(<"$tmp/err")"
cmp -s "$installed" "$tmp/before" || fail "a failed channel read does not touch packages"
[[ ! -e $pending ]] || fail "a failed channel read does not record a machine-wide pending swap"
pass "a failed channel read leaves the leftover headers migration pending"

reset_packages linux-aurora linux-asahi-headers m1n1-aurora
TEST_INSTALL_FAIL=1
export TEST_INSTALL_FAIL
run_fail "a failed headers install"
grep -Fq "Could not install linux-aurora-headers $kernel_version" "$tmp/err" ||
  fail "a failed install says it will retry" "$(<"$tmp/err")"
! grep -Fxq linux-asahi-headers "$installed" || fail "Asahi headers are already gone when install fails"
! grep -Fxq linux-aurora-headers "$installed" || fail "Aurora headers are not recorded when install fails"
[[ -f $pending ]] || fail "the pending marker remains after a failed install"
pass "a failed package install leaves the leftover headers migration pending"

TEST_INSTALL_FAIL=0
export TEST_INSTALL_FAIL
run
grep -Fxq linux-aurora-headers "$installed" || fail "the retry installs Aurora headers"
[[ ! -e $pending ]] || fail "the retry after a failed install settles"
pass "a successful retry after a failed install settles the migration"

reset_packages linux-aurora linux-asahi-headers m1n1-aurora
TEST_M1N1_FAIL=1
export TEST_M1N1_FAIL
run_fail "a failed m1n1 rebuild"
grep -Fq 'update-m1n1 failed after replacing linux-asahi-headers' "$tmp/err" ||
  fail "a failed m1n1 rebuild names the manual step" "$(<"$tmp/err")"
grep -Fxq linux-aurora-headers "$installed" || fail "headers stay swapped when m1n1 fails"
[[ -f $pending ]] || fail "the pending marker remains after a failed m1n1 rebuild"
pass "a failed m1n1 rebuild leaves the leftover headers migration pending"

TEST_M1N1_FAIL=0
export TEST_M1N1_FAIL
run
[[ ! -e $pending ]] || fail "the retry after a failed m1n1 rebuild settles"
pass "a successful retry after a failed m1n1 rebuild settles the migration"

reset_packages linux-aurora linux-asahi-headers m1n1-aurora
printf 'DTBS="/lib/modules/%s/dtbs/*.dtb"\n' "$kernel_version-ARCH" >"$config"
cp "$installed" "$tmp/before"
run
grep -Fxq linux-aurora-headers "$installed" || fail "custom DTBS still replaces leftover Asahi headers"
! grep -Fxq linux-asahi-headers "$installed" || fail "custom DTBS still removes Asahi headers"
! grep -qx update-m1n1 "$calls" || fail "custom DTBS does not rebuild m1n1" "$(<"$calls")"
grep -qx 'boot-check linux-aurora' "$calls" || fail "custom DTBS still checks boot"
[[ ! -e $pending ]] || fail "custom DTBS still settles after a verified swap"
pass "a custom DTBS still swaps headers and does not rebuild m1n1"

reset_packages linux-aurora linux-asahi-headers m1n1-aurora
TEST_HELD=linux-aurora
export TEST_HELD
cp "$installed" "$tmp/before"
run_fail "a held linux-aurora"
grep -Fq 'IgnorePkg/IgnoreGroup holds linux-aurora' "$tmp/err" ||
  fail "a held kernel names the hold" "$(<"$tmp/err")"
cmp -s "$installed" "$tmp/before" || fail "a held kernel does not swap headers"
[[ ! -e $pending ]] || fail "a held kernel does not start the swap"
pass "a held kernel leaves the leftover headers migration pending"

reset_packages linux-aurora linux-asahi-headers m1n1-aurora
TEST_HEADERS_AVAILABLE=7.1.13-3-2
export TEST_HEADERS_AVAILABLE
cp "$installed" "$tmp/before"
run_fail "headers that do not match the installed kernel"
grep -Fq "linux-aurora-headers $kernel_version is not available from [omarchy-aurora] (has 7.1.13-3-2)" "$tmp/err" ||
  fail "a version mismatch names the missing headers" "$(<"$tmp/err")"
cmp -s "$installed" "$tmp/before" || fail "mismatched headers are not installed and Asahi headers stay"
[[ ! -e $pending ]] || fail "a version mismatch does not start the swap"
pass "headers that do not match the installed linux-aurora stay pending"

reset_packages linux-aurora linux-asahi-headers m1n1-aurora
TEST_SI_LOCALIZED=1
export TEST_SI_LOCALIZED
run
grep -Fxq linux-aurora-headers "$installed" || fail "localized pacman metadata still installs matching Aurora headers"
! grep -Fxq linux-asahi-headers "$installed" || fail "localized pacman metadata still removes Asahi headers"
grep -Fq "pacman -S --noconfirm --needed omarchy-aurora/linux-aurora-headers=$kernel_version" "$calls" ||
  fail "localized pacman metadata still pins linux-aurora's version" "$(<"$calls")"
[[ ! -e $pending ]] || fail "localized pacman metadata still settles after a verified swap"
pass "localized pacman metadata still finds matching headers"
