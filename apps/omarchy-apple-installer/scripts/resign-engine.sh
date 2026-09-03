#!/bin/bash
# Produce the notarization-ready engine artifact from a locked engine build.
#
# The locked build (Engine/build-locked-engine.sh) bundles a stock Python
# runtime whose Tk/Tcl frameworks, tkinter, idlelib, turtledemo and static
# linking objects Apple notarization rejects (broken or absent Developer ID
# signatures), and the console installer imports none of them. This is the
# same procedure that produced omarchy.7 from omarchy.6
# (scripts/resign-engine-omarchy7.sh), made reusable: prune those components,
# re-sign every remaining Mach-O with the Developer ID (hardened runtime,
# secure timestamp), and repack under a new, version-bumped name so the
# shipped artifact is never confused with the reproducible locked one.
#
# Usage: resign-engine.sh LOCKED_TARBALL NEW_NAME OUT_DIR
set -euo pipefail
(( $# == 3 )) || { echo "Usage: $0 LOCKED_TARBALL NEW_NAME OUT_DIR" >&2; exit 64; }
SRC=$(cd -- "$(dirname -- "$1")" && pwd -P)/$(basename -- "$1")
NEW_NAME=$2
OUT_DIR=$3
IDENTITY=${OMARCHY_APP_SIGNING_IDENTITY:-"Developer ID Application: MARCELO DE BARROS ALCANTARA (T2C384FJBD)"}
# Resolved before any cd: the entitlements the interpreter and its helper
# executables must keep (see the signing loop below).
ENTITLEMENTS=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../Engine" && pwd -P)/python-executable.entitlements.plist
[[ -f $ENTITLEMENTS ]] || { echo "missing $ENTITLEMENTS" >&2; exit 1; }
[[ -f $SRC ]] || { echo "missing locked tarball: $SRC" >&2; exit 1; }
rm -rf "$OUT_DIR/tree"; mkdir -p "$OUT_DIR/tree"; cd "$OUT_DIR/tree"
tar -xzf "$SRC"
rm -rf \
  Frameworks/Python.framework/Versions/3.13/Frameworks/Tk.framework \
  Frameworks/Python.framework/Versions/3.13/Frameworks/Tcl.framework \
  Frameworks/Python.framework/Versions/3.13/lib/python3.13/config-3.13-darwin \
  Frameworks/Python.framework/Versions/3.13/lib/python3.13/tkinter \
  Frameworks/Python.framework/Versions/3.13/lib/python3.13/idlelib \
  Frameworks/Python.framework/Versions/3.13/lib/python3.13/turtledemo
rm -f Frameworks/Python.framework/Versions/3.13/lib/python3.13/lib-dynload/_tkinter*.so
# Pruning leaves framework-level symlinks (Headers, Tk/Tcl references) pointing
# at nothing; codesign refuses to verify a bundle containing a dangling link,
# so drop them before signing.
find . -type l ! -exec test -e {} \; -delete
echo "pruned unused GUI/static-link components"
# Executables keep the entitlements python.org ships (dyld environment
# variables allowed, library validation disabled, unsigned executable memory,
# Apple Events): the app points the interpreter at the framework inside the
# engine tree through DYLD_FRAMEWORK_PATH, and a hardened-runtime binary
# ignores that variable without the entitlement, then fails to launch because
# its install name is the system /Library/Frameworks path. A plain re-sign
# strips them; omarchy.9 shipped that way and could not start.
count=0
while IFS= read -r -d '' f; do
  if file -b "$f" 2>/dev/null | grep -q "Mach-O"; then
    if file -b "$f" | grep -q "executable"; then
      codesign --force --sign "$IDENTITY" --options runtime --timestamp --entitlements "$ENTITLEMENTS" "$f" 2>/dev/null
    else
      codesign --force --sign "$IDENTITY" --options runtime --timestamp "$f" 2>/dev/null
    fi
    count=$((count + 1))
  fi
done < <(find . -type f -print0)
# Every file is inspected rather than a name/mode filter: the framework's
# top-level "Python" dylib carries neither an extension nor the execute bit
# in the locked build and was skipped by the omarchy.7 filter.
echo "re-signed $count Mach-O files with Developer ID"
# Re-seal the Python framework bundle: its CodeResources still describe the
# binaries as python.org shipped them, so every per-file re-sign above
# invalidated the seal and the framework's own dylib would fail verification.
codesign --force --sign "$IDENTITY" --options runtime --timestamp \
  Frameworks/Python.framework/Versions/3.13
codesign --verify --strict --deep Frameworks/Python.framework/Versions/3.13
echo "re-sealed the Python framework bundle"
invalid=0
while IFS= read -r -d '' f; do
  file -b "$f" 2>/dev/null | grep -q "Mach-O" || continue
  codesign --verify --strict "$f" 2>/dev/null || { echo "  INVALID signature: $f" >&2; invalid=$((invalid + 1)); }
done < <(find . -type f -print0)
(( invalid == 0 )) || { echo "$invalid Mach-O files failed verification" >&2; exit 1; }
echo "all Mach-O signatures verify"
cd "$OUT_DIR"
tar -czf "$NEW_NAME" -C tree .
echo "NEW ENGINE: $OUT_DIR/$NEW_NAME"
echo "size_bytes: $(stat -f %z "$NEW_NAME")"
echo "sha256: $(shasum -a 256 "$NEW_NAME" | awk '{print $1}')"
