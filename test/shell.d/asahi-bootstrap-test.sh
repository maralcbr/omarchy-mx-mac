#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

bootstrap="$ROOT/install-omarchy-mx-mac.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/tmp"

cat >"$test_tmp/bin/curl" <<'EOF'
#!/bin/bash

for argument in "$@"; do
  [[ $argument == https://* ]] && output=${argument##*/}
done

case "$output" in
  install-omarchy-mx-mac)
    cat >"$output" <<'INSTALLER'
#!/bin/bash
printf '%s\n' "$*" >>"$INVOCATION_LOG"
identity_bytes=$(wc -c <"${OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE:-/dev/null}")
printf 'identity:%s:%s\n' "${OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE:-}" "${identity_bytes//[[:space:]]/}" >>"$IDENTITY_LOG"
printf 'run\n' >>"${OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE:-/dev/null}"
INSTALLER
    ;;
  *)
    : >"$output"
    ;;
esac
EOF

cat >"$test_tmp/bin/gpg" <<'EOF'
#!/bin/bash
printf 'fpr:::::::::%s:\n' "${GPG_FINGERPRINT:-5983B1CA32CB778F4D74D24ECFF35022CA5B5959}"
EOF

cat >"$test_tmp/bin/gpgv" <<'EOF'
#!/bin/bash
exit "${GPGV_EXIT:-0}"
EOF

chmod +x "$test_tmp/bin"/*

run_bootstrap() {
  PATH="$test_tmp/bin:$(dirname "$BASH"):/usr/bin:/bin" TMPDIR="$test_tmp/tmp" \
    INVOCATION_LOG="$test_tmp/invocations" IDENTITY_LOG="$test_tmp/identities" \
    bash "$bootstrap" "$@"
}

bash -n "$bootstrap"
grep -Fq 'for cmd in curl gpg gpgv awk' "$bootstrap" || fail "bootstrap checks every verification command"
pass "bootstrap syntax and prerequisites are valid"

: >"$test_tmp/invocations"
: >"$test_tmp/identities"
run_bootstrap --user example >/dev/null
mapfile -t invocations <"$test_tmp/invocations"
[[ ${invocations[0]} == "--verify-only --user example" ]] || fail "bootstrap pre-verifies the signed installer with the same arguments"
[[ ${invocations[1]} == "--user example" ]] || fail "bootstrap forwards installer arguments"
(( ${#invocations[@]} == 2 )) || fail "bootstrap invokes the installer exactly twice"
pass "bootstrap verifies before forwarding installer arguments"

# Both runs must select the same release, so the wrapper owns the file they
# hand that selection over in and starts it empty.
mapfile -t identities <"$test_tmp/identities"
identity_path=${identities[0]%:*}
identity_path=${identity_path#identity:}
[[ $identity_path == */channel-identity ]] ||
  fail "bootstrap creates the handover file in its own work directory" "${identities[*]}"
[[ ${identities[0]} == "identity:$identity_path:0" ]] || fail "the handover file starts empty"
[[ ${identities[1]} == "identity:$identity_path:4" ]] || fail "both runs share one handover file"
pass "bootstrap hands one empty-at-first identity file to both runs"

if find "$test_tmp/tmp" -mindepth 1 -print -quit | grep -q .; then
  fail "bootstrap cleans its non-root working directory"
fi
pass "bootstrap cleans its non-root working directory"

: >"$test_tmp/invocations"
: >"$test_tmp/identities"
if GPG_FINGERPRINT=invalid run_bootstrap >"$test_tmp/fingerprint.out" 2>&1; then
  fail "bootstrap rejects an unexpected release fingerprint"
fi
grep -Fq 'Release signing key fingerprint mismatch' "$test_tmp/fingerprint.out" || fail "bootstrap reports a fingerprint mismatch"
[[ ! -s $test_tmp/invocations ]] || fail "bootstrap does not run an installer with an unexpected fingerprint"
pass "bootstrap rejects an unexpected release fingerprint"

: >"$test_tmp/invocations"
: >"$test_tmp/identities"
if GPGV_EXIT=1 run_bootstrap >"$test_tmp/signature.out" 2>&1; then
  fail "bootstrap rejects an invalid installer signature"
fi
grep -Fq 'Installer signature verification failed' "$test_tmp/signature.out" || fail "bootstrap reports an invalid signature"
[[ ! -s $test_tmp/invocations ]] || fail "bootstrap does not run an installer with an invalid signature"
pass "bootstrap rejects an invalid installer signature"

: >"$test_tmp/invocations"
: >"$test_tmp/identities"
run_bootstrap --verify-only >/dev/null
mapfile -t invocations <"$test_tmp/invocations"
[[ ${invocations[0]} == "--verify-only --verify-only" && ${invocations[1]} == "--verify-only" ]] || \
  fail "bootstrap preserves the verify-only request"
pass "bootstrap preserves the verify-only request"

# First boot selects its release once and hands every attempt the same file,
# with the matching --release-tag, so the wrapper keeps that file as it is.
handover="$test_tmp/first-boot-selection"
selection=$'format=1\nselector=release\nvalue=asahi-quattro-fe8d2bf8\nrelease_tag=asahi-quattro-fe8d2bf8\n'
printf '%s' "$selection" >"$handover"
for attempt in 1 2; do
  : >"$test_tmp/invocations"
  : >"$test_tmp/identities"
  OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE="$handover" \
    run_bootstrap --deferred-user --release-tag asahi-quattro-fe8d2bf8 >/dev/null
  mapfile -t invocations <"$test_tmp/invocations"
  [[ ${invocations[0]} == "--verify-only --deferred-user --release-tag asahi-quattro-fe8d2bf8" &&
    ${invocations[1]} == "--deferred-user --release-tag asahi-quattro-fe8d2bf8" ]] ||
    fail "a first-boot attempt forwards --deferred-user and its release to both runs" "${invocations[*]}"
  mapfile -t identities <"$test_tmp/identities"
  [[ ${identities[0]} == "identity:$handover:$(( ${#selection} + (attempt - 1) * 8 ))" &&
    ${identities[1]} == "identity:$handover:$(( ${#selection} + (attempt - 1) * 8 + 4 ))" ]] ||
    fail "attempt $attempt hands both runs the first-boot selection without truncating it" "${identities[*]}"
done
[[ $(head -c "${#selection}" "$handover") == "${selection%$'\n'}" ]] || fail "the first-boot selection survives every attempt"
pass "a first-boot attempt keeps its handed-over selection across invocations"

: >"$test_tmp/invocations"
: >"$test_tmp/identities"
printf '%s' "$selection" >"$handover"
OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE="$handover" run_bootstrap --user example >/dev/null
mapfile -t identities <"$test_tmp/identities"
[[ ${identities[0]} == */channel-identity:0 ]] || fail "without --deferred-user the wrapper uses its own empty file" "${identities[*]}"
[[ $(<"$handover") == "${selection%$'\n'}" ]] || fail "without --deferred-user a handed-over file is left alone"
if OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE=first-boot-selection run_bootstrap --deferred-user >"$test_tmp/relative.out" 2>&1; then
  fail "a relative first-boot selection is refused"
fi
grep -Fq 'must be an absolute path' "$test_tmp/relative.out" || fail "a relative first-boot selection says why"
pass "only a first-boot run keeps a handed-over file, and only by absolute path"
