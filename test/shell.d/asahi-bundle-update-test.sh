#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

updater="$ROOT/bin/omarchy-update-asahi-bundle"
grep -Fq 'manifest_format == "2"' "$updater" || fail "Asahi updater consumes manifest format 2"
grep -Fq 'package=*)' "$updater" || fail "Asahi updater consumes canonical package records"
grep -Fq 'channel=*) channel_name=' "$updater" || fail "Asahi updater validates the signed channel name"
if grep -Eq '/proc/swaps|/sys/module/zswap' "$updater"; then
  fail "Asahi bundle updates do not reject Omarchy's active zram configuration"
fi
grep -Fq '/sys/module/zswap/parameters/enabled' "$ROOT/bin/omarchy-install-asahi-fresh" ||
  fail "fresh Asahi installs retain the zswap safety gate"
pass "runtime zram is allowed only outside the fresh-install storage boundary"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub_bin="$test_tmp/bin"
assets="$test_tmp/assets"
state="$test_tmp/state"
source_commit=0123456789abcdef0123456789abcdef01234567
package_source_commit=89abcdef0123456789abcdef0123456789abcdef
mkdir -p "$stub_bin" "$assets" "$test_tmp/root/proc/device-tree"
: >"$test_tmp/omarchy-release.gpg"
printf 'apple,j314s\0apple,arm-platform\0' >"$test_tmp/root/proc/device-tree/compatible"

