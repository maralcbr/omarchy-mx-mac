#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -r "$tmp_dir"' EXIT

cat >"$tmp_dir/blkid" <<'EOF'
#!/bin/bash
echo /dev/test-luks
EOF

cat >"$tmp_dir/gum" <<'EOF'
#!/bin/bash
head -n 1 "$TEST_INPUTS"
sed -i '1d' "$TEST_INPUTS"
EOF

cat >"$tmp_dir/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$TEST_ARGS"
if [[ $* == *chpasswd* ]]; then
  echo chpasswd >>"$TEST_CHPASSWD"
fi
cat >"$TEST_STDIN"
exit ${TEST_CRYPTSETUP_STATUS:-0}
EOF

cat >"$tmp_dir/omarchy-hw-apple-silicon" <<'EOF'
#!/bin/bash
exit 1
EOF

chmod +x "$tmp_dir/blkid" "$tmp_dir/gum" "$tmp_dir/sudo" "$tmp_dir/omarchy-hw-apple-silicon"
export PATH="$tmp_dir:$ROOT/bin:$PATH"
export TEST_ARGS="$tmp_dir/args" TEST_INPUTS="$tmp_dir/inputs" TEST_STDIN="$tmp_dir/stdin"
export TEST_CHPASSWD="$tmp_dir/chpasswd.out"

printf '\n' >"$TEST_INPUTS"
if "$ROOT/bin/omarchy-drive-password" >/dev/null; then
  fail "drive password rejects an empty passphrase"
fi
[[ ! -e $TEST_ARGS ]] || fail "drive password does not run cryptsetup for an empty passphrase"

printf 'secret123\n*\n' >"$TEST_INPUTS"
if "$ROOT/bin/omarchy-drive-password" >/dev/null; then
  fail "drive password rejects a mismatched confirmation"
fi
[[ ! -e $TEST_ARGS ]] || fail "drive password does not run cryptsetup for a mismatched confirmation"

printf 'new password\nnew password\n' >"$TEST_INPUTS"
"$ROOT/bin/omarchy-drive-password" >/dev/null

[[ $(<"$TEST_STDIN") == "new password" ]] || fail "drive password passes the validated passphrase without a newline"
grep -F 'cryptsetup luksChangeKey' "$TEST_ARGS" >/dev/null || fail "drive password changes the LUKS key"
grep -Fx /dev/test-luks "$TEST_ARGS" >/dev/null || fail "drive password targets the selected drive"
[[ ! -e $TEST_CHPASSWD ]] || fail "Intel drive password does not change the login passphrase"

rm -f "$TEST_ARGS" "$TEST_STDIN" "$TEST_CHPASSWD"
export TEST_CRYPTSETUP_STATUS=1
printf 'new password\nnew password\n' >"$TEST_INPUTS"
if "$ROOT/bin/omarchy-drive-password" >/dev/null; then
  fail "Intel drive password returns cryptsetup's failure"
fi
grep -F 'cryptsetup luksChangeKey' "$TEST_ARGS" >/dev/null || fail "Intel drive password still attempted cryptsetup"
[[ ! -e $TEST_CHPASSWD ]] || fail "Intel drive password does not call chpasswd after cryptsetup failure"
pass "drive password rejects empty and mismatched passphrases and passes validated input to cryptsetup"
