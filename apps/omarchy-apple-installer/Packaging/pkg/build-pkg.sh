#!/bin/bash
# Build a signed + notarized macOS installer package for the Omarchy Apple
# Silicon installer. The package installs the notarized app to /Applications and
# a system LaunchDaemon to /Library/LaunchDaemons, then loads the daemon in its
# postinstall — so the recipient enters one admin password (the macOS installer
# prompt) and never touches Login Items.
#
# Usage: build-pkg.sh --app <signed .app> --version <x.y.z> --out <output.pkg> \
#          [--plist <daemon plist>]
#
# The system daemon plist is derived from the plist the app embeds
# (Contents/Library/LaunchDaemons), rewriting its bundle-relative BundleProgram
# into an absolute Program under /Applications. Pass --plist only to supply a
# daemon plist that already carries an absolute Program; it is validated the
# same way.
set -euo pipefail

APP="" PLIST="" VERSION="" OUT=""
INSTALLER_ID="Developer ID Installer: MARCELO DE BARROS ALCANTARA (T2C384FJBD)"
PKG_IDENTIFIER="com.omarchy.mx.installer.pkg"
PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$PKG_DIR/scripts"

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
[[ -d "$APP" && -n "$VERSION" && -n "$OUT" ]] || {
  echo "usage: build-pkg.sh --app <app> --version <v> --out <pkg> [--plist <plist>]" >&2
  exit 64
}
[[ -z "$PLIST" || -f "$PLIST" ]] || { echo "build-pkg.sh: --plist is not a file: $PLIST" >&2; exit 64; }

work="$(mktemp -d /tmp/omarchy-pkg.XXXXXX)"
trap 'rm -rf "$work"' EXIT
root="$work/root"
mkdir -p "$root/Applications" "$root/Library/LaunchDaemons"

# Payload: the notarized app and the system daemon plist.
/usr/bin/ditto "$APP" "$root/Applications/$(basename "$APP")"

# Derive the daemon plist from the app's embedded copy (absolute Program under
# /Applications), or validate a supplied one the same way. A daemon whose
# Program is missing, relative, or points at nothing inside the staged app
# cannot be loaded by launchd, so that is a build failure, not a warning.
daemon_plist="$work/com.omarchy.mx.installer.helper.plist"
if [[ -n "$PLIST" ]]; then
  /bin/cp "$PLIST" "$daemon_plist"
else
  "$PKG_DIR/derive-daemon-plist" "$APP" "$daemon_plist" /Applications >/dev/null
fi
prog="$(/usr/bin/plutil -extract Program raw -o - "$daemon_plist" 2>/dev/null || true)"
[[ $prog == /Applications/* ]] || {
  echo "build-pkg.sh: daemon Program must be an absolute path under /Applications (got '${prog:-<missing>}')" >&2
  exit 65
}
[[ -f "$root$prog" ]] || {
  echo "build-pkg.sh: daemon Program does not exist inside the staged app: $prog" >&2
  exit 65
}
/usr/bin/install -m 0644 "$daemon_plist" "$root/Library/LaunchDaemons/com.omarchy.mx.installer.helper.plist"
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
