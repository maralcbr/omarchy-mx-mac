#!/bin/bash

# Building AUR packages can take many minutes. sudo's credential cache expires
# after five, and yay only needs the password once the build is done — so an
# update that built for eleven minutes died with "sudo: timed out reading
# password" and installed none of it. The AUR step must hold the credential
# open while it builds, the way omarchy-pkg-aur-install already does.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"
order_log="$test_tmp/order.log"

write_stub() {
  cat >"$stub_bin/$1" <<SH
#!/bin/bash
$2
SH
  chmod +x "$stub_bin/$1"
}

write_stub pacman 'exit 0'
write_stub omarchy-pkg-aur-accessible 'exit 0'
write_stub omarchy-hw-apple-silicon 'exit 0'
# The real helper is sourced, so the stub must be too: record that it ran and
# leave no background job behind.
write_stub omarchy-sudo-keepalive 'printf "keepalive\n" >>"$ORDER_LOG"'
write_stub yay 'printf "yay %s\n" "$*" >>"$ORDER_LOG"'

run_step() {
  ORDER_LOG="$order_log" PATH="$stub_bin:/usr/bin:/bin" \
    "$ROOT/bin/omarchy-update-aur-pkgs"
}

: >"$order_log"
run_step >/dev/null 2>&1

grep -q "^keepalive$" "$order_log" ||
  fail "the AUR update holds the sudo credential open" "$(cat "$order_log")"
[[ $(head -1 "$order_log") == "keepalive" ]] ||
  fail "the credential is held before yay starts building" "$(cat "$order_log")"
grep -q "^yay -Sua" "$order_log" ||
  fail "the AUR update still runs yay" "$(cat "$order_log")"
pass "the AUR update holds the sudo credential open before building"

# It must reuse the existing upstream helper rather than reimplementing one.
source_text=$(<"$ROOT/bin/omarchy-update-aur-pkgs")
[[ $source_text == *"source omarchy-sudo-keepalive"* ]] ||
  fail "the AUR update sources the shared omarchy-sudo-keepalive helper"
pass "the AUR update reuses the shared sudo-keepalive helper"

# Nothing should run when the AUR is unreachable — including the keepalive,
# which would otherwise prompt for a password for no reason.
write_stub omarchy-pkg-aur-accessible 'exit 1'
: >"$order_log"
run_step >/dev/null 2>&1
[[ ! -s $order_log ]] ||
  fail "an unreachable AUR runs nothing at all" "$(cat "$order_log")"
pass "an unreachable AUR neither builds nor asks for a password"
