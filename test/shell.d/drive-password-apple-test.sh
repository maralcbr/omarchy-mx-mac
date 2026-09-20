#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -r "$tmp"' EXIT

cat >"$tmp/blkid" <<'EOF'
#!/bin/bash
echo /dev/test-luks
EOF

cat >"$tmp/gum" <<'EOF'
#!/bin/bash
head -n 1 "$TEST_INPUTS"
sed -i '1d' "$TEST_INPUTS"
EOF

cat >"$tmp/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$TEST_ARGS"
cat >"$TEST_STDIN"
EOF

cat >"$tmp/omarchy-hw-apple-silicon" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$tmp/chpasswd" <<'EOF'
#!/bin/bash
cat >>"$TEST_CHPASSWD"
EOF

cat >"$tmp/logname" <<'EOF'
#!/bin/bash
echo testuser
EOF

chmod +x "$tmp"/{blkid,gum,sudo,omarchy-hw-apple-silicon,chpasswd,logname}
export PATH="$tmp:$ROOT/bin:$PATH"
export TEST_ARGS="$tmp/args" TEST_INPUTS="$tmp/inputs" TEST_STDIN="$tmp/stdin" TEST_CHPASSWD="$tmp/chpasswd.out"
export SUDO_USER=testuser

printf 'new password\nnew password\n' >"$TEST_INPUTS"
"$ROOT/bin/omarchy-drive-password" >/dev/null

[[ $(<"$TEST_STDIN") == "new password" ]] || fail "Apple drive password passes the validated passphrase without a newline"
grep -F 'cryptsetup luksChangeKey' "$TEST_ARGS" >/dev/null || fail "Apple drive password changes the LUKS key"
grep -Fx /dev/test-luks "$TEST_ARGS" >/dev/null || fail "Apple drive password targets the selected drive"
grep -Fx 'testuser:new password' "$TEST_CHPASSWD" >/dev/null || fail "Apple drive password keeps the login passphrase in sync"
grep -Fx 'root:new password' "$TEST_CHPASSWD" >/dev/null || fail "Apple drive password keeps the root passphrase in sync"
! grep -F 'limine-update' "$TEST_ARGS" >/dev/null || fail "Apple drive password does not rebuild a Limine UKI"
pass "Apple GRUB+sd-encrypt drive password changes LUKS and keeps login in sync"
