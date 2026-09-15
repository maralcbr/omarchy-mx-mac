#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/base-test.sh"
runner=/usr/lib/qt6/bin/qmltestrunner
if [[ ! -x $runner || ! -f /usr/lib/qt6/qml/SddmComponents/qmldir ]]; then
  pass "Qt Quick Test or SDDM unavailable; skipping password UI test"
  exit 0
fi
QT_QPA_PLATFORM=offscreen "$runner" -input "$ROOT/test/fixtures/sddm-password"
