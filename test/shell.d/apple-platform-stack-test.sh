#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

contract="$ROOT/install/apple-silicon-platform-stack.json"
verifier="$ROOT/bin/omarchy-apple-platform-stack-verify"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

OMARCHY_PATH="$ROOT" "$verifier" "$contract" >"$test_tmp/valid.out"
grep -Fxq 'Apple Silicon platform contract is valid but not ready' "$test_tmp/valid.out" ||
  fail "Apple platform ownership contract validates without claiming readiness"
pass "Apple platform ownership contract is machine-validatable"

if OMARCHY_PATH="$ROOT" "$verifier" "$contract" "$contract" >/dev/null 2>&1; then
  fail "Apple platform verifier accepts more than one contract"
fi
pass "Apple platform verifier accepts exactly one contract"

if OMARCHY_PATH="$ROOT" "$verifier" --require-ready "$contract" >"$test_tmp/ready.out" 2>"$test_tmp/ready.err"; then
  fail "Apple platform contract must not claim physical-install readiness"
fi
for blocker in signed-engine-artifact-absent apple-live-media-build-unverified bootaa64-assembly-unverified platform-stack-transaction-unverified physical-install-evidence-absent; do
  grep -Fxq -- "- $blocker" "$test_tmp/ready.err" || fail "readiness output includes $blocker"
done
pass "Apple platform readiness gate names every unresolved blocker"

jq '.engine_artifact.sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
  "$contract" >"$test_tmp/changed-engine.json"
if OMARCHY_PATH="$ROOT" "$verifier" "$test_tmp/changed-engine.json" >/dev/null 2>&1; then
  fail "Apple platform contract accepts a changed engine artifact"
fi
pass "Apple platform contract binds the reproducible engine artifact"

jq '.engine_artifact.source_lock_sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
  "$contract" >"$test_tmp/changed-source-lock.json"
if OMARCHY_PATH="$ROOT" "$verifier" "$test_tmp/changed-source-lock.json" >/dev/null 2>&1; then
  fail "Apple platform contract accepts a changed source lock"
fi
pass "Apple platform contract binds the engine source lock"

jq '.target.boot_backend = "limine"' "$contract" >"$test_tmp/limine.json"
if OMARCHY_PATH="$ROOT" "$verifier" "$test_tmp/limine.json" >/dev/null 2>&1; then
  fail "Apple platform contract rejects Limine"
fi
pass "Apple platform contract fixes the Asahi GRUB boot boundary"

jq '.components |= map(select(.id != "machine-firmware"))' "$contract" >"$test_tmp/missing.json"
if OMARCHY_PATH="$ROOT" "$verifier" "$test_tmp/missing.json" >/dev/null 2>&1; then
  fail "Apple platform contract rejects an incomplete stack"
fi
pass "Apple platform contract requires every platform component"

jq '.readiness.ready = true | .readiness.blockers = []' "$contract" >"$test_tmp/false-ready.json"
if OMARCHY_PATH="$ROOT" "$verifier" "$test_tmp/false-ready.json" >/dev/null 2>&1; then
  fail "Apple platform contract rejects readiness with blocked components"
fi
pass "Apple platform contract cannot bypass component gates"

jq '(.components[] | select(.id == "asahi-kernel") | .packages) += ["not-in-package-manifest"]' \
  "$contract" >"$test_tmp/unlinked-package.json"
if OMARCHY_PATH="$ROOT" "$verifier" "$test_tmp/unlinked-package.json" >/dev/null 2>&1; then
  fail "Apple platform contract rejects an unlinked Omarchy package"
fi
pass "Apple platform contract links Omarchy-owned packages to the shipped closure"

for package in asahi-audio asahi-fwextract asahi-scripts grub linux-asahi \
  linux-asahi-headers m1n1 speakersafetyd uboot-asahi; do
  grep -Fxq "$package" "$ROOT/install/omarchy-base-asahi.packages" ||
    fail "new Apple installs explicitly select $package"
done
! grep -Fxq tiny-dfr "$ROOT/install/omarchy-base-asahi.packages" ||
  fail "tiny-dfr must remain exact-model conditional"
pass "new Apple installs select the complete universal platform transaction"

jq '.release_lifecycle.stage = "preview" |
    .release_lifecycle.public_release_authorized = true |
    .release_lifecycle.preview.readme_install_path = "macos-bridge-to-verified-apple-media"' \
  "$contract" >"$test_tmp/preview-without-evidence.json"
if OMARCHY_PATH="$ROOT" "$verifier" "$test_tmp/preview-without-evidence.json" >/dev/null 2>&1; then
  fail "Apple platform contract permits preview before physical evidence"
fi
pass "README cutover and preview publication remain gated on physical evidence"

jq '.release_lifecycle.removal.mode = "delete-release-and-assets"' \
  "$contract" >"$test_tmp/destructive-removal.json"
if OMARCHY_PATH="$ROOT" "$verifier" "$test_tmp/destructive-removal.json" >/dev/null 2>&1; then
  fail "Apple platform contract permits destructive release-lineage removal"
fi
pass "release removal must archive and preserve recovery lineage"

jq '.release_lifecycle.rollback.action = "reuse-old-sequence"' \
  "$contract" >"$test_tmp/rollback-reuse.json"
if OMARCHY_PATH="$ROOT" "$verifier" "$test_tmp/rollback-reuse.json" >/dev/null 2>&1; then
  fail "Apple platform contract permits rollback sequence reuse"
fi
pass "rollback uses a higher signed sequence and cannot bypass anti-rollback"

jq '.release_lifecycle.stage = "retired" |
    .release_lifecycle.physical_allowlist = [{
      device_tree: "apple,j314s",
      evidence_revision: "physical-1",
      evidence_sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      catalog_sequence: 1,
      matrix_complete: true,
      matrix: {
        install: true, reboot: true, macos_coexistence: true, recovery: true,
        updates: true, rollback: true, display: true, keyboard: true,
        touchpad: true, storage: true, wifi: true, audio: true,
        brightness: true, suspend: false, power_management: true
      }
    }]' "$contract" >"$test_tmp/false-matrix-complete.json"
if OMARCHY_PATH="$ROOT" "$verifier" "$test_tmp/false-matrix-complete.json" >/dev/null 2>&1; then
  fail "Apple platform contract accepts matrix_complete with a failed capability"
fi
pass "physical matrix completion is derived from every named capability"

[[ $(jq -r '.release_lifecycle.stage' "$contract") == "development" ]] ||
  fail "current Apple release lifecycle remains in development"
grep -Fq '### 1. Install Asahi Arch Minimal' "$ROOT/README.md" ||
  fail "development README must retain the currently supported installation path"
grep -Fq 'Only at this gate may the' "$ROOT/docs/apple-silicon-release-lifecycle.md" ||
  fail "release lifecycle must name the gated README cutover"
pass "current README stays truthful until the physical preview gate"
