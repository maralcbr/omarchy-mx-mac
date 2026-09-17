#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

grep -Fq 'asahi_status == 3' "$ROOT/bin/omarchy-update-available" || fail "availability checks tolerate bundle transport outages"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
git_log="$test_tmp/git.log"
mkdir -p "$stub_bin"

cat >"$stub_bin/checkupdates" <<'SH'
#!/bin/bash
case "${TEST_CHECKUPDATES:-updates}" in
  updates)
    printf 'linux 6.1-1 -> 6.1-2\nomarchy 4.0.0-1 -> 4.0.1-1\nomarchy-settings 4.0.0-1 -> 4.0.1-1\nomarchy-dev 4.1.0-1 -> 4.1.1-1\nomarchy-settings-dev 4.1.0-1 -> 4.1.1-1\n'
    exit 0
    ;;
  none)
    exit 2
    ;;
  fail)
    echo "check failed" >&2
    exit 1
    ;;
esac
SH
chmod +x "$stub_bin/checkupdates"

cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
case "$1" in
  -Qq)
    case "${TEST_INSTALLED_PACKAGE:-omarchy}" in
      omarchy)
        [[ $2 == "omarchy" ]]; exit $?
        ;;
      omarchy-dev)
        [[ $2 == "omarchy-dev" ]]; exit $?
        ;;
      both)
        [[ $2 == "omarchy" || $2 == "omarchy-dev" ]]; exit $?
        ;;
      none)
        exit 1
        ;;
    esac
    ;;
esac
exit 0
SH
chmod +x "$stub_bin/pacman"

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
[[ ${TEST_APPLE_SILICON:-0} == 1 ]]
SH
for asahi_check in omarchy-update-asahi-bundle omarchy-update-asahi-repository; do
  cat >"$stub_bin/$asahi_check" <<'SH'
#!/bin/bash
name=${0##*/}
name=${name#omarchy-update-asahi-}
output_var="TEST_${name^^}_OUTPUT"
status_var="TEST_${name^^}_STATUS"
[[ -z ${!output_var:-} ]] || printf '%s\n' "${!output_var}"
exit "${!status_var:-1}"
SH
  chmod +x "$stub_bin/$asahi_check"
done
chmod +x "$stub_bin/omarchy-hw-apple-silicon"

cat >"$stub_bin/git" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$TEST_GIT_LOG"

[[ $1 == "-C" ]] || exit 1
shift 2

case "$1" in
  fetch)
    [[ ${TEST_GIT_FETCH:-ok} == "ok" ]]
    ;;
  rev-parse)
    case "$2" in
      --is-inside-work-tree)
        [[ ${TEST_GIT_CHECKOUT:-yes} == "yes" ]] || exit 1
        echo true
        ;;
      --abbrev-ref)
        [[ ${TEST_GIT_UPSTREAM:-origin/quattro} != "none" ]] || exit 1
        echo "${TEST_GIT_UPSTREAM:-origin/quattro}"
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  rev-list)
    echo "${TEST_GIT_BEHIND:-0}"
    ;;
  *)
    exit 1
    ;;
esac
SH
chmod +x "$stub_bin/git"

run_checker() {
  OMARCHY_PATH="${TEST_OMARCHY_PATH:-/usr/share/omarchy}" \
    TEST_GIT_LOG="$git_log" \
    PATH="$stub_bin:$PATH" \
    "$ROOT/bin/omarchy-update-available"
}

capture_checker() {
  local stdout_file="$1"
  local stderr_file="$2"
  shift 2

  set +e
  (
    export "$@"
    run_checker
  ) >"$stdout_file" 2>"$stderr_file"
  local status=$?
  set -e
  return "$status"
}

