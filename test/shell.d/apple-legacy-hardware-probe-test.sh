#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-spi-keyboard.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin"
cat >"$test_tmp/bin/cat" <<'SH'
#!/bin/bash

exit 1
SH
chmod +x "$test_tmp/bin/cat"

if ! PATH="$test_tmp/bin:$PATH" bash -eE -c 'source "$1"' bash "$leaf"; then
  fail "legacy Apple probes tolerate hosts without DMI"
fi

pass "legacy Apple probes tolerate hosts without DMI"
