#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB

# Records each invocation; refuses the target when the case says the repository lacks it.
cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$PACMAN_CALLS"
if [[ -n ${NO_PACKAGE:-} && " $* " == *" omarchy-apple-boot "* ]]; then
  if [[ $NO_PACKAGE == color ]]; then
    printf '\033[1;31merror: \033[0mtarget not found: omarchy-apple-boot\n' >&2
  else
    echo "error: target not found: omarchy-apple-boot" >&2
  fi
  exit 1
fi
if [[ -n ${CONFLICT_WITHOUT_TARGET:-} ]]; then
  echo "error: failed to commit transaction (conflicting files)" >&2
  echo "somepkg: /usr/bin/thing exists in filesystem" >&2
  exit 1
fi
echo "upgrade complete"
STUB

cat >"$stub_bin/omarchy-update-system-pkgs-when-conflicted" <<'STUB'
#!/bin/bash
printf 'unavailable=%s\n' "${OMARCHY_APPLE_BOOT_UNAVAILABLE:-}" >"$HANDLER_SEEN"
rm -f "$1"
STUB

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'STUB'
#!/bin/bash
[[ ${APPLE_SILICON:-0} == 1 ]]
STUB

cat >"$stub_bin/omarchy-update-aurora-repository" <<'STUB'
#!/bin/bash
exit 0
STUB

cat >"$stub_bin/omarchy-update-apple-boot-admission" <<'STUB'
#!/bin/bash
echo x >>"$ADMISSION_CALLS"
echo "$ADMISSION"
STUB

chmod +x "$stub_bin"/*

# Remaining arguments are extra environment assignments.
run_update() {
  : >"$test_tmp/pacman-calls"
  : >"$test_tmp/admission-calls"
  rm -rf "$test_tmp/tmp" "$test_tmp/handler-seen"
  mkdir -p "$test_tmp/tmp"
  env PACMAN_CALLS="$test_tmp/pacman-calls" \
    ADMISSION_CALLS="$test_tmp/admission-calls" \
    HANDLER_SEEN="$test_tmp/handler-seen" \
    TMPDIR="$test_tmp/tmp" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    "$@" bash "$ROOT/bin/omarchy-update-system-pkgs" >"$test_tmp/out" 2>&1
}

calls() {
  cat "$test_tmp/pacman-calls"
}

run_update APPLE_SILICON=1 ADMISSION=adopt || fail "an adoptable Mac updates" "$(cat "$test_tmp/out")"
[[ $(wc -l <"$test_tmp/pacman-calls") == 1 ]] || fail "an adoptable Mac upgrades once" "$(calls)"
[[ $(calls) == "-Syu --noconfirm --overwrite /usr/share/omarchy/* --ignore "*" --needed omarchy-apple-boot" ]] ||
  fail "an adoptable Mac names omarchy-apple-boot in its full upgrade" "$(calls)"
pass "an adoptable Mac names omarchy-apple-boot in its full upgrade"

run_update APPLE_SILICON=1 ADMISSION=adopt OMARCHY_UPDATE_RETRY=1 || fail "a retried update succeeds"
[[ $(calls) == *" --needed omarchy-apple-boot" ]] || fail "the conflict handler's retry keeps the target" "$(calls)"
pass "the conflict handler's retry keeps the target"

run_update APPLE_SILICON=1 ADMISSION=adopt OMARCHY_UPDATE_CONFLICT=1 OMARCHY_UPDATE_INTERACTIVE=1 ||
  fail "an interactive update runs"
[[ $(calls) == "-Syu --overwrite /usr/share/omarchy/* --needed omarchy-apple-boot" ]] ||
  fail "the interactive last resort keeps the target" "$(calls)"
pass "the interactive last resort keeps the target"

for state in owned "skip: no image-written boot files"; do
  run_update APPLE_SILICON=1 ADMISSION="$state" || fail "a Mac reporting '$state' updates"
  [[ $(calls) != *omarchy-apple-boot* ]] || fail "a Mac reporting '$state' names no target" "$(calls)"
  ! grep -q 'boot files stay unmanaged' "$test_tmp/out" || fail "a Mac reporting '$state' is not warned"
done
pass "an owned or file-less Mac upgrades without a target or a warning"

run_update APPLE_SILICON=1 ADMISSION="skip: /etc/mkinitcpio.conf.d/90-omarchy-asahi.conf differs from what the image laid down" ||
  fail "a Mac with an edited boot file still updates"
[[ $(calls) != *omarchy-apple-boot* ]] || fail "an edited boot file keeps the Mac out of adoption" "$(calls)"
grep -Fq 'Apple Silicon boot files stay unmanaged: /etc/mkinitcpio.conf.d/90-omarchy-asahi.conf differs' "$test_tmp/out" ||
  fail "an edited boot file is reported" "$(cat "$test_tmp/out")"
pass "an edited boot file keeps the Mac out of adoption and says why"

run_update APPLE_SILICON=0 ADMISSION=adopt || fail "a non-Apple machine updates"
[[ ! -s $test_tmp/admission-calls ]] || fail "a non-Apple machine never checks Apple boot files"
[[ $(calls) != *omarchy-apple-boot* ]] || fail "a non-Apple machine names no target" "$(calls)"
pass "a non-Apple machine never checks Apple boot files"

run_update APPLE_SILICON=1 ADMISSION=adopt NO_PACKAGE=1 || fail "an old repository snapshot does not fail the update" "$(cat "$test_tmp/out")"
[[ $(wc -l <"$test_tmp/pacman-calls") == 2 ]] || fail "an old repository snapshot upgrades twice" "$(calls)"
[[ $(sed -n 2p "$test_tmp/pacman-calls") != *omarchy-apple-boot* ]] ||
  fail "the second upgrade drops the missing target" "$(calls)"
[[ $(wc -l <"$test_tmp/admission-calls") == 1 ]] || fail "the second upgrade does not re-check the boot files"
grep -Fq "has no omarchy-apple-boot yet; updating without it" "$test_tmp/out" ||
  fail "the missing package is explained" "$(cat "$test_tmp/out")"
pass "a repository snapshot without the package updates without it"
[[ -z $(ls -A "$test_tmp/tmp") ]] || fail "the fallback leaves no pacman error reports behind" "$(ls -A "$test_tmp/tmp")"
pass "the fallback leaves no pacman error reports behind"

run_update APPLE_SILICON=1 ADMISSION=adopt NO_PACKAGE=color ||
  fail "a coloured 'target not found' still falls back" "$(cat "$test_tmp/out")"
[[ $(wc -l <"$test_tmp/pacman-calls") == 2 && $(sed -n 2p "$test_tmp/pacman-calls") != *omarchy-apple-boot* ]] ||
  fail "a coloured 'target not found' still falls back" "$(calls)"
[[ ! -e $test_tmp/handler-seen ]] || fail "a coloured 'target not found' is not mistaken for a conflict"
pass "pacman's coloured error prefix does not defeat the fallback"

run_update APPLE_SILICON=1 ADMISSION=adopt NO_PACKAGE=1 CONFLICT_WITHOUT_TARGET=1 || true
[[ $(cat "$test_tmp/handler-seen" 2>/dev/null) == "unavailable=1" ]] ||
  fail "the conflict handler inherits the missing-package decision" "$(cat "$test_tmp/handler-seen" 2>/dev/null)"
pass "the conflict handler inherits the decision to update without the missing package"
