#!/bin/bash

source "$(dirname "$0")/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"

cat >"$tmp/bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$tmp/bin/mise" <<'SH'
#!/bin/bash
printf '%s\n' "${MISE_MINIMUM_RELEASE_AGE:-unset}" "$*" >"$MISE_TEST_LOG"
SH

chmod +x "$tmp/bin/omarchy-cmd-present" "$tmp/bin/mise"
MISE_TEST_LOG="$tmp/mise.log" PATH="$tmp/bin:$PATH" "$ROOT/bin/omarchy-update-mise" >/dev/null

mapfile -t mise_call <"$tmp/mise.log"
[[ ${mise_call[0]} == "0s" && ${mise_call[1]} == "up" ]] ||
  fail "mise update uses a valid zero release age"
pass "mise update uses a valid zero release age"

HOME="$tmp/home" "$ROOT/bin/omarchy-mise-install" aqua:test test-tool >/dev/null
grep -Fxq 'export MISE_MINIMUM_RELEASE_AGE=0s' "$tmp/home/.local/bin/test-tool" ||
  fail "mise wrapper uses a valid zero release age"
pass "mise wrapper uses a valid zero release age"

grep -Fxq "alias mup='MISE_MINIMUM_RELEASE_AGE=0s mise up'" "$ROOT/default/bash/aliases" ||
  fail "mise update alias uses a valid zero release age"
pass "mise update alias uses a valid zero release age"

cat >"$tmp/bin/omarchy-refresh-applications" <<'SH'
#!/bin/bash
touch "$MISE_REFRESH_LOG"
SH
chmod +x "$tmp/bin/omarchy-refresh-applications"

MISE_REFRESH_LOG="$tmp/refresh.log" PATH="$tmp/bin:$PATH" \
  bash -euo pipefail "$ROOT/migrations/1787231692.sh" >/dev/null
[[ -f $tmp/refresh.log ]] || fail "mise release-age migration refreshes existing wrappers"
pass "mise release-age migration refreshes existing wrappers"
