#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

pkg_dir=$ROOT/apps/omarchy-apple-installer/Packaging/pkg
derive=$pkg_dir/derive-daemon-plist

make_app() {
  local app=$1 bundle_program=$2 helper=${3:-Contents/Resources/omarchy-apple-installer-helper}
  mkdir -p "$app/Contents/Library/LaunchDaemons" "$app/$(dirname "$helper")"
  printf '#!/bin/sh\n' >"$app/$helper"
  python3 - "$app/Contents/Library/LaunchDaemons/com.omarchy.mx.installer.helper.plist" "$bundle_program" <<'PY'
import plistlib, sys
plistlib.dump({
    "Label": "com.omarchy.mx.installer.helper",
    "BundleProgram": sys.argv[2],
    "MachServices": {"com.omarchy.mx.installer.helper": True},
    "UserName": "root",
    "KeepAlive": False,
    "EnvironmentVariables": {"OMARCHY_CLIENT_CODE_SIGNING_REQUIREMENT": "anchor apple generic"},
}, open(sys.argv[1], "wb"))
PY
}

read_plist() {
  python3 -c 'import plistlib, sys, json; print(json.dumps(plistlib.load(open(sys.argv[1], "rb")), sort_keys=True))' "$1"
}

app="$test_tmp/Omarchy MX Mac Installer.app"
make_app "$app" Contents/Resources/omarchy-apple-installer-helper
out=$test_tmp/daemon.plist
program=$("$derive" "$app" "$out" /Applications)
[[ $program == "/Applications/Omarchy MX Mac Installer.app/Contents/Resources/omarchy-apple-installer-helper" ]] ||
  fail "the derived daemon Program is the helper's absolute path under /Applications"
derived=$(read_plist "$out")
grep -Fq '"Program": "/Applications/Omarchy MX Mac Installer.app/Contents/Resources/omarchy-apple-installer-helper"' <<<"$derived" ||
  fail "the derived plist records the absolute Program"
! grep -Fq '"BundleProgram"' <<<"$derived" || fail "the derived plist drops the bundle-relative BundleProgram"
grep -Fq '"Label": "com.omarchy.mx.installer.helper"' <<<"$derived" || fail "the derived plist keeps the Label"
grep -Fq '"com.omarchy.mx.installer.helper": true' <<<"$derived" || fail "the derived plist keeps the Mach service"
grep -Fq '"UserName": "root"' <<<"$derived" || fail "the derived plist keeps the root UserName"
grep -Fq 'OMARCHY_CLIENT_CODE_SIGNING_REQUIREMENT' <<<"$derived" || fail "the derived plist keeps the client requirement"
pass "the system daemon plist is derived with an absolute Program inside the installed app"

app_missing="$test_tmp/Missing.app"
make_app "$app_missing" Contents/Resources/omarchy-apple-installer-helper
rm "$app_missing/Contents/Resources/omarchy-apple-installer-helper"
if "$derive" "$app_missing" "$test_tmp/missing.plist" /Applications >/dev/null 2>&1; then
  fail "derivation rejects a helper that is missing inside the app"
fi
app_escape="$test_tmp/Escape.app"
make_app "$app_escape" ../../../usr/bin/true
if "$derive" "$app_escape" "$test_tmp/escape.plist" /Applications >/dev/null 2>&1; then
  fail "derivation rejects a BundleProgram that escapes the bundle"
fi
app_absolute="$test_tmp/Absolute.app"
make_app "$app_absolute" /usr/bin/true
if "$derive" "$app_absolute" "$test_tmp/absolute.plist" /Applications >/dev/null 2>&1; then
  fail "derivation rejects an absolute BundleProgram"
fi
pass "derivation fails closed on missing, escaping, or absolute helper paths"

! grep -Eq 'launchctl bootstrap system "\$PLIST" 2>/dev/null \|\|' "$pkg_dir/scripts/postinstall" ||
  fail "postinstall no longer hides launchctl bootstrap failures"
grep -Fq 'exit 1' "$pkg_dir/scripts/postinstall" || fail "postinstall fails the package when the daemon cannot load"
grep -Fq 'derive-daemon-plist' "$pkg_dir/build-pkg.sh" || fail "build-pkg.sh derives the daemon plist"
grep -Fq 'daemon Program must be an absolute path' "$pkg_dir/build-pkg.sh" || fail "build-pkg.sh fails on a non-absolute daemon Program"
pass "the package builder and postinstall fail closed on an unloadable daemon"
