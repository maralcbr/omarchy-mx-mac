#!/bin/bash
# Qt 6.12 adds a Color type to QtQuick. A bare Color in shell QML binds
# that type instead of the qs.Commons palette singleton.
source "$(dirname "$0")/base-test.sh"

bare=()
while IFS= read -r -d '' file; do
  [[ $file == */Commons/Color.qml ]] && continue
  # `$]` is Perl's version number, so the dollars stay escaped inside //.
  perl -0ne 'exit((/(?<![\w.\$])Color\b(?![\w\$]|\s*:(?!:))/s) ? 0 : 1)' "$file"
  status=$?
  if (( status == 0 )); then
    bare+=("${file#"$ROOT"/}")
  elif (( status != 1 )); then
    fail "shell QML qualifies the palette as Commons.Color" "scan failed for ${file#"$ROOT"/} (exit $status)"
  fi
done < <(find "$ROOT/shell" -name '*.qml' -print0)

if (( ${#bare[@]} )); then
  printf '%s\n' "${bare[@]}" >&2
  fail "shell QML qualifies the palette as Commons.Color" "Qt 6.12 QtQuick.Color shadows a bare Color"
fi

pass "shell QML qualifies the palette as Commons.Color"
