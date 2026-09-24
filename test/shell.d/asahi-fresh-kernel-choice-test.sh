#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The fresh installer's kernel choice, run on its own: the image's marker, else
# the installed kernel by exact name, and never Aurora on an M3.
installer="$ROOT/bin/omarchy-install-asahi-fresh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

sed -n '/^kernel_marker=/,/the Apple Silicon kernel this install uses)"$/p' "$installer" >"$test_tmp/choice"
grep -q 'the Apple Silicon kernel this install uses' "$test_tmp/choice" || fail "the kernel choice block is found"
printf 'echo "kernel=$kernel_package"\n' >>"$test_tmp/choice"

mkdir -p "$test_tmp/bin"
printf '#!/bin/bash\n(( $# == 1 )) && [[ $1 == -Q ]] && sed "s/$/ 1/" "$TEST_INSTALLED"\n' >"$test_tmp/bin/pacman"
chmod +x "$test_tmp/bin/pacman"

choose() {
  local compatible=$1 installed=$2 marker=${3:-}
  printf '%s\n' $installed >"$test_tmp/installed"
  printf '%s\0apple,arm-platform\0' "$compatible" >"$test_tmp/compatible"
  rm -f "$test_tmp/marker"
  [[ -z $marker ]] || printf '%s\n' "$marker" >"$test_tmp/marker"
  TEST_INSTALLED="$test_tmp/installed" OMARCHY_APPLE_KERNEL_FILE="$test_tmp/marker" \
    OMARCHY_DEVICE_TREE_COMPATIBLE="$test_tmp/compatible" PATH="$test_tmp/bin:$PATH" \
    bash -euo pipefail -c 'fail() { echo "Error: $*" >&2; exit 1; }; source "$1"' _ "$test_tmp/choice" 2>"$test_tmp/err"
}

[[ $(choose apple,t6000 'linux-aurora m1n1-aurora' linux-aurora) == kernel=linux-aurora ]] || fail "the image's marker names the kernel"
[[ $(choose apple,t6000 'linux-aurora m1n1-aurora') == kernel=linux-aurora ]] || fail "an Aurora-only system keeps Aurora"
[[ $(choose apple,t6000 'linux-asahi m1n1') == kernel=linux-asahi ]] || fail "Asahi's own image keeps linux-asahi"
[[ $(choose apple,t8122 'linux-asahi linux-asahi-headers m1n1') == kernel=linux-asahi ]] ||
  fail "an M3 on Asahi Arch Minimal installs with linux-asahi" "$(cat "$test_tmp/err")"
pass "the kernel is the image's, else the one installed"

# linux-aurora provides linux-asahi; a listing of exact names is the evidence.
! choose apple,t6000 'linux-asahi-headers m1n1' >/dev/null || fail "a headers package is not a kernel"
grep -Fq 'Required Asahi package is not installed: linux-asahi' "$test_tmp/err" || fail "a missing kernel is named" "$(cat "$test_tmp/err")"
! choose apple,t6031 'linux-aurora m1n1-aurora' >/dev/null || fail "an M3 never boots Aurora"
! choose apple,t8122 'linux-asahi m1n1' linux-aurora >/dev/null || fail "an M3 refuses a marker naming Aurora"
grep -Fq 'This M3 Mac cannot boot linux-aurora' "$test_tmp/err" || fail "the M3 refusal is explained" "$(cat "$test_tmp/err")"
pass "a kernel that is not installed, or Aurora on an M3, fails before any change"
