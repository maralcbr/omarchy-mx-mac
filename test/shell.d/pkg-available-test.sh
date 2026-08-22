#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_path="$test_tmp/bin"
mkdir -p "$mock_path"

cat >"$mock_path/pacman" <<'EOF'
#!/bin/bash
if [[ $1 == "-Si" ]]; then
  shift
  for pkg in "$@"; do
    case "$pkg" in
      zed | helix) ;;
      *) exit 1 ;;
    esac
  done
  exit 0
fi
exit 1
EOF
chmod +x "$mock_path/pacman"

helper="$ROOT/bin/omarchy-pkg-available"

PATH="$mock_path:$PATH" "$helper"
pass "repository availability is true of no packages"

PATH="$mock_path:$PATH" "$helper" zed helix
pass "repository availability accepts packages in the sync database"

if PATH="$mock_path:$PATH" "$helper" omazed; then
  fail "repository availability rejects a missing package"
fi
pass "repository availability rejects a missing package"

if PATH="$mock_path:$PATH" "$helper" zed omazed; then
  fail "repository availability requires every named package"
fi
pass "repository availability requires every named package"
