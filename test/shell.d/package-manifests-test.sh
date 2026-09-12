#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

for required in omarchy-base omarchy-base-asahi omarchy-other omarchy-other-asahi; do
  [[ -r $ROOT/install/$required.packages ]] || fail "required fork manifest exists: $required"
done

# The ISO builder and the installer read these lists one name per line, and a
# line holding two names or a stray character installs neither. Every
# manifest under install/ gets the same check, so an architecture-specific
# list added beside the base ones is held to it too.
shopt -s nullglob
manifests=("$ROOT"/install/*.packages)
shopt -u nullglob
(( ${#manifests[@]} > 0 )) || fail "package manifests exist under install/"

for manifest in "${manifests[@]}"; do
  [[ -r $manifest ]] || fail "package manifest is readable: $(basename "$manifest")"

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

# The optional transaction manifests are read with IFS='|' by
# omarchy-install-available and the menu guard prelude, so a row is exactly
# one id, one separator, and space-separated names.
for manifest in optional-packages.tsv optional-aur-packages.tsv; do
  columns=2
  [[ $manifest != "optional-aur-packages.tsv" ]] || columns=3
  malformed=$(awk -F '|' -v columns="$columns" '!/^#/ && NF { if (NF != columns || $1 !~ /^install\.[a-z0-9.-]+$/ || $2 !~ /^[a-zA-Z0-9@._+:-]+( [a-zA-Z0-9@._+:-]+)*$/ || (columns == 3 && $3 !~ /^(x86_64|aarch64)( (x86_64|aarch64))*$/)) print FNR ": " $0 }' "$ROOT/install/$manifest")
  [[ -z $malformed ]] || fail "optional manifest fields are valid: $manifest" "$malformed"
  pass "optional manifest fields are valid: $manifest"
done

malformed=$(awk '!/^#/ && NF && $0 !~ /^install\.[a-z0-9.-]+$/ { print FNR ": " $0 }' "$ROOT/install/optional-packages-aarch64-required")
[[ -z $malformed ]] ||
  fail "aarch64 baseline rows are menu ids" "$malformed"
pass "aarch64 baseline is well formed"

# The resolver and transaction scripts derive their release-bundle exemption
# from this exact installer line, so it must survive installer edits.
grep -Fq 'expected_packages=(omarchy-keyring omarchy-settings-dev omarchy-dev omarchy-nvim quickshell-git ttf-jetbrains-mono-nerd-basic)' \
  "$ROOT/bin/omarchy-install-asahi-fresh" ||
  fail "fresh installer retains the release bundle package list"
pass "fresh installer retains the release bundle package list"

if grep -Fq 'source_packages=(' "$ROOT/bin/omarchy-install-asahi-fresh"; then
  fail "fresh installer no longer builds packages from source"
fi
pass "fresh installer installs every package from repositories"

for script in packages-resolve packages-install-transaction; do
  [[ -x $ROOT/test/$script ]] || fail "package test script is executable: $script"
done
pass "package test scripts are executable"
