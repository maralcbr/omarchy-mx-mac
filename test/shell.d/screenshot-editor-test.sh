#!/bin/bash
#
# The screenshot notification offers its Edit action only when the editor is
# installed, and Macs set up before tensaku was built for aarch64 get it.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/editor-bin" "$tmp/home/Pictures"
export CALL_LOG="$tmp/calls"

stub() {
  printf '#!/bin/bash\n%s\n' "$2" >"$tmp/bin/$1"
  chmod +x "$tmp/bin/$1"
}

# --- The screenshot notification ---------------------------------------------
stub pkill 'exit 1'
stub hyprctl 'echo "{\"int\": 0}"'
stub omarchy-capture-region 'echo 4242; echo "0,0 10x10"'
stub grim 'for last; do :; done; [[ $last == - ]] || : >"$last"'
stub wl-copy 'cat >/dev/null'
stub omarchy-notification-send 'printf "notify" >>"$CALL_LOG"; printf " [%s]" "$@" >>"$CALL_LOG"; echo >>"$CALL_LOG"'
printf '#!/bin/bash\nexit 0\n' >"$tmp/editor-bin/tensaku-edit"
chmod +x "$tmp/editor-bin/tensaku-edit"

screenshot() {
  local path=$1
  shift
  : >"$CALL_LOG"
  env HOME="$tmp/home" OMARCHY_SCREENSHOT_DIR="$tmp/home/Pictures" PATH="$path" \
    bash "$ROOT/bin/omarchy-capture-screenshot" "$@" >"$tmp/out" 2>&1 ||
    fail "the screenshot is taken" "$(cat "$tmp/out")"
  notification=$(<"$CALL_LOG")
}

base_path="$tmp/bin:$ROOT/bin:/usr/bin:/bin"

screenshot "$tmp/editor-bin:$base_path" region
[[ $notification == *"[Edit with Super + Alt + , (or click this)]"* && $notification == *"[--exec] [tensaku-edit] [$tmp/home/Pictures/screenshot-"*".png]"* ]] ||
  fail "an installed editor is offered as the click action" "$notification"
pass "with Tensaku installed the notification opens it"

screenshot "$base_path" region
[[ $notification == "notify [Screenshot saved to clipboard and file] [--image] [$tmp/home/Pictures/screenshot-"*".png]" ]] ||
  fail "a missing editor is not offered" "$notification"
pass "without Tensaku the notification offers no Edit action"

screenshot "$base_path" region --editor=missing-editor
[[ $notification != *"--exec"* && $notification != *"Edit with"* ]] ||
  fail "a missing --editor is not offered" "$notification"
screenshot "$tmp/editor-bin:$base_path" region --editor=tensaku-edit
[[ $notification == *"[--exec] [tensaku-edit]"* ]] || fail "an installed --editor is offered" "$notification"
pass "the --editor choice is checked the same way"

# --- The Tensaku migration -----------------------------------------------------
migration="$ROOT/migrations/1790226271.sh"
rm -f "$tmp/bin"/*
stub omarchy-hw-apple-silicon 'exit "${APPLE:-0}"'
stub omarchy-pkg-present 'echo "present $*" >>"$CALL_LOG"; exit "${PRESENT:-1}"'
stub omarchy-pkg-available 'echo "available $*" >>"$CALL_LOG"; exit "${AVAILABLE:-0}"'
stub omarchy-pkg-add 'echo "pkg-add $*" >>"$CALL_LOG"; exit "${ADD_STATUS:-0}"'

migrate() { : >"$CALL_LOG"; PATH="$tmp/bin:$PATH" bash -euo pipefail "$migration" >"$tmp/out" 2>&1; }

migrate || fail "the migration runs" "$(<"$tmp/out")"
[[ $(<"$CALL_LOG") == $'present tensaku\navailable tensaku\npkg-add tensaku' ]] ||
  fail "a Mac without Tensaku gets it" "$(<"$CALL_LOG")"
pass "a Mac without Tensaku installs it"

PRESENT=0 migrate || fail "a Mac with Tensaku passes"
! grep -q pkg-add "$CALL_LOG" || fail "a Mac with Tensaku installs nothing"
AVAILABLE=1 migrate || fail "a Mac whose repositories lack Tensaku passes"
! grep -q pkg-add "$CALL_LOG" || fail "an unavailable Tensaku is not installed"
pass "the migration installs Tensaku only when it is missing and available"

if ADD_STATUS=1 migrate; then fail "a failed install fails the migration so it retries"; fi
pass "a failed install is retried later"

APPLE=1 migrate || fail "a non-Apple machine passes"
[[ ! -s $CALL_LOG ]] || fail "a non-Apple machine is untouched" "$(<"$CALL_LOG")"
pass "the migration gates itself to Apple Silicon"

grep -Fq $'1790226271.sh) printf \'run\\treviewed' "$ROOT/bin/omarchy-migrate" ||
  fail "the Apple Silicon migration policy runs the Tensaku migration"
pass "the Apple Silicon migration policy runs the Tensaku migration"
