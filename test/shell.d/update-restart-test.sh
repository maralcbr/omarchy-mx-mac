#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$stub_bin" "$test_home"

write_stub() {
  cat >"$stub_bin/$1" <<SH
#!/bin/bash
$2
SH
  chmod +x "$stub_bin/$1"
}

# pacman owning no kernel makes the kernel look updated wherever the test runs.
write_stub pacman 'exit 1'
write_stub pgrep 'exit 1'
write_stub gum 'echo "gum $*" >>"$RESTART_LOG"; exit "${GUM_STATUS:-1}"'
write_stub omarchy-system-reboot 'echo reboot >>"$RESTART_LOG"'
write_stub omarchy-restart-shell 'echo restart-shell >>"$RESTART_LOG"'

run_restart() {
  : >"$test_tmp/log"
  RESTART_LOG="$test_tmp/log" HOME="$test_home" PATH="$stub_bin:$PATH" \
    "$ROOT/bin/omarchy-update-restart" >"$test_tmp/out" 2>&1
}

OMARCHY_UPDATE_UNATTENDED=1 run_restart || fail "an unattended restart check fails"
! grep -q '^gum ' "$test_tmp/log" || fail "an unattended update asks to reboot" "$(cat "$test_tmp/log")"
! grep -qx reboot "$test_tmp/log" || fail "an unattended update reboots"
grep -q 'The Linux kernel has been updated. Reboot when you are ready.' "$test_tmp/out" ||
  fail "an unattended update does not say a reboot is needed" "$(cat "$test_tmp/out")"
grep -qx restart-shell "$test_tmp/log" || fail "an unattended update no longer restarts the shell"
pass "an unattended update reports a needed reboot without asking or rebooting"

OMARCHY_UPDATE_UNATTENDED= run_restart || fail "a declined reboot fails the restart check"
grep -q '^gum confirm Linux kernel has been updated. Reboot?$' "$test_tmp/log" ||
  fail "a person is no longer asked to reboot after a kernel update" "$(cat "$test_tmp/log")"
! grep -qx reboot "$test_tmp/log" || fail "a declined reboot still reboots"
pass "a person is still asked to reboot and can decline"

OMARCHY_UPDATE_UNATTENDED= GUM_STATUS=0 run_restart || fail "an accepted reboot fails the restart check"
grep -qx reboot "$test_tmp/log" || fail "an accepted reboot does not reboot"
pass "an accepted reboot reboots"