stdout="$test_tmp/stdout"
stderr="$test_tmp/stderr"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=updates TEST_INSTALLED_PACKAGE=omarchy; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker exits successfully when omarchy update is available"
grep -q '^omarchy ' "$stdout" || fail "update checker prints omarchy updates"
! grep -q '^omarchy-settings ' "$stdout" || fail "update checker ignores omarchy-settings updates"
! grep -q '^linux ' "$stdout" || fail "update checker ignores non-Omarchy package updates"
! grep -q '^omarchy-dev ' "$stdout" || fail "update checker ignores omarchy-dev when omarchy is installed"
pass "update checker detects installed omarchy package updates"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=updates TEST_INSTALLED_PACKAGE=omarchy-dev; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker exits successfully when omarchy-dev update is available"
grep -q '^omarchy-dev ' "$stdout" || fail "update checker prints omarchy-dev updates"
! grep -q '^omarchy-settings-dev ' "$stdout" || fail "update checker ignores omarchy-settings-dev updates"
! grep -q '^omarchy ' "$stdout" || fail "update checker ignores omarchy when omarchy-dev is installed"
pass "update checker detects installed omarchy-dev package updates"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=updates TEST_INSTALLED_PACKAGE=both; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker prefers omarchy-dev when both packages are installed"
grep -q '^omarchy-dev ' "$stdout" || fail "update checker prints omarchy-dev when both packages are installed"
! grep -q '^omarchy ' "$stdout" || fail "update checker ignores omarchy when omarchy-dev is installed"
pass "update checker prefers omarchy-dev over omarchy"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=updates TEST_INSTALLED_PACKAGE=none; then
  status=0
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "update checker exits non-zero when no Omarchy package is installed"
[[ ! -s $stderr ]] || fail "update checker is quiet when no Omarchy package is installed"
pass "update checker ignores systems without omarchy or omarchy-dev installed"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=none TEST_INSTALLED_PACKAGE=omarchy; then
  status=0
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "update checker exits non-zero when no updates are available"
grep -q '^Omarchy is up to date$' "$stdout" || fail "update checker prints up-to-date message"
pass "update checker reports up-to-date Omarchy packages"

: >"$git_log"
if capture_checker "$stdout" "$stderr" \
  TEST_CHECKUPDATES=none \
  TEST_INSTALLED_PACKAGE=none \
  TEST_OMARCHY_PATH="$test_tmp/checkout" \
  TEST_GIT_BEHIND=2; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker exits successfully when dev commits are available"
grep -Fx 'omarchy-dev-checkout 2 new commits on origin/quattro' "$stdout" >/dev/null ||
  fail "update checker reports available dev commits" "$(cat "$stdout")"
grep -Fx -- "-C $test_tmp/checkout fetch --quiet" "$git_log" >/dev/null ||
  fail "update checker fetches the dev checkout upstream" "$(cat "$git_log")"
pass "update checker detects new commits in the dev checkout"

if capture_checker "$stdout" "$stderr" \
  TEST_CHECKUPDATES=none \
  TEST_INSTALLED_PACKAGE=none \
  TEST_OMARCHY_PATH="$test_tmp/checkout" \
  TEST_GIT_BEHIND=0; then
  status=0
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "update checker exits non-zero when the dev checkout is current"
grep -q '^Omarchy is up to date$' "$stdout" || fail "update checker reports a current dev checkout"
pass "update checker ignores a current dev checkout"

if capture_checker "$stdout" "$stderr" \
  TEST_CHECKUPDATES=none \
  TEST_INSTALLED_PACKAGE=none \
  TEST_OMARCHY_PATH="$test_tmp/checkout" \
  TEST_GIT_BEHIND=1 \
  TEST_GIT_FETCH=fail; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker uses cached upstream state when fetch fails"
grep -Fx 'omarchy-dev-checkout 1 new commit on origin/quattro' "$stdout" >/dev/null ||
  fail "update checker reports cached dev commits after a fetch failure" "$(cat "$stdout")"
[[ ! -s $stderr ]] || fail "update checker keeps dev fetch failures quiet" "$(cat "$stderr")"
pass "update checker uses cached dev state when fetching is unavailable"

# A repository check that exits 1 is not an update, whatever it printed.
if capture_checker "$stdout" "$stderr" \
  TEST_APPLE_SILICON=1 \
  TEST_INSTALLED_PACKAGE=omarchy-dev \
  TEST_REPOSITORY_OUTPUT='Apple Silicon package repository: unrecognised [omarchy] Server; not moving it' \
  TEST_REPOSITORY_STATUS=1; then
  status=0
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "a repository check with no update is reported as one" "$(cat "$stdout")"
grep -qx 'Omarchy is up to date' "$stdout" || fail "an Apple Silicon Mac with no updates says so" "$(cat "$stdout")"
pass "Apple Silicon checks that exit 1 never become updates"

if capture_checker "$stdout" "$stderr" \
  TEST_APPLE_SILICON=1 \
  TEST_INSTALLED_PACKAGE=omarchy-dev \
  TEST_REPOSITORY_OUTPUT='Apple Silicon package repository asahi-packages-stable-abc is available' \
  TEST_REPOSITORY_STATUS=0; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "an available repository update is not reported"
grep -qx 'Apple Silicon package repository asahi-packages-stable-abc is available' "$stdout" ||
  fail "an available repository update is listed" "$(cat "$stdout")"
pass "an available Apple Silicon repository update is listed"
