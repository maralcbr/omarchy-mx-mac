#!/bin/bash

set -euo pipefail

fail() {
  echo "notarize-app: $*" >&2
  exit 1
}

(( $# == 1 )) \
  || fail "usage: notarize-app.sh '/absolute/path/Omarchy MX Mac Installer.app'"

app_path="$1"
notary_profile="${OMARCHY_NOTARY_PROFILE:-}"

[[ $app_path == /* && -d $app_path && ! -L $app_path ]] \
  || fail "application must be an absolute path to a real bundle"
[[ -n $notary_profile ]] \
  || fail "OMARCHY_NOTARY_PROFILE is required"
[[ $app_path == *.app ]] \
  || fail "application path must end in .app"

codesign --verify --deep --strict --verbose=2 "$app_path"
signing_details="$(codesign -d --verbose=4 "$app_path" 2>&1)"
[[ $signing_details == *"Authority=Developer ID Application:"* ]] \
  || fail "application is not signed with Developer ID Application"
[[ $signing_details != *"TeamIdentifier=not set"* ]] \
  || fail "application has no signing team"

archive_root="$(mktemp -d /private/tmp/omarchy-notary.XXXXXX)"
trap 'rm -rf "$archive_root"' EXIT
archive_path="$archive_root/Omarchy-MX-Mac-Installer.zip"

ditto -c -k --keepParent "$app_path" "$archive_path"
xcrun notarytool submit "$archive_path" \
  --keychain-profile "$notary_profile" \
  --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
