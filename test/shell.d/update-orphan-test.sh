#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$stub_bin" "$test_home"

write_stub() {
  local name="$1"
  local body="$2"

  cat >"$stub_bin/$name" <<SH
#!/bin/bash
$body
SH
  chmod +x "$stub_bin/$name"
}

run_orphan_checker() {
  HOME="$test_home" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-update-orphan-pkgs"
}

write_stub pacman 'if [[ $1 == "-Qtdq" ]]; then printf "old-lib\nunused-tool\n"; exit 0; fi; exit 1'
write_stub sudo 'echo "sudo should not be called" >&2; exit 99'
write_stub gum 'echo "gum should not be called" >&2; exit 99'

run_orphan_checker >"$test_tmp/noninteractive.out" 2>"$test_tmp/noninteractive.err"
grep -q '^  old-lib$' "$test_tmp/noninteractive.out" || fail "orphan checker lists orphan packages"
grep -q 'Re-run omarchy-update-orphan-pkgs in a terminal' "$test_tmp/noninteractive.out" || fail "orphan checker does not remove packages non-interactively"
pass "orphan checker only reports orphans non-interactively"

write_stub pacman 'if [[ $1 == "-Qtdq" ]]; then exit 0; fi; exit 1'
run_orphan_checker >"$test_tmp/none.out" 2>"$test_tmp/none.err"
[[ ! -s $test_tmp/none.out ]] || fail "orphan checker stays quiet when no orphans exist"
pass "orphan checker stays quiet without orphans"

# omarchy update runs under script(1), so -t answers true with nobody at the terminal; -y must still keep gum away.
write_stub pacman 'if [[ $1 == "-Qtdq" ]]; then printf "old-lib\n"; exit 0; fi; exit 1'
write_stub gum 'echo called >>"$GUM_LOG"; exit 1'
run_orphan_checker_on_tty() {
  : >"$test_tmp/gum-log"
  GUM_LOG="$test_tmp/gum-log" HOME="$test_home" PATH="$stub_bin:$PATH" \
    script -qec "'$ROOT/bin/omarchy-update-orphan-pkgs'" /dev/null >"$test_tmp/tty.out" 2>&1
}

OMARCHY_UPDATE_UNATTENDED=1 run_orphan_checker_on_tty
[[ ! -s $test_tmp/gum-log ]] || fail "an unattended update asks about orphans on a terminal nobody watches"
grep -q 'Re-run omarchy-update-orphan-pkgs in a terminal' "$test_tmp/tty.out" ||
  fail "an unattended update does not report the orphans" "$(cat "$test_tmp/tty.out")"
pass "an unattended update reports orphans without prompting, even on a terminal"

OMARCHY_UPDATE_UNATTENDED= run_orphan_checker_on_tty
[[ -s $test_tmp/gum-log ]] || fail "a person at a terminal is no longer asked about orphans" "$(cat "$test_tmp/tty.out")"
grep -q 'Keeping orphaned packages' "$test_tmp/tty.out" || fail "declining the orphan prompt does not keep the packages"
pass "a person at a terminal is still asked about orphans"
