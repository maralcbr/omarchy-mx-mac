#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

package=$ROOT/apps/omarchy-apple-installer
build_script=$package/Packaging/build-app.sh
info_plist=$package/Packaging/Info.plist
icon=$package/Packaging/OmarchyInstaller.icns
chrome=$package/Sources/OmarchyAppleInstallerApp/InstallerChrome.swift
package_manifest=$package/Package.swift

if [[ ! -f $icon || -L $icon ]]; then
  fail "installer icon is a real file"
fi
if (( $(wc -c <"$icon") != 42899 )); then
  fail "installer icon has the reviewed size"
fi
if [[ $(sha256sum "$icon" | awk '{print $1}') != \
  "cf26ed5d2831db99c00d62ca046040e01a18e08e63363d629340d04ac6ec8c23" ]]; then
  fail "installer icon has the reviewed digest"
fi
if [[ $(python3 -c 'import plistlib, sys; print(plistlib.load(open(sys.argv[1], "rb"))["CFBundleIconFile"])' \
  "$info_plist") != \
  "OmarchyInstaller" ]]; then
  fail "Info.plist selects the Omarchy app icon"
fi
if ! grep -Fq '"$script_directory/OmarchyInstaller.icns"' "$build_script"; then
  fail "app packaging installs the Omarchy app icon"
fi
if ! grep -Fq 'Bundle.main.url(' "$chrome"; then
  fail "app chrome loads its authoritative image from the assembled app bundle"
fi
if ! grep -Fq 'install -m 0444 "$app_icon_source" "$resources/omarchy-icon.png"' \
  "$build_script"; then
  fail "app packaging installs the authoritative image as a normal app resource"
fi
if grep -Fq 'resources: [.process("Resources")]' "$package_manifest"; then
  fail "app packaging does not generate a second SwiftPM bundle with incompatible lookup semantics"
fi
if ! grep -Fq 'exclude: ["Resources"]' "$package_manifest"; then
  fail "SwiftPM explicitly excludes the manually assembled app resources"
fi

pass "installer packaging binds authoritative Omarchy resources"
