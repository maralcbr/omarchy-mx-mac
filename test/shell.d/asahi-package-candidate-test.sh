#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
repository=$test_tmp/repository
export GNUPGHOME=$test_tmp/gnupg
mkdir "$repository"
mkdir -m 0700 "$GNUPGHOME"

passphrase=phase-2-candidate-test
commit=1111111111111111111111111111111111111111
tag=asahi-packages-candidate-$commit

gpg --batch --pinentry-mode loopback --passphrase "$passphrase" \
  --quick-generate-key 'Candidate Fixture <candidate@example.invalid>' ed25519 cert 1d >/dev/null 2>&1
primary_fingerprint=$(gpg --batch --list-secret-keys --with-colons |
  awk -F: '$1 == "sec" { primary=1; next } primary && $1 == "fpr" { print $10; exit }')
gpg --batch --pinentry-mode loopback --passphrase "$passphrase" \
  --quick-add-key "$primary_fingerprint" ed25519 sign 1d >/dev/null 2>&1
signing_fingerprint=$(gpg --batch --list-secret-keys --with-colons |
  awk -F: '$1 == "ssb" { subkey=1; next } subkey && $1 == "fpr" { print $10; exit }')
gpg --batch --export "$primary_fingerprint" >"$test_tmp/candidate.gpg"

sign() {
  gpg --batch --yes --pinentry-mode loopback --passphrase "$passphrase" \
    --local-user "$signing_fingerprint!" --detach-sign "$1"
}

for number in $(seq -w 1 21); do
  package=phase-two-package-$number
  metadata=$test_tmp/.PKGINFO
  printf 'pkgname = %s\npkgver = 1.2.%s-1\narch = aarch64\n' "$package" "$number" >"$metadata"
  archive=$repository/$package-1.2.$number-1-aarch64.pkg.tar.zst
  bsdtar -cf "$archive" -C "$test_tmp" .PKGINFO
  sign "$archive"
done

for asset in omarchy.db omarchy.files transaction-clean.log transaction-upgrade.log transaction-repositories.sha256; do
  printf '%s fixture\n' "$asset" >"$repository/$asset"
done
sign "$repository/omarchy.db"
sign "$repository/omarchy.files"

{
  printf 'format=1\n'
  printf 'channel=candidate\n'
  printf 'release_tag=%s\n' "$tag"
  printf 'source_commit=%s\n' "$commit"
  printf 'workflow_run=42\n'
  printf 'runner_arch=aarch64\n'
  printf 'signing_fingerprint=%s\n' "$signing_fingerprint"
  printf 'package_count=21\n'
  index=0
  for archive in "$repository"/*.pkg.tar.zst; do
    ((index += 1))
    metadata=$(bsdtar -xOf "$archive" .PKGINFO)
    package=$(sed -n 's/^pkgname = //p' <<<"$metadata")
    version=$(sed -n 's/^pkgver = //p' <<<"$metadata")
    filename=${archive##*/}
    printf 'package=%s|%s|%s|aarch64|%s|%s|%s.sig|%s\n' \
      "$index" "$package" "$version" "$filename" \
      "$(sha256sum "$archive" | cut -d' ' -f1)" "$filename" \
      "$(sha256sum "$archive.sig" | cut -d' ' -f1)"
  done
  for asset in omarchy.db omarchy.db.sig omarchy.files omarchy.files.sig transaction-clean.log transaction-upgrade.log transaction-repositories.sha256; do
    printf 'asset=%s|%s\n' "$asset" "$(sha256sum "$repository/$asset" | cut -d' ' -f1)"
  done
} >"$repository/CANDIDATE"
sign "$repository/CANDIDATE"
(
  cd "$repository"
  sha256sum -- * >SHA256SUMS
)
descriptor_sha256=$(sha256sum "$repository/CANDIDATE" | cut -d' ' -f1)

"$ROOT/bin/omarchy-pkg-repository-verify-candidate" \
  "$repository" "$tag" "$descriptor_sha256" "$signing_fingerprint" "$test_tmp/candidate.gpg" >/dev/null
pass "exact signed package candidate is accepted"

if "$ROOT/bin/omarchy-pkg-repository-verify-candidate" \
  "$repository" "$tag" "$(printf '0%.0s' {1..64})" "$signing_fingerprint" "$test_tmp/candidate.gpg" >/dev/null 2>&1; then
  fail "candidate verifier accepted the wrong descriptor digest"
fi
pass "candidate descriptor digest is pinned"

if "$ROOT/bin/omarchy-pkg-repository-verify-candidate" \
  "$repository" "$tag" "$descriptor_sha256" "$primary_fingerprint" "$test_tmp/candidate.gpg" >/dev/null 2>&1; then
  fail "candidate verifier accepted the primary fingerprint"
fi
pass "candidate signer must be the exact signing subkey"

printf 'unexpected\n' >"$repository/unexpected"
if "$ROOT/bin/omarchy-pkg-repository-verify-candidate" \
  "$repository" "$tag" "$descriptor_sha256" "$signing_fingerprint" "$test_tmp/candidate.gpg" >/dev/null 2>&1; then
  fail "candidate verifier accepted an unexpected release asset"
fi
pass "candidate release asset inventory is closed"
