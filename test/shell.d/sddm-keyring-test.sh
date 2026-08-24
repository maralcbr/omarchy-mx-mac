#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

pam_file="$test_tmp/sddm"
autologin_file="$test_tmp/sddm-autologin"
leaf="$ROOT/install/login/sddm.sh"

cat >"$pam_file" <<'PAM'
#%PAM-1.0
auth        include     system-login
-auth       optional    pam_kwallet5.so
account     include     system-login
session     include     system-login
-session    optional    pam_gnome_keyring.so auto_start
PAM
cat >"$autologin_file" <<'PAM'
#%PAM-1.0
auth        required    pam_permit.so
-auth       optional    pam_gnome_keyring.so
session     include     system-local-login
PAM

autologin_before=$(sha256sum "$autologin_file")
OMARCHY_SDDM_PAM_FILE="$pam_file" bash -euo pipefail -c 'source "$1"' _ "$leaf"
grep -Fxq -- '-auth       optional    pam_gnome_keyring.so' "$pam_file" || fail "SDDM setup restores the GNOME Keyring auth hook"
[[ $(grep -Ec '^[[:space:]]*-?auth[[:space:]]+.*pam_gnome_keyring\.so([[:space:]]|$)' "$pam_file") == 1 ]] || fail "SDDM setup writes one GNOME Keyring auth hook"
grep -Fxq -- '-auth       optional    pam_kwallet5.so' "$pam_file" || fail "SDDM setup preserves other auth hooks"
grep -Fxq -- '-session    optional    pam_gnome_keyring.so auto_start' "$pam_file" || fail "SDDM setup preserves the keyring session hook"
[[ $(sha256sum "$autologin_file") == "$autologin_before" ]] || fail "SDDM setup leaves the autologin PAM stack unchanged"
pass "password login gains keyring unlock without changing autologin"

after_first=$(sha256sum "$pam_file")
OMARCHY_SDDM_PAM_FILE="$pam_file" bash -euo pipefail -c 'source "$1"' _ "$leaf"
[[ $(sha256sum "$pam_file") == "$after_first" ]] || fail "SDDM keyring setup is idempotent"
pass "SDDM keyring setup is idempotent"

cat >"$pam_file" <<'PAM'
#%PAM-1.0
auth include system-login
auth optional pam_gnome_keyring.so
account include system-login
PAM
before_existing=$(sha256sum "$pam_file")
OMARCHY_SDDM_PAM_FILE="$pam_file" bash -euo pipefail -c 'source "$1"' _ "$leaf"
[[ $(sha256sum "$pam_file") == "$before_existing" ]] || fail "SDDM setup preserves an existing non-dashed auth hook"
pass "SDDM setup accepts the packaged hook variants"

grep -Fq 'SDDM GNOME Keyring auth hook' "$ROOT/test/vm/asahi-fresh/guest/verify" || fail "fresh-install VM verifies keyring authentication"
pass "fresh-install VM requires both GNOME Keyring PAM phases"

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"
cat >"$mock_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
exit "${OMARCHY_TEST_PACKAGE_MISSING:-0}"
SH
cat >"$mock_bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH
chmod +x "$mock_bin"/*

cat >"$pam_file" <<'PAM'
#%PAM-1.0
auth include system-login
account include system-login
-session optional pam_gnome_keyring.so auto_start
PAM
OMARCHY_PATH="$ROOT" OMARCHY_SDDM_PAM_FILE="$pam_file" PATH="$mock_bin:$PATH" \
  bash -euo pipefail "$ROOT/migrations/1787552167.sh"
grep -Eq '^-auth[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so$' "$pam_file" || fail "migration repairs a previously stripped SDDM stack"
pass "existing password-login installations regain keyring unlock"

sed -i '/pam_gnome_keyring\.so/d' "$pam_file"
before_missing=$(sha256sum "$pam_file")
OMARCHY_TEST_PACKAGE_MISSING=1 OMARCHY_PATH="$ROOT" OMARCHY_SDDM_PAM_FILE="$pam_file" PATH="$mock_bin:$PATH" \
  bash -euo pipefail "$ROOT/migrations/1787552167.sh"
[[ $(sha256sum "$pam_file") == "$before_missing" ]] || fail "migration skips systems without GNOME Keyring"
grep -Fq '1787552167.sh)' "$ROOT/bin/omarchy-migrate" || fail "keyring migration is reviewed for Asahi"
pass "keyring migration is package-aware and reviewed"
