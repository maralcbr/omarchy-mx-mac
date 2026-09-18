#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"
targets='omarchy-aurora/linux-aurora omarchy-aurora/linux-aurora-headers omarchy-aurora/m1n1-aurora'

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
[[ $1 != tee ]] || printf 'sudo tee %s\n' "$2" >>"$ORDER"
exec "$@"
STUB

# Each pacman run is recorded; the first can be made to fail the way a
# conflict, a missing target or a plain error does.
cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
[[ $1 != -Qo ]] || exit 1
attempt=$(($(cat "$PACMAN_ATTEMPTS") + 1))
echo "$attempt" >"$PACMAN_ATTEMPTS"
printf 'pacman %s\n' "$*" >>"$ORDER"
if ((attempt == 1)); then
  case "${FIRST_PACMAN:-ok}" in
    conflict)
      echo "error: failed to commit transaction (conflicting files)" >&2
      echo "omarchy: $LEFTOVER exists in filesystem" >&2
      exit 1
      ;;
    no-apple-boot)
      echo "error: target not found: omarchy-apple-boot" >&2
      exit 1
      ;;
    fail)
      echo "error: failed to prepare transaction" >&2
      exit 1
      ;;
  esac
fi
echo "upgrade complete"
STUB

# The Aurora step writes the targets while a switch is open; --complete proves it.
cat >"$stub_bin/omarchy-update-aurora-repository" <<'STUB'
#!/bin/bash
if [[ ${1:-} == --complete ]]; then
  echo complete >>"$ORDER"
  exit "${COMPLETE_STATUS:-0}"
fi
echo aurora >>"$ORDER"
if [[ -n ${AURORA_TARGETS:-} ]]; then
  printf '%s\n' $AURORA_TARGETS >"$OMARCHY_AURORA_TARGETS"
fi
exit "${AURORA_STATUS:-0}"
STUB

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'STUB'
#!/bin/bash
exit 0
STUB

cat >"$stub_bin/omarchy-update-apple-boot-admission" <<'STUB'
#!/bin/bash
echo "${ADMISSION:-owned}"
STUB

