#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
config_dir="$tmp/.config/fastfetch"
config="$config_dir/config.jsonc"
mkdir -p "$config_dir"

run_migration() {
  HOME="$tmp" bash -euo pipefail "$ROOT/migrations/1786922691.sh" >/dev/null
}

printf '%s\n' '"text": "version=$(omarchy-version); echo \"Omarchy Mac $version\""' >"$config"
run_migration
grep -Fq 'echo \"Omarchy Mx Mac $version\"' "$config" || fail "migration updates legacy Mac About branding"
pass "migration updates legacy Mac About branding"

printf '%s\n' '"text": "version=$(omarchy-version) && echo \"Omarchy $version\""' >"$config"
run_migration
grep -Fq 'echo \"Omarchy Mx Mac $version\"' "$config" || fail "migration updates generic About branding"
pass "migration updates generic About branding"

printf '%s\n' '"text": "echo \"My custom system\""' >"$config"
cp "$config" "$tmp/custom"
run_migration
cmp "$config" "$tmp/custom" || fail "migration preserves custom About branding"
pass "migration preserves custom About branding"
