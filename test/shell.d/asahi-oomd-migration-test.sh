#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1789479600.sh"
[[ -f $migration ]] || fail "Apple Silicon systemd-oomd enablement migration exists"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub_bin="$test_tmp/bin"
calls="$test_tmp/calls"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
[[ $TEST_APPLE_SILICON == 1 ]]
SH

cat >"$stub_bin/systemctl" <<'SH'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$TEST_CALLS"
if [[ $1 == "is-enabled" ]]; then
  [[ $TEST_OOMD_ENABLED == 1 ]]
fi
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH
chmod +x "$stub_bin"/*

run_migration() {
  : >"$calls"
  PATH="$stub_bin:$PATH" TEST_CALLS="$calls" TEST_APPLE_SILICON="$1" TEST_OOMD_ENABLED="$2" \
    bash -euo pipefail "$migration" >/dev/null
}

run_migration 0 0
[[ ! -s $calls ]] || fail "migration leaves systemd-oomd alone off Apple Silicon" "$(cat "$calls")"
pass "migration leaves systemd-oomd alone off Apple Silicon"

run_migration 1 0
grep -Fxq 'systemctl enable --now systemd-oomd.service' "$calls" ||
  fail "migration enables systemd-oomd on Apple Silicon" "$(cat "$calls")"
grep -Fxq 'systemctl --user daemon-reload' "$calls" ||
  fail "migration reports app.slice candidacy without a relogin" "$(cat "$calls")"
pass "migration enables systemd-oomd on Apple Silicon"

run_migration 1 1
grep -Fxq 'systemctl try-restart systemd-oomd.service' "$calls" ||
  fail "migration restarts an already enabled systemd-oomd to load the thresholds" "$(cat "$calls")"
! grep -Fq 'enable --now' "$calls" ||
  fail "migration does not re-enable an enabled systemd-oomd" "$(cat "$calls")"
pass "migration restarts an already enabled systemd-oomd"