chmod +x "$stub_bin"/*

run_update() {
  : >"$test_tmp/order"
  echo 0 >"$test_tmp/attempts"
  rm -rf "$test_tmp/tmp" "$test_tmp/replaced" "$test_tmp/reboot-blocked"
  mkdir -p "$test_tmp/tmp"
  printf 'left by an old installer\n' >"$test_tmp/leftover"
  set +e
  env ORDER="$test_tmp/order" \
    PACMAN_ATTEMPTS="$test_tmp/attempts" \
    TMPDIR="$test_tmp/tmp" \
    OMARCHY_REPLACED_DIR="$test_tmp/replaced" \
    LEFTOVER="$test_tmp/leftover" \
    OMARCHY_REBOOT_BLOCKED="$test_tmp/reboot-blocked" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    "$@" bash "$ROOT/bin/omarchy-update-system-pkgs" >"$test_tmp/out" 2>&1
  status=$?
  set -e
}

pacman_runs() {
  grep '^pacman ' "$test_tmp/order" || true
}

# The normal path.
run_update AURORA_TARGETS="$targets"
(( status == 0 )) || fail "an open switch upgrades" "status $status: $(cat "$test_tmp/out")"
[[ $(pacman_runs) == "pacman -Syu --noconfirm --overwrite /usr/share/omarchy/* --ignore "*" --needed $targets" ]] ||
  fail "an open switch names the release's packages by repository" "$(pacman_runs)"
[[ $(cat "$test_tmp/order") == $'aurora\npacman '*$'\ncomplete' ]] || fail "the switch is completed after the upgrade" "$(cat "$test_tmp/order")"
[[ -z $(ls -A "$test_tmp/tmp") ]] || fail "the targets file is removed" "$(ls -A "$test_tmp/tmp")"
run_update AURORA_TARGETS="$targets" ADMISSION=adopt
[[ $(pacman_runs) == "pacman -Syu --noconfirm --overwrite /usr/share/omarchy/* --ignore "*" --needed omarchy-apple-boot $targets" ]] ||
  fail "the targets share --needed with the boot adoption" "$(pacman_runs)"
run_update
[[ $(pacman_runs) != *omarchy-aurora/* && $(cat "$test_tmp/order") != *complete* ]] ||
  fail "without an open switch nothing is named and nothing completed" "$(cat "$test_tmp/order")"
pass "an open switch names its packages in the upgrade and is completed after it"

# Every other way the upgrade runs keeps the targets.
run_update AURORA_TARGETS="$targets" FIRST_PACMAN=conflict
(( status == 0 )) || fail "a conflict retry succeeds" "status $status: $(cat "$test_tmp/out")"
(( $(pacman_runs | wc -l) == 2 )) && [[ $(pacman_runs | sed -n 2p) == *" --needed $targets" ]] ||
  fail "the conflict retry keeps the targets" "$(pacman_runs)"
(( $(grep -c '^complete$' "$test_tmp/order") == 1 )) || fail "the retry completes the switch once" "$(cat "$test_tmp/order")"
run_update AURORA_TARGETS="$targets" ADMISSION=adopt FIRST_PACMAN=no-apple-boot
(( status == 0 )) || fail "the re-run without omarchy-apple-boot succeeds" "status $status: $(cat "$test_tmp/out")"
[[ $(pacman_runs | sed -n 2p) == *" --needed $targets" && $(pacman_runs | sed -n 2p) != *omarchy-apple-boot* ]] ||
  fail "the re-run without omarchy-apple-boot keeps the Aurora targets" "$(pacman_runs)"
run_update AURORA_TARGETS="$targets" OMARCHY_UPDATE_CONFLICT=1 OMARCHY_UPDATE_INTERACTIVE=1
(( status == 0 )) || fail "the interactive upgrade succeeds" "status $status: $(cat "$test_tmp/out")"
[[ $(pacman_runs) == "pacman -Syu --overwrite /usr/share/omarchy/* --needed $targets" ]] ||
  fail "the interactive upgrade keeps the targets" "$(pacman_runs)"
[[ $(tail -1 "$test_tmp/order") == complete ]] || fail "the interactive upgrade is followed by the same completion" "$(cat "$test_tmp/order")"
run_update AURORA_TARGETS="$targets" OMARCHY_UPDATE_CONFLICT=1 OMARCHY_UPDATE_INTERACTIVE=1 FIRST_PACMAN=fail
(( status == 1 )) && ! grep -qx complete "$test_tmp/order" || fail "a failed interactive upgrade completes nothing" "status $status: $(cat "$test_tmp/order")"
pass "the conflict retry, the re-run without omarchy-apple-boot and the interactive upgrade keep the targets and complete after"

# An unexpected target is not handed to pacman.
run_update AURORA_TARGETS="omarchy-aurora/linux-aurora extra/linux"
(( status == 1 )) && [[ -z $(pacman_runs) ]] || fail "an unexpected target stops the update" "status $status: $(pacman_runs)"
pass "only the three Aurora packages are accepted as targets"

# 3 is edge deferred: the upgrade runs on the current pin and nothing completes.
run_update AURORA_STATUS=3 AURORA_TARGETS="$targets"
(( status == 0 )) || fail "a deferred edge move still upgrades" "status $status: $(cat "$test_tmp/out")"
[[ $(pacman_runs) == "pacman -Syu --noconfirm --overwrite /usr/share/omarchy/* --ignore "* && $(pacman_runs) != *omarchy-aurora/* ]] ||
  fail "a deferred edge move names no targets" "$(pacman_runs)"
! grep -qx complete "$test_tmp/order" || fail "a deferred edge move never completes a switch"
for aurora_status in 1 2; do
  run_update AURORA_STATUS=$aurora_status AURORA_TARGETS="$targets"
  (( status == 1 )) && [[ -z $(pacman_runs) ]] || fail "Aurora status $aurora_status stops before pacman" "status $status"
done
run_update AURORA_TARGETS="$targets" FIRST_PACMAN=fail OMARCHY_UPDATE_RETRY=1
(( status == 1 )) && ! grep -qx complete "$test_tmp/order" || fail "a failed upgrade completes nothing"
pass "exit 3 upgrades on the current pin without completing, 1 and 2 stop, and a failed upgrade completes nothing"

# A switch that cannot be proven blocks the reboot but does not undo the upgrade.
run_update AURORA_TARGETS="$targets" COMPLETE_STATUS=1
(( status == 0 )) || fail "an unverified switch still lets the update carry on" "status $status"
grep -Fq 'could not be verified' "$test_tmp/reboot-blocked" || fail "an unverified switch blocks the reboot" "$(cat "$test_tmp/reboot-blocked" 2>&1)"
pass "an unverified switch blocks the reboot and lets the rest of the update run"