write_channel() {
  local sequence="$1" source="$2"
  cat >"$assets/asahi-quattro-channel" <<EOF
format=1
channel=asahi-quattro
sequence=$sequence
release_tag=asahi-quattro-test
source_commit=$source
manifest=asahi-quattro-bundle.manifest
manifest_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
EOF
  : >"$assets/asahi-quattro-channel.sig"
}

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$stub_bin/uname" <<'SH'
#!/bin/bash
echo aarch64
SH
cat >"$stub_bin/curl" <<'SH'
#!/bin/bash
output=""
url=""
while (($#)); do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    http*|file:*) url="$1"; shift ;;
    *) shift ;;
  esac
done
cp "$TEST_ASSETS/${url##*/}" "$output"
SH
cat >"$stub_bin/gpg" <<'SH'
#!/bin/bash
if [[ " $* " == *" --show-keys "* ]]; then
  echo 'fpr:::::::::5983B1CA32CB778F4D74D24ECFF35022CA5B5959:'
  exit 0
fi
if [[ " $* " == *" --import "* ]]; then
  exit 0
fi
echo '[GNUPG:] VALIDSIG 5983B1CA32CB778F4D74D24ECFF35022CA5B5959 2026-01-01 0 4 0 1 10 00 5983B1CA32CB778F4D74D24ECFF35022CA5B5959'
SH
cat >"$stub_bin/jq" <<'SH'
#!/bin/bash
exit 1
SH
cat >"$stub_bin/bsdtar" <<'SH'
#!/bin/bash
exit 1
SH
cat >"$stub_bin/vercmp" <<'SH'
#!/bin/bash
echo 0
SH
chmod +x "$stub_bin"/*

run_check() {
  TEST_ASSETS="$assets" \
    OMARCHY_ASAHI_TESTING=1 \
    OMARCHY_ASAHI_ROOT="$test_tmp/root" \
    OMARCHY_ASAHI_BUNDLE_STATE="$state" \
    OMARCHY_ASAHI_KEY_FILE="$test_tmp/omarchy-release.gpg" \
    OMARCHY_ASAHI_CHANNEL_URL="https://example.test/asahi-quattro-channel" \
    PATH="$stub_bin:$PATH" \
    "$updater" --check
}

write_channel 2 "$source_commit"
run_check >"$test_tmp/available.out"
grep -Fxq 'Apple Silicon Quattro bundle asahi-quattro-test is available' "$test_tmp/available.out" ||
  fail "signed Asahi channel reports an available release" "$(cat "$test_tmp/available.out")"
pass "signed Asahi channel reports an available release"

cat >"$state" <<EOF
format=1
sequence=2
tag=asahi-quattro-test
source_commit=$source_commit
package_source_commit=$package_source_commit
EOF
set +e
run_check >"$test_tmp/current.out"
status=$?
set -e
if (( status == 0 )); then
  fail "current Asahi release is not reported as available"
fi
[[ $status -eq 1 ]] || fail "current Asahi release uses the no-update status"
pass "current signed Asahi release is not offered again"

sed -i 's/^package_source_commit=.*/package_source_commit=invalid/' "$state"
set +e
run_check >"$test_tmp/package-source.out" 2>"$test_tmp/package-source.err"
status=$?
set -e
[[ $status -eq 2 ]] || fail "invalid package source state fails closed" "status $status"
grep -Fq 'release state is malformed' "$test_tmp/package-source.err" ||
  fail "invalid package source state explains the refusal" "$(cat "$test_tmp/package-source.err")"
pass "fresh install package source state is validated"
sed -i "s/^package_source_commit=.*/package_source_commit=$package_source_commit/" "$state"

write_channel 1 fedcba9876543210fedcba9876543210fedcba98
set +e
run_check >"$test_tmp/rollback.out" 2>"$test_tmp/rollback.err"
status=$?
set -e
[[ $status -eq 2 ]] || fail "signed rollback fails closed" "status $status"
grep -Fq 'refusing signed release rollback from sequence 2 to 1' "$test_tmp/rollback.err" ||
  fail "signed rollback explains the refusal" "$(cat "$test_tmp/rollback.err")"
pass "signed Asahi release sequence prevents rollback"

write_channel 2 fedcba9876543210fedcba9876543210fedcba98
set +e
run_check >"$test_tmp/reuse.out" 2>"$test_tmp/reuse.err"
status=$?
set -e
[[ $status -eq 2 ]] || fail "release sequence reuse fails closed" "status $status"
grep -Fq 'sequence 2 was reused for different source' "$test_tmp/reuse.err" ||
  fail "release sequence reuse explains the refusal" "$(cat "$test_tmp/reuse.err")"
pass "signed release sequence cannot be rebound to another source"

cat >"$state" <<EOF
format=1
sequence=1
tag=asahi-quattro-old
source_commit=fedcba9876543210fedcba9876543210fedcba98
EOF
cat >"$state.pending" <<EOF
format=1
sequence=2
tag=asahi-quattro-test
source_commit=$source_commit
package_source_commit=$package_source_commit
EOF
write_channel 2 "$source_commit"
run_check >"$test_tmp/pending.out"
grep -Fxq 'Apple Silicon Quattro bundle asahi-quattro-test has pending migrations' "$test_tmp/pending.out" ||
  fail "pending bundle resumes migrations without reinstalling" "$(cat "$test_tmp/pending.out")"
pass "pending signed Asahi release resumes migrations"

write_channel 3 fedcba9876543210fedcba9876543210fedcba98
set +e
run_check >"$test_tmp/pending-newer.out" 2>"$test_tmp/pending-newer.err"
status=$?
set -e
[[ $status -eq 2 ]] || fail "new release cannot leapfrog pending migrations" "status $status"
grep -Fq 'finish pending release sequence 2 before installing sequence 3' "$test_tmp/pending-newer.err" ||
  fail "pending migration refusal explains the blocker" "$(cat "$test_tmp/pending-newer.err")"
pass "new signed release cannot leapfrog pending migrations"
rm -f "$state.pending"

cat >"$stub_bin/gpg" <<'SH'
#!/bin/bash
if [[ " $* " == *" --show-keys "* ]]; then
  echo 'fpr:::::::::5983B1CA32CB778F4D74D24ECFF35022CA5B5959:'
  exit 0
fi
if [[ " $* " == *" --import "* ]]; then
  exit 0
fi
exit 1
SH
set +e
run_check >"$test_tmp/signature.out" 2>"$test_tmp/signature.err"
status=$?
set -e
[[ $status -eq 2 ]] || fail "invalid channel signature fails closed" "status $status"
grep -Fq 'signature verification failed' "$test_tmp/signature.err" ||
  fail "invalid signature explains the refusal" "$(cat "$test_tmp/signature.err")"
pass "unsigned Asahi channel is rejected"
