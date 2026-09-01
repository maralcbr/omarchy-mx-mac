#!/bin/bash
# Produce engine artifact v0.9.0-omarchy.7 from omarchy.6 for Apple notarization.
#
# Why: Apple notarization rejected the app because the PINNED engine tarball
# bundles a Python runtime with broken/absent Developer ID signatures
# (submission 0fa2c71b, 10 issues: Python dylib, libffi, Tk/Tcl, python.o).
# This is an intentional, version-bumped engine re-release, not silent
# tampering: every change is listed below, the new artifact gets a new name
# and digest, and every pin (build-app.sh, ValidationEngineArtifact.swift,
# catalog) is updated to match in tracked code.
#
# Changes to the engine contents:
#   1. Remove Tk/Tcl frameworks, tkinter, idlelib, turtledemo, and the
#      config-3.13-darwin static-linking objects — the console installer
#      imports none of them, and they are exactly what Apple flagged.
#   2. Re-sign every remaining Mach-O with the owner's Developer ID
#      (hardened runtime + secure timestamp), which Apple requires.
#   3. Repack as installer-v0.9.0-omarchy.7.tar.gz.
set -euo pipefail

IDENTITY="Developer ID Application: MARCELO DE BARROS ALCANTARA (T2C384FJBD)"
SRC=/Users/maralc/dev/omarchy/omarchy-mx-mac-integration/apps/omarchy-apple-installer/Engine/artifacts/installer-v0.9.0-omarchy.6.tar.gz
OUT_DIR=/private/tmp/engine-resign
NEW_NAME=installer-v0.9.0-omarchy.7.tar.gz

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/tree"
cd "$OUT_DIR/tree"
tar -xzf "$SRC"

rm -rf \
  Frameworks/Python.framework/Versions/3.13/Frameworks/Tk.framework \
  Frameworks/Python.framework/Versions/3.13/Frameworks/Tcl.framework \
  Frameworks/Python.framework/Versions/3.13/lib/python3.13/config-3.13-darwin \
  Frameworks/Python.framework/Versions/3.13/lib/python3.13/tkinter \
  Frameworks/Python.framework/Versions/3.13/lib/python3.13/idlelib \
  Frameworks/Python.framework/Versions/3.13/lib/python3.13/turtledemo
rm -f Frameworks/Python.framework/Versions/3.13/lib/python3.13/lib-dynload/_tkinter*.so
echo "pruned unused GUI/static-link components"

count=0
while IFS= read -r -d '' f; do
  if file -b "$f" 2>/dev/null | grep -q "Mach-O"; then
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$f" 2>/dev/null
    count=$((count + 1))
  fi
done < <(find . -type f \( -perm +111 -o -name "*.so" -o -name "*.dylib" -o -name "*.o" -o -name "*.a" \) -print0)
echo "re-signed $count Mach-O files with Developer ID"

echo "verifying a sample of signatures:"
codesign --verify --strict Frameworks/Python.framework/Versions/3.13/bin/python3.13 && echo "  python3.13 OK"
codesign --verify --strict Frameworks/Python.framework/Versions/3.13/Python && echo "  Python dylib OK"

cd "$OUT_DIR"
tar -czf "$NEW_NAME" -C tree .
size=$(stat -f %z "$NEW_NAME")
digest=$(shasum -a 256 "$NEW_NAME" | awk '{print $1}')
echo "NEW ENGINE: $OUT_DIR/$NEW_NAME"
echo "size_bytes: $size"
echo "sha256: $digest"
