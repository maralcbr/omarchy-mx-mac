#!/bin/bash

set -euo pipefail

fail() { echo "build-privilege-proof: $*" >&2; exit 1; }
(( $# == 2 )) || fail "usage: build-privilege-proof.sh BUILT_PRODUCTS_DIRECTORY NEW_OUTPUT_DIRECTORY"
products="$({ cd "$1" && pwd -P; })"
output="$2"
[[ $output == /* ]] || fail "output directory must be absolute"
[[ ! -e $output && ! -L $output ]] || fail "output directory already exists"
for binary in OmarchyPrivilegeProofApp OmarchyPrivilegeProofWorker; do
  [[ -x $products/$binary && ! -L $products/$binary ]] || fail "missing built executable: $binary"
done

# The default is a locally reviewable build that cannot request authorization.
# Named signing must be invoked separately under the owner's production-signing authority.
identity="${OMARCHY_PROOF_SIGNING_IDENTITY:--}"
allows_authorization=false
timestamp=(--timestamp=none)
if [[ $identity != "-" ]]; then
  [[ ${OMARCHY_PROOF_SIGNING_AUTHORIZED:-} == "yes" ]] || fail "named signing requires explicit authorization"
  allows_authorization=true
  timestamp=(--timestamp)
fi

mkdir -p "$output/Omarchy Privilege Proof.app/Contents/MacOS" "$output/Omarchy Privilege Proof.app/Contents/Helpers"
app="$output/Omarchy Privilege Proof.app"
cp "$products/OmarchyPrivilegeProofApp" "$app/Contents/MacOS/OmarchyPrivilegeProofApp"
cp "$products/OmarchyPrivilegeProofWorker" "$app/Contents/Helpers/OmarchyPrivilegeProofWorker"
/usr/bin/plutil -create xml1 "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string com.omarchy.mx.installer.privilege-proof "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string OmarchyPrivilegeProofApp "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleName -string 'Omarchy Privilege Proof' "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string 0.1.0 "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string 1 "$app/Contents/Info.plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string 15.0 "$app/Contents/Info.plist"
/usr/bin/plutil -insert NSHighResolutionCapable -bool true "$app/Contents/Info.plist"
/usr/bin/plutil -insert OmarchyProofAllowsAuthorization -bool "$allows_authorization" "$app/Contents/Info.plist"
/usr/bin/codesign --force --sign "$identity" "${timestamp[@]}" --options runtime \
  --identifier com.omarchy.mx.installer.privilege-proof.worker "$app/Contents/Helpers/OmarchyPrivilegeProofWorker"
/usr/bin/codesign --force --sign "$identity" "${timestamp[@]}" --options runtime "$app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
[[ ! -e $app/Contents/Library/LaunchDaemons ]] || fail "proof must not embed a persistent daemon"
echo "$app"
