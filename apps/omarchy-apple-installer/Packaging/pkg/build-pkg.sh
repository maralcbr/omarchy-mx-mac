#!/bin/bash
# Build a signed + notarized macOS installer package for the Omarchy Apple
# Silicon installer. The package installs the notarized app to /Applications and
# a system LaunchDaemon to /Library/LaunchDaemons, then loads the daemon in its
# postinstall — so the recipient enters one admin password (the macOS installer
# prompt) and never touches Login Items.
#
# Usage: build-pkg.sh --app <signed .app> --plist <helper-launchdaemon.plist> \
#          --version <x.y.z> --out <output.pkg>
set -euo pipefail

APP="" PLIST="" VERSION="" OUT=""
INSTALLER_ID="Developer ID Installer: MARCELO DE BARROS ALCANTARA (T2C384FJBD)"
PKG_IDENTIFIER="com.omarchy.mx.installer.pkg"
SCRIPTS="$(cd "$(dirname "$0")" && pwd)/scripts"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --plist) PLIST="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --installer-identity) INSTALLER_ID="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -d "$APP" && -f "$PLIST" && -n "$VERSION" && -n "$OUT" ]] || {
  echo "usage: build-pkg.sh --app <app> --plist <plist> --version <v> --out <pkg>" >&2
  exit 64
}

work="$(mktemp -d /tmp/omarchy-pkg.XXXXXX)"
trap 'rm -rf "$work"' EXIT
root="$work/root"
mkdir -p "$root/Applications" "$root/Library/LaunchDaemons"

# Payload: the notarized app and the system daemon plist.
/usr/bin/ditto "$APP" "$root/Applications/$(basename "$APP")"
/usr/bin/install -m 0644 "$PLIST" "$root/Library/LaunchDaemons/com.omarchy.mx.installer.helper.plist"

# Confirm the plist's Program points at where the app actually lands.
prog="$(/usr/bin/plutil -extract Program raw -o - "$PLIST" 2>/dev/null || true)"
echo "daemon Program: $prog"

# Pin the app to /Applications. Without this, PackageKit "relocates" the
# install onto any existing copy of the bundle it can find anywhere on disk
# (it did exactly that onto a stale test copy in /Users/Shared), leaving
# /Applications empty and the daemon pointing at nothing.
component_plist="$work/component.plist"
/usr/bin/pkgbuild --analyze --root "$root" "$component_plist"
/usr/bin/plutil -replace 0.BundleIsRelocatable -bool false "$component_plist"

echo "=== pkgbuild (component) ==="
comp="$work/component.pkg"
/usr/bin/pkgbuild \
  --root "$root" \
  --component-plist "$component_plist" \
  --scripts "$SCRIPTS" \
  --identifier "$PKG_IDENTIFIER" \
  --version "$VERSION" \
  --install-location / \
  --ownership recommended \
  "$comp"

echo "=== productbuild (signed distribution) ==="
/usr/bin/productbuild \
  --package "$comp" \
  --identifier "$PKG_IDENTIFIER" \
  --version "$VERSION" \
  --sign "$INSTALLER_ID" \
  "$OUT"

echo "=== verify signature ==="
/usr/sbin/pkgutil --check-signature "$OUT" | head -6

echo "PKG_BUILT: $OUT"
echo "sha256: $(/usr/bin/shasum -a 256 "$OUT" | awk '{print $1}')"
