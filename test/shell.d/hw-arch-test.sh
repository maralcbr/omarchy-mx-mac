#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

hw() {
  local name="$1"
  shift
  PATH="$ROOT/bin:$PATH" "$ROOT/bin/omarchy-hw-$name" "$@"
}

arch=$(OMARCHY_UNAME_M=x86_64 hw arch)
[[ $arch == "x86_64" ]] || fail "x86_64 prints x86_64" "actual: $arch"
pass "x86_64 prints x86_64"

OMARCHY_UNAME_M=x86_64 hw aarch64 && fail "x86_64 is not aarch64" || true
pass "x86_64 is not aarch64"

printf 'apple,j413\n' >"$tmp_dir/compatible"
OMARCHY_UNAME_M=x86_64 OMARCHY_APPLE_COMPATIBLE="$tmp_dir/compatible" hw apple-silicon &&
  fail "x86_64 with an apple DT is not Apple Silicon" || true
pass "x86_64 with an apple DT is not Apple Silicon"

arch=$(OMARCHY_UNAME_M=aarch64 hw arch)
[[ $arch == "aarch64" ]] || fail "aarch64 prints aarch64" "actual: $arch"
pass "aarch64 prints aarch64"

OMARCHY_UNAME_M=aarch64 hw aarch64 || fail "aarch64 detects aarch64"
pass "aarch64 detects aarch64"

OMARCHY_UNAME_M=aarch64 OMARCHY_APPLE_COMPATIBLE="$tmp_dir/missing" hw apple-silicon &&
  fail "aarch64 without apple DT is not Apple Silicon" || true
pass "aarch64 without apple DT is not Apple Silicon"

arch=$(OMARCHY_UNAME_M=arm64 hw arch)
[[ $arch == "aarch64" ]] || fail "arm64 canonicalizes to aarch64" "actual: $arch"
pass "arm64 canonicalizes to aarch64"

OMARCHY_UNAME_M=arm64 hw aarch64 || fail "arm64 detects as aarch64"
pass "arm64 detects as aarch64"

for unsupported in riscv64 armv7l unknown; do
  if arch=$(OMARCHY_UNAME_M="$unsupported" hw arch); then
    fail "unsupported architectures must fail detection" "$unsupported returned: $arch"
  fi
  [[ -z $arch ]] || fail "unsupported architectures print no canonical name" "$arch"
done
pass "unsupported architectures cannot be mistaken for x86_64"

OMARCHY_UNAME_M=aarch64 OMARCHY_APPLE_COMPATIBLE="$tmp_dir/compatible" hw apple-silicon ||
  fail "aarch64 with apple DT is Apple Silicon"
pass "aarch64 with apple DT is Apple Silicon"

# Invoke by absolute path with no bin/ on PATH, the way bootstrap and Quickshell do.
PATH=/usr/bin:/bin OMARCHY_UNAME_M=aarch64 OMARCHY_APPLE_COMPATIBLE="$tmp_dir/compatible" \
  "$ROOT/bin/omarchy-hw-apple-silicon" ||
  fail "Apple Silicon detection works when invoked by absolute path"
pass "Apple Silicon detection works when invoked by absolute path"
