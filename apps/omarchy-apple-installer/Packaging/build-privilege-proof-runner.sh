#!/bin/bash

set -euo pipefail

fail() { echo "build-privilege-proof-runner: $*" >&2; exit 1; }
(( $# == 2 )) || fail "usage: build-privilege-proof-runner.sh BUILT_PRODUCTS_DIRECTORY NEW_OUTPUT_DIRECTORY"
products="$({ cd "$1" && pwd -P; })"
output="$2"
[[ $output == /* && ! -e $output && ! -L $output ]] || fail "output must be a new absolute directory"
[[ -x $products/OmarchyPrivilegeProofRunner && ! -L $products/OmarchyPrivilegeProofRunner ]] || fail "missing built runner"
identity="${OMARCHY_PROOF_SIGNING_IDENTITY:--}"
timestamp=(--timestamp=none)
if [[ $identity != "-" ]]; then
  [[ ${OMARCHY_PROOF_SIGNING_AUTHORIZED:-} == "yes" ]] || fail "named signing requires explicit authorization"
  timestamp=(--timestamp)
fi
app="$output/Omarchy Proof Automation.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers"
cp "$products/OmarchyPrivilegeProofRunner" "$app/Contents/MacOS/OmarchyPrivilegeProofRunner"
cp "$products/OmarchyPrivilegeProofRunner" "$app/Contents/Helpers/OmarchyUntrustedProofPeer"
/usr/bin/plutil -create xml1 "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string com.omarchy.mx.installer.privilege-proof "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string OmarchyPrivilegeProofRunner "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleName -string 'Omarchy Proof Automation' "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string 0.1.0 "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string 1 "$app/Contents/Info.plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string 15.0 "$app/Contents/Info.plist"
/usr/bin/plutil -insert LSUIElement -bool true "$app/Contents/Info.plist"
# Only this proof identity can talk to the immutable, harmless baseline worker.
# The shipping installer identity is never used by this developer tool.
/usr/bin/codesign --force --sign "$identity" "${timestamp[@]}" --options runtime \
  --identifier com.omarchy.mx.installer.privilege-proof.untrusted-peer "$app/Contents/Helpers/OmarchyUntrustedProofPeer"
/usr/bin/codesign --force --sign "$identity" "${timestamp[@]}" --options runtime \
  --identifier com.omarchy.mx.installer.privilege-proof "$app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
/usr/bin/shasum -a 256 "$app/Contents/MacOS/OmarchyPrivilegeProofRunner"
