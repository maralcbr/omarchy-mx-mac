#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

# Every step omarchy-update runs, recorded in order with the unattended flag it
# was handed. One of them can be told to fail.
steps=(
  omarchy-update-lock
  omarchy-update-requires-free-space
  omarchy-update-confirm
  omarchy-update-pkg-prune
  omarchy-snapshot
  omarchy-update-stay-awake
  omarchy-update-dev
  omarchy-update-asahi-bundle
  omarchy-update-asahi-repository
  omarchy-update-keyring
  omarchy-update-system-pkgs
  omarchy-migrate
  omarchy-update-aurora-repository
  omarchy-hook
  omarchy-update-aur-pkgs
  omarchy-update-mise
  omarchy-update-orphan-pkgs
  omarchy-update-analyze-logs
  omarchy-update-status
  omarchy-update-restart
)

for step in "${steps[@]}"; do
  cat >"$stub_bin/$step" <<'STUB'
#!/bin/bash
printf '%s unattended=%s\n' "${0##*/}" "${OMARCHY_UPDATE_UNATTENDED:-}" >>"$STEP_LOG"
if [[ ${CLEANUP_FAIL:-0} == "1" && ${0##*/} == "omarchy-update-stay-awake" && ${1:-} == "stop" ]]; then
  exit 7
fi
[[ ${FAILING_STEP:-} != "${0##*/}" ]] || exit "${FAILING_STATUS:-42}"
STUB
  chmod +x "$stub_bin/$step"
done

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'STUB'
#!/bin/bash
[[ ${APPLE_SILICON:-0} == 1 ]]
STUB
chmod +x "$stub_bin/omarchy-hw-apple-silicon"

# OMARCHY_UPDATE_LOGGED stands in for the script(1) wrapper the update re-execs
# itself under; the stubbed lock reports itself already held.
run_update() {
  : >"$test_tmp/steps"
  STEP_LOG="$test_tmp/steps" \
    FAILING_STEP="${FAILING_STEP:-}" \
    FAILING_STATUS="${FAILING_STATUS:-}" \
    CLEANUP_FAIL="${CLEANUP_FAIL:-0}" \
    APPLE_SILICON="${APPLE_SILICON:-0}" \
    OMARCHY_REBOOT_BLOCKED="${OMARCHY_REBOOT_BLOCKED:-$test_tmp/no-reboot-block}" \
    OMARCHY_UPDATE_LOGGED=1 \
    PATH="$stub_bin:$PATH" \
    bash "$ROOT/bin/omarchy-update" "$@" >"$test_tmp/out" 2>"$test_tmp/err"
}

steps_run() {
  cut -d' ' -f1 "$test_tmp/steps"
}

# Every step of a whole update, in order. $1 asks for the one a person confirms.
# Stay Awake bookends the work, so it is here twice.
expected_steps() {
  printf '%s\n' \
    omarchy-update-lock \
    omarchy-update-requires-free-space \
    ${1:+omarchy-update-confirm} \
    omarchy-update-pkg-prune \
    omarchy-snapshot \
    omarchy-update-stay-awake \
    omarchy-update-dev \
    omarchy-update-keyring \
    omarchy-update-system-pkgs \
    omarchy-migrate \
    omarchy-hook \
    omarchy-update-aur-pkgs \
    omarchy-update-mise \
    omarchy-update-orphan-pkgs \
    omarchy-update-analyze-logs \
    omarchy-update-status \
    omarchy-update-stay-awake \
    omarchy-update-restart
}

run_update -y || fail "an update where everything works reports a failure"
diff <(expected_steps) <(steps_run) >"$test_tmp/order" ||
  fail "an update where everything works does not run every step in order" "$(cat "$test_tmp/order")"
pass "an update where every step works runs all of them, in order"

grep -q '^omarchy-update-system-pkgs unattended=1$' "$test_tmp/steps" ||
  fail "-y does not mark the update unattended"
run_update </dev/null || fail "a confirmed update reports a failure"
diff <(expected_steps confirmed) <(steps_run) >"$test_tmp/order" ||
  fail "a confirmed update runs a different set of steps" "$(cat "$test_tmp/order")"
grep -q '^omarchy-update-system-pkgs unattended=$' "$test_tmp/steps" ||
  fail "an update a person confirmed is treated as unattended"
pass "-y is what marks an update unattended, not the update itself"

# Migrations ship with the packages the upgrade installs and are written against
# them. Running them against what is still on disk is the failure this ordering
# exists to prevent, so the update stops where the packages did.
if FAILING_STEP=omarchy-update-system-pkgs run_update -y; then
  fail "an update whose packages did not upgrade passes for a whole one"
fi
for step in omarchy-migrate omarchy-update-aurora-repository omarchy-hook omarchy-update-aur-pkgs omarchy-update-restart; do
  if grep -q "^$step " "$test_tmp/steps"; then
    fail "a blocked package upgrade still runs $step"
  fi
done
pass "a blocked package upgrade stops the update before it migrates"

set +e
FAILING_STEP=omarchy-update-system-pkgs CLEANUP_FAIL=1 run_update -y
update_status=$?
set -e
[[ $update_status -eq 42 ]] ||
  fail "cleanup failure replaces the original update status" "expected 42, got $update_status"
pass "cleanup failure preserves the original update status"

# A package upgrade the repositories themselves refuse (status 3) has already
# told the person to try again later; the generic failure banner on top of that
# would send them looking for an error to correct that is not theirs.
set +e
FAILING_STEP=omarchy-update-system-pkgs FAILING_STATUS=3 run_update -y
update_status=$?
set -e
[[ $update_status -eq 3 ]] ||
  fail "a repository mid-transition does not keep its status" "expected 3, got $update_status"
if grep -q 'Something went wrong' "$test_tmp/err" "$test_tmp/out"; then
  fail "a repository mid-transition is reported as something to correct"
fi
if grep -q '^omarchy-migrate \|^omarchy-update-aurora-repository ' "$test_tmp/steps"; then
  fail "a repository mid-transition still migrates"
fi
pass "a repository mid-transition stops the update without the failure banner"

set +e
FAILING_STEP=omarchy-update-system-pkgs run_update -y
set -e
grep -q 'Something went wrong' "$test_tmp/out" "$test_tmp/err" ||
  fail "any other blocked upgrade lost the failure banner"
pass "every other blocked upgrade still shows the failure banner"

# The Apple Silicon bundle and repository steps may defer (3) or, for the repository, fail
# without stopping the update. Their status is taken so the ERR trap cannot print the
# failure banner over an update that carries on; only a bundle that really failed shows it.
apple_expected_steps() {
  expected_steps | sed \
    -e '/^omarchy-update-dev$/a omarchy-update-asahi-bundle\nomarchy-update-asahi-repository' \
    -e '/^omarchy-migrate$/a omarchy-update-aurora-repository'
}

for deferred in omarchy-update-asahi-bundle omarchy-update-asahi-repository; do
  APPLE_SILICON=1 FAILING_STEP=$deferred FAILING_STATUS=3 run_update -y ||
    fail "a deferred $deferred fails the update" "$(cat "$test_tmp/err")"
  diff <(apple_expected_steps) <(steps_run) >"$test_tmp/order" ||
    fail "a deferred $deferred does not run every other step" "$(cat "$test_tmp/order")"
  grep -q 'deferred because' "$test_tmp/err" || fail "a deferred $deferred is not reported"
  if grep -q 'Something went wrong' "$test_tmp/out" "$test_tmp/err"; then
    fail "a deferred $deferred prints the failure banner"
  fi
done
pass "a deferred Apple Silicon bundle or repository step continues without the failure banner"

APPLE_SILICON=1 FAILING_STEP=omarchy-update-asahi-repository FAILING_STATUS=2 run_update -y ||
  fail "a failed repository repoint fails the update"
grep -q 'continuing with the pinned snapshot' "$test_tmp/err" || fail "a failed repository repoint is not reported"
if grep -q 'Something went wrong' "$test_tmp/out" "$test_tmp/err"; then
  fail "a failed repository repoint that the update carries past prints the failure banner"
fi
pass "a failed repository repoint continues on the pinned snapshot without the failure banner"

set +e
APPLE_SILICON=1 FAILING_STEP=omarchy-update-asahi-bundle FAILING_STATUS=2 run_update -y
update_status=$?
set -e
[[ $update_status -eq 2 ]] || fail "a failed bundle update does not keep its status" "expected 2, got $update_status"
grep -q 'Something went wrong' "$test_tmp/out" "$test_tmp/err" || fail "a failed bundle update lost the failure banner"
if grep -q '^omarchy-update-system-pkgs ' "$test_tmp/steps"; then
  fail "a failed bundle update still upgrades packages"
fi
pass "a failed bundle update stops the update with the failure banner"

# An Aurora kernel switch that could not be verified blocks the reboot; the
# update still runs every step, and then does not pass for a finished one.
printf 'the move to aurora-edge-7 is not verified\n' >"$test_tmp/reboot-block"
set +e
OMARCHY_REBOOT_BLOCKED="$test_tmp/reboot-block" run_update -y
update_status=$?
set -e
(( update_status != 0 )) || fail "an update with an unverified kernel switch reports success"
grep -Fq 'The update is not finished: the move to aurora-edge-7 is not verified' "$test_tmp/err" ||
  fail "an unverified kernel switch says why the update is not finished" "$(cat "$test_tmp/err")"
diff <(expected_steps) <(steps_run) >"$test_tmp/order" ||
  fail "an unverified kernel switch still runs every step" "$(cat "$test_tmp/order")"
pass "an unverified kernel switch runs the whole update and then fails it"

# Leftover Asahi headers can fail completion during the package upgrade; the
# update still migrates, then proves the switch again so the same run finishes.
APPLE_SILICON=1 run_update -y || fail "an Apple Silicon update where everything works reports a failure"
diff <(apple_expected_steps) <(steps_run) >"$test_tmp/order" ||
  fail "an Apple Silicon update does not re-complete Aurora after migrations" "$(cat "$test_tmp/order")"
pass "an Apple Silicon update re-runs Aurora completion after migrations"

cat >"$stub_bin/omarchy-update-system-pkgs" <<'STUB'
#!/bin/bash
printf '%s unattended=%s\n' "${0##*/}" "${OMARCHY_UPDATE_UNATTENDED:-}" >>"$STEP_LOG"
printf 'the move to aurora-edge-8 is not verified: leftover linux-asahi-headers\n' >"$OMARCHY_REBOOT_BLOCKED"
[[ ${FAILING_STEP:-} != "${0##*/}" ]] || exit "${FAILING_STATUS:-42}"
STUB
cat >"$stub_bin/omarchy-update-aurora-repository" <<'STUB'
#!/bin/bash
printf '%s unattended=%s\n' "${0##*/}" "${OMARCHY_UPDATE_UNATTENDED:-}" >>"$STEP_LOG"
[[ ${1:-} == --complete ]] || exit 2
[[ ${FAILING_STEP:-} != "${0##*/}" ]] || exit "${FAILING_STATUS:-42}"
rm -f "$OMARCHY_REBOOT_BLOCKED"
STUB
chmod +x "$stub_bin/omarchy-update-system-pkgs" "$stub_bin/omarchy-update-aurora-repository"

printf 'stale\n' >"$test_tmp/heal-block"
set +e
APPLE_SILICON=1 OMARCHY_REBOOT_BLOCKED="$test_tmp/heal-block" run_update -y
update_status=$?
set -e
(( update_status == 0 )) || fail "the same update does not finish after migrating leftover headers" "status $update_status: $(cat "$test_tmp/err")"
[[ ! -e $test_tmp/heal-block ]] || fail "post-migrate completion does not lift the reboot block"
diff <(apple_expected_steps) <(steps_run) >"$test_tmp/order" ||
  fail "the leftover-headers heal still runs every Apple Silicon step" "$(cat "$test_tmp/order")"
pass "the same update heals leftover Asahi headers: migrate, then complete"

# Completion can fail after migrate, and writing the reboot-block marker can
# fail too. That must not be discarded: the update still fails and must not
# restart as if the switch were verified.
cat >"$stub_bin/omarchy-update-system-pkgs" <<'STUB'
#!/bin/bash
printf '%s unattended=%s\n' "${0##*/}" "${OMARCHY_UPDATE_UNATTENDED:-}" >>"$STEP_LOG"
[[ ${FAILING_STEP:-} != "${0##*/}" ]] || exit "${FAILING_STATUS:-42}"
STUB
cat >"$stub_bin/omarchy-update-aurora-repository" <<'STUB'
#!/bin/bash
printf '%s unattended=%s\n' "${0##*/}" "${OMARCHY_UPDATE_UNATTENDED:-}" >>"$STEP_LOG"
[[ ${FAILING_STEP:-} != "${0##*/}" ]] || exit "${FAILING_STATUS:-42}"
STUB
cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$stub_bin/omarchy-update-system-pkgs" "$stub_bin/omarchy-update-aurora-repository" "$stub_bin/sudo"

rm -f "$test_tmp/no-reboot-block"
set +e
APPLE_SILICON=1 FAILING_STEP=omarchy-update-aurora-repository run_update -y
update_status=$?
set -e
(( update_status != 0 )) || fail "a failed Aurora completion reports success when the reboot block cannot be written" "$(cat "$test_tmp/err")"
if grep -q '^omarchy-update-restart ' "$test_tmp/steps"; then
  fail "a failed Aurora completion still restarts when the reboot block cannot be written"
fi
[[ ! -e $test_tmp/no-reboot-block ]] || fail "a failed marker write created the reboot block"
grep -Fq 'The update is not finished: the Aurora kernel switch could not be verified' "$test_tmp/err" ||
  fail "a failed Aurora completion without a marker still says the update is not finished" "$(cat "$test_tmp/err")"
pass "a failed Aurora completion with no reboot-block marker fails the update and does not restart"
