#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tsv="$ROOT/install/optional-packages.tsv"
[[ -r $tsv ]] || fail "optional transaction manifest exists: $(basename "$tsv")"

# The manifest is hand-curated upstream, but its contents must keep matching
# what the recipes really request. Deriving the transactions independently
# turns silent drift between installers and the manifest into a hard failure.
drift_out=$(mktemp)
trap 'rm -f "$drift_out"' EXIT
if ! bash "$ROOT/test/generate-optional-transactions" --check "$tsv" >"$drift_out" 2>&1; then
  detail=$(<"$drift_out")
  fail "optional transaction manifest matches the install recipes" \
    "the manifest drifted from what the installers request:$detail"
fi
pass "optional transaction manifest matches the install recipes"
