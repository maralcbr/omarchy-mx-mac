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
  PATH="$test_tmp/bin:/usr/bin" TMPDIR="$test_tmp/tmp" \
    INVOCATION_LOG="$test_tmp/invocations" bash "$bootstrap" "$@"
}

bash -n "$bootstrap"
grep -Fq 'for cmd in curl gpg gpgv awk' "$bootstrap" || fail "bootstrap checks every verification command"
pass "bootstrap syntax and prerequisites are valid"

: >"$test_tmp/invocations"
run_bootstrap --user example >/dev/null
mapfile -t invocations <"$test_tmp/invocations"
[[ ${invocations[0]} == "--verify-only" ]] || fail "bootstrap pre-verifies the signed installer"
[[ ${invocations[1]} == "--user example" ]] || fail "bootstrap forwards installer arguments"
(( ${#invocations[@]} == 2 )) || fail "bootstrap invokes the installer exactly twice"
pass "bootstrap verifies before forwarding installer arguments"

if find "$test_tmp/tmp" -mindepth 1 -print -quit | grep -q .; then
  fail "bootstrap cleans its non-root working directory"
fi
pass "bootstrap cleans its non-root working directory"

: >"$test_tmp/invocations"
if GPG_FINGERPRINT=invalid run_bootstrap >"$test_tmp/fingerprint.out" 2>&1; then
  fail "bootstrap rejects an unexpected release fingerprint"
fi
grep -Fq 'Release signing key fingerprint mismatch' "$test_tmp/fingerprint.out" || fail "bootstrap reports a fingerprint mismatch"
[[ ! -s $test_tmp/invocations ]] || fail "bootstrap does not run an installer with an unexpected fingerprint"
pass "bootstrap rejects an unexpected release fingerprint"

: >"$test_tmp/invocations"
if GPGV_EXIT=1 run_bootstrap >"$test_tmp/signature.out" 2>&1; then
  fail "bootstrap rejects an invalid installer signature"
fi
grep -Fq 'Installer signature verification failed' "$test_tmp/signature.out" || fail "bootstrap reports an invalid signature"
[[ ! -s $test_tmp/invocations ]] || fail "bootstrap does not run an installer with an invalid signature"
pass "bootstrap rejects an invalid installer signature"

: >"$test_tmp/invocations"
run_bootstrap --verify-only >/dev/null
mapfile -t invocations <"$test_tmp/invocations"
[[ ${invocations[0]} == "--verify-only" && ${invocations[1]} == "--verify-only" ]] || \
  fail "bootstrap preserves the verify-only request"
pass "bootstrap preserves the verify-only request"
