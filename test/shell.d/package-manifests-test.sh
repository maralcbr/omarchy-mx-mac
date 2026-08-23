#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

manifests=(
  "$ROOT/install/omarchy-base.packages"
  "$ROOT/install/omarchy-base-asahi.packages"
  "$ROOT/install/omarchy-other.packages"
  "$ROOT/install/omarchy-other-asahi.packages"
)

for manifest in "${manifests[@]}"; do
  [[ -r $manifest ]] || fail "package manifest exists: $(basename "$manifest")"

  malformed=$(awk '{ sub(/#.*/, "") } NF > 1 { print FNR ": " $0 }' "$manifest")
  [[ -z $malformed ]] ||
    fail "manifest lines hold exactly one package name: $(basename "$manifest")" "$malformed"

  invalid=$(awk '{ sub(/#.*/, ""); if (NF == 1 && $1 !~ /^[a-zA-Z0-9_@.+-][a-zA-Z0-9_@.+-]*$/) print FNR ": " $1 }' "$manifest")
  [[ -z $invalid ]] ||
    fail "manifest entries are valid package names: $(basename "$manifest")" "$invalid"

  duplicates=$(awk '{ sub(/#.*/, ""); if (NF == 1) seen[$1]++ } END { for (name in seen) if (seen[name] > 1) print name }' "$manifest")
  [[ -z $duplicates ]] ||
    fail "manifest has no duplicate packages: $(basename "$manifest")" "$duplicates"

  pass "package manifest is well formed: $(basename "$manifest")"
done

# The resolver and transaction scripts derive their release-bundle and
# source-built exemptions from these exact installer lines, so both must
# survive installer edits.
grep -Fq 'expected_packages=(omarchy-keyring omarchy-settings-dev omarchy-dev omarchy-nvim quickshell-git ttf-jetbrains-mono-nerd-basic)' \
  "$ROOT/bin/omarchy-install-asahi-fresh" ||
  fail "fresh installer retains the release bundle package list"
pass "fresh installer retains the release bundle package list"

grep -Fq 'source_packages=(' "$ROOT/bin/omarchy-install-asahi-fresh" ||
  fail "fresh installer retains the source-built package list"
pass "fresh installer retains the source-built package list"

for script in packages-resolve packages-install-transaction; do
  [[ -x $ROOT/test/$script ]] || fail "package test script is executable: $script"
done
pass "package test scripts are executable"
