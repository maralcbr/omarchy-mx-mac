#!/bin/bash
# Launch the installer UI in the debug-only preview (mock) mode, which
# simulates a complete run by replaying the recorded M1 fresh-install
# journal through the real trust-core decoder. No download, helper,
# privileged request, or disk operation happens in this mode, and release
# builds do not contain the preview branch at all.
#
# Usage: Development/run-ui-preview.sh [scenario] [journal-path]
set -euo pipefail

package_root=$(cd "$(dirname "$0")/.." && pwd)
scenario=${1:-fresh-install}
journal=${2:-$package_root/../../evidence/apple-silicon/2026-08-29-m1-fresh-install-v6/execution-journal.jsonl}

# An unknown scenario string would make the factory fall back to the LIVE
# environment, so refuse anything not in the preview list.
case $scenario in
  fresh-install | existing-install | unsupported | credential-reject | recovery-retry | degraded-journal) ;;
  *)
    echo "unknown scenario: $scenario" >&2
    echo "valid scenarios: fresh-install existing-install unsupported credential-reject recovery-retry degraded-journal" >&2
    exit 1
    ;;
esac

if [[ ! -f $journal ]]; then
  echo "journal fixture not found: $journal" >&2
  exit 1
fi

# The app holds a single-instance lease; a second launch quits immediately
# with "refused a duplicate or unsafe launch". Surface that up front.
if pgrep -f OmarchyAppleInstallerApp >/dev/null; then
  echo "an installer instance is already running (its lease blocks new launches):" >&2
  pgrep -fl OmarchyAppleInstallerApp >&2
  echo "quit it first, e.g.: pkill -f OmarchyAppleInstallerApp" >&2
  exit 1
fi

swift build --package-path "$package_root"

OMARCHY_INSTALLER_UI_PREVIEW=$scenario \
  OMARCHY_INSTALLER_UI_PREVIEW_JOURNAL=$journal \
  exec "$package_root/.build/debug/OmarchyAppleInstallerApp"
