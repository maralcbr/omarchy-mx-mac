#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Third-party menu plugins (including `omarchy plugin clone omarchy.menu`) are
# loaded by the panel Instantiator. Its model data turns nested arrays into Qt
# sequences, so capability checks must read the registry's manifest, and the
# kind check itself must stay strict.
run_node_test <<'JS'
const fs = require('fs')
const qml = fs.readFileSync(path.join(root, 'shell/shell.qml'), 'utf8')
const panel = qml.slice(qml.indexOf('id: panelEntry'))

assert(
  /readonly property var manifest: shell\.pluginRegistry\.installedPlugins\[pluginId\] \|\| null/.test(panel),
  'panel delegate reads the registry manifest, not Instantiator model data'
)
assert(
  !/readonly property var manifest: modelData\.manifest/.test(panel),
  'panel delegate does not hand model-converted manifests to capability checks'
)
assert(
  /function manifestHasKind\(manifest, kind\) \{\s*return !!manifest && Array\.isArray\(manifest\.kinds\)/.test(qml),
  'manifestHasKind stays strict: a string or Qt sequence never declares a kind'
)
assert(
  /appLibrary: shell\.manifestHasKind\(manifest, "menu"\)/.test(qml),
  'the app-library facade is still granted only to manifests declaring kind menu'
)
JS

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping panel menu capability runtime test"
  exit 0
fi
require_command python3
require_command timeout

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
mkdir "$tmpdir/services"
cp "$ROOT/shell/services/PluginShellApi.qml" "$ROOT/shell/services/PluginAppLibraryApi.qml" "$tmpdir/services/"

# Fill the fixture with the production binding and grant. Node alone cannot
# reproduce Qt's conversion of nested arrays to sequences at a model boundary.
python3 - "$ROOT" "$tmpdir/shell.qml" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
source = (root / "shell/shell.qml").read_text()
fixture = (root / "test/shell.d/fixtures/panel-menu-capability/shell.qml").read_text()
panel = source[source.index("id: panelEntry"):]
replacements = {
    "__PANEL_MANIFEST_BINDING__": re.search(r"readonly property var manifest: [^\n]+", panel).group(),
    "__MANIFEST_HAS_KIND__": re.search(r"function manifestHasKind\([^)]*\) \{.*?\n  \}", source, re.S).group(),
    "__APP_LIBRARY_GRANT__": re.search(r"appLibrary: (shell\.manifestHasKind\(manifest, \"menu\"\).*?),\n", source, re.S).group(1),
}
for marker, code in replacements.items():
    fixture = fixture.replace(marker, code)
Path(sys.argv[2]).write_text(fixture)
PY

# No windows or Wayland services: the fixture runs on Qt's offscreen backend.
if ! env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen \
  timeout 8 quickshell --no-color -p "$tmpdir" >"$tmpdir/log" 2>&1; then
  fail "panel menu capability fixture runs" "$(<"$tmpdir/log")"
fi
if ! grep -q 'PANEL_MENU_OK' "$tmpdir/log"; then
  fail "menu plugins keep their app library across the Qt model boundary" "$(<"$tmpdir/log")"
fi
pass "menu plugins keep their app library across the Qt model boundary"
pass "panels, overlays and plugins missing from the registry get no app library"
