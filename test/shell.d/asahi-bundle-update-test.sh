#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

updater="$ROOT/bin/omarchy-update-asahi-bundle"
package_certificate="$ROOT/default/asahi-repository-signing.asc"
[[ -s $package_certificate ]] || fail "Asahi package signing certificate is installed with the runtime"
gpg --batch --show-keys --with-colons "$package_certificate" |
  grep -Fxq 'fpr:::::::::C81AC3E2A99556F9B21D5FEA3DD49BC9F8360BDC:' ||
  fail "Asahi package signing certificate has the pinned primary fingerprint"
grep -Fq 'manifest_format == "2"' "$updater" || fail "Asahi updater consumes manifest format 2"
grep -Fq 'package=*)' "$updater" || fail "Asahi updater consumes canonical package records"
grep -Fq 'channel=*) channel_name=' "$updater" || fail "Asahi updater validates the signed channel name"
grep -Fq 'verify_release_signature "$workdir/channel"' "$updater" ||
  fail "Asahi updater verifies the channel with the release key"
grep -Fq 'verify_package_signature "$workdir/$manifest_name"' "$updater" ||
  fail "Asahi updater verifies the runtime manifest with the package key"
grep -Fq 'verify_package_signature "$archive" "$archive.sig"' "$updater" ||
  fail "Asahi updater verifies package archives with the package key"
if grep -Eq '/proc/swaps|/sys/module/zswap' "$updater"; then
  fail "Asahi bundle updates do not reject Omarchy's active zram configuration"
fi
grep -Fq '/sys/module/zswap/parameters/enabled' "$ROOT/bin/omarchy-install-asahi-fresh" ||
  fail "fresh Asahi installs retain the zswap safety gate"
pass "runtime zram is allowed only outside the fresh-install storage boundary"

audit=$(grep -F 'grep -Eqi' "$updater")
grep -Fq 'systemd/oomd\.conf\.d' <<<"$audit" || fail "Asahi bundle audit still rejects oomd drop-ins"
grep -Fq 'initcpio' <<<"$audit" || fail "Asahi bundle audit still rejects initramfs changes"
! grep -Eq 'zram-generator|omarchy-zswap' <<<"$audit" || fail "Asahi bundle audit accepts the zram drop-in and zswap tmpfile"
pass "Asahi bundle audit accepts memory configuration but not boot or oomd changes"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub_bin="$test_tmp/bin"
assets="$test_tmp/assets"
state="$test_tmp/state"
source_commit=0123456789abcdef0123456789abcdef01234567
package_source_commit=89abcdef0123456789abcdef0123456789abcdef
mkdir -p "$stub_bin" "$assets" "$test_tmp/root/proc/device-tree"
: >"$test_tmp/omarchy-release.gpg"
: >"$test_tmp/asahi-repository-signing.asc"
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
cat >"$stub_bin/omarchy-hw-apple-kernel" <<'SH'
#!/bin/bash
echo linux-asahi
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
args="$*"
output=""
url=""
max_filesize=""
while (($#)); do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --max-filesize) max_filesize="$2"; shift 2 ;;
    http*|file:*) url="$1"; shift ;;
    *) shift ;;
  esac
done
[[ -z ${TEST_CURL_LOG:-} ]] || printf '%s\n' "$url" >>"$TEST_CURL_LOG"
if [[ $url == */pointers/* ]]; then
  [[ -z ${TEST_POINTER_ARGS:-} ]] || printf '%s\n' "$args" >"$TEST_POINTER_ARGS"
  case ${TEST_POINTER:-missing} in
    missing) exit 22 ;;
    unreachable) exit 7 ;;
  esac
  # A streamed body has no length for curl to refuse up front.
  if [[ -n $max_filesize && -z ${TEST_POINTER_STREAMED:-} ]] &&
    (( $(wc -c <"$TEST_ASSETS/$TEST_POINTER") > max_filesize )); then
    exit 63
  fi
  cp "$TEST_ASSETS/$TEST_POINTER" "$output"
elif [[ $url == */releases\?per_page=100 ]]; then
  [[ ${TEST_API:-up} == up ]] || exit 7
  cp "$TEST_ASSETS/releases.json" "$output"
else
  cp "$TEST_ASSETS/${url##*/}" "$output"
fi
SH
cat >"$stub_bin/gpg" <<'SH'
#!/bin/bash
if [[ " $* " == *" --show-keys "* ]]; then
  if [[ $* == *asahi-repository-signing.asc* ]]; then
    echo 'fpr:::::::::C81AC3E2A99556F9B21D5FEA3DD49BC9F8360BDC:'
  else
    echo 'fpr:::::::::5983B1CA32CB778F4D74D24ECFF35022CA5B5959:'
  fi
  exit 0
fi
if [[ " $* " == *" --import "* ]]; then
  exit 0
fi
echo '[GNUPG:] VALIDSIG 5983B1CA32CB778F4D74D24ECFF35022CA5B5959 2026-01-01 0 4 0 1 10 00 5983B1CA32CB778F4D74D24ECFF35022CA5B5959'
SH
cat >"$stub_bin/jq" <<'SH'
#!/bin/bash
echo "${TEST_API_TAG:-asahi-quattro-channel-22}"
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
    OMARCHY_ASAHI_PACKAGE_KEY_FILE="$test_tmp/asahi-repository-signing.asc" \
    OMARCHY_ASAHI_CHANNEL_URL="https://example.test/asahi-quattro-channel" \
    PATH="$stub_bin:$PATH" \
    "$updater" --check
}

run_discovery_check() {
  TEST_ASSETS="$assets" \
    TEST_CURL_LOG="$test_tmp/discovery-curl.log" \
    OMARCHY_ASAHI_TESTING=1 \
    OMARCHY_ASAHI_ROOT="$test_tmp/root" \
    OMARCHY_ASAHI_BUNDLE_STATE="$state" \
    OMARCHY_ASAHI_KEY_FILE="$test_tmp/omarchy-release.gpg" \
    OMARCHY_ASAHI_PACKAGE_KEY_FILE="$test_tmp/asahi-repository-signing.asc" \
    OMARCHY_ASAHI_CHANNEL_POINTER_URL="https://downloads.example.test/pointers/asahi-quattro-channel" \
    OMARCHY_ASAHI_RELEASES_API_URL="https://api.github.test/repos/example/releases?per_page=100" \
    PATH="$stub_bin:$PATH" \
    "$updater" --check
}

printf '%s\n' \
  '[{"draft":false,"prerelease":false,"tag_name":"asahi-quattro-channel-22"}]' \
  >"$assets/releases.json"
write_channel 22 "$source_commit"
run_discovery_check >"$test_tmp/discovery.out"
grep -Fxq 'https://api.github.test/repos/example/releases?per_page=100' "$test_tmp/discovery-curl.log" ||
  fail "versioned channel discovery reads the GitHub releases API"
grep -Fxq 'https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-quattro-channel-22/asahi-quattro-channel' "$test_tmp/discovery-curl.log" ||
  fail "versioned channel discovery downloads the selected signed pointer"
grep -Fq '&page=$page' "$updater" || fail "bundle updater pages through the release listing"
pass "immutable versioned Asahi channels are discovered dynamically"

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

api_users=$(cd "$ROOT" && grep -rlF 'api.github.com' bin | sort)
[[ $api_users == $'bin/omarchy-update-asahi-bundle\nbin/omarchy-update-asahi-repository' ]] ||
  fail "only the bundle updater's fallback and the repository updater read the GitHub API" "$api_users"
grep -Fq 'https://downloads.aicodelabs.com.au/pointers/asahi-quattro-channel' "$updater" ||
  fail "bundle updater reads the published release channel pointer"
pass "installed Macs read the GitHub API only for the bundle fallback and the repository update"

pointer_url="https://downloads.example.test/pointers/asahi-quattro-channel"
api_url="https://api.github.test/repos/example/releases?per_page=100"
other_commit=fedcba9876543210fedcba9876543210fedcba98
newer_commit=2468ace02468ace02468ace02468ace02468ace0
pointer_warning='release channel pointer is malformed; using the GitHub release listing'

write_state() {
  printf 'format=1\nsequence=%s\ntag=asahi-quattro-test\nsource_commit=%s\n' "$2" "$3" >"$1"
}

write_pointer() {
  printf 'format=1\nsequence=%s\ntag=asahi-quattro-channel-%s\n' "$1" "$1" >"$assets/pointer-$1"
}

channel_asset() {
  printf 'https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-quattro-channel-%s/asahi-quattro-channel\n' "$1"
}

run_discovery() {
  TEST_ASSETS="$assets" \
    TEST_CURL_LOG="$test_tmp/curl.log" \
    TEST_POINTER_ARGS="$test_tmp/pointer-args" \
    OMARCHY_ASAHI_TESTING=1 \
    OMARCHY_ASAHI_ROOT="$test_tmp/root" \
    OMARCHY_ASAHI_BUNDLE_STATE="$state" \
    OMARCHY_ASAHI_KEY_FILE="$test_tmp/omarchy-release.gpg" \
    OMARCHY_ASAHI_PACKAGE_KEY_FILE="$test_tmp/asahi-repository-signing.asc" \
    OMARCHY_ASAHI_CHANNEL_POINTER_URL="$pointer_url" \
    OMARCHY_ASAHI_RELEASES_API_URL="$api_url" \
    PATH="$stub_bin:$PATH" \
    "$updater" "$@"
}

# Sets status and leaves stdout, stderr and every fetched URL under $test_tmp.
discover() {
  local name="$1"
  shift
  rm -f "$test_tmp/curl.log" "$test_tmp/pointer-args"
  : >"$test_tmp/curl.log"
  set +e
  run_discovery "$@" >"$test_tmp/$name.out" 2>"$test_tmp/$name.err"
  status=$?
  set -e
}

expect_status() {
  local name="$1" expected="$2" description="$3"
  (( status == expected )) ||
    fail "$description" "status $status, expected $expected: $(cat "$test_tmp/$name.out" "$test_tmp/$name.err")"
}

listing_read() {
  grep -Fxq "$api_url" "$test_tmp/curl.log"
}

for sequence in 1 2 3; do
  write_pointer "$sequence"
done

write_state "$state" 2 "$source_commit"
write_channel 3 "$newer_commit"
TEST_POINTER=pointer-3 TEST_API=down discover pointer-current --check
expect_status pointer-current 0 "a current pointer offers its channel"
grep -Fxq 'Apple Silicon Quattro bundle asahi-quattro-test is available' "$test_tmp/pointer-current.out" ||
  fail "a current pointer offers its channel" "$(cat "$test_tmp/pointer-current.out")"
grep -Fxq "$(channel_asset 3)" "$test_tmp/curl.log" || fail "a current pointer selects its numbered channel release"
! listing_read || fail "a current pointer does not read the GitHub release listing"
[[ ! -s $test_tmp/pointer-current.err ]] || fail "a current pointer is silent" "$(cat "$test_tmp/pointer-current.err")"
for flag in '--proto =https' '--tlsv1.2' '--max-time 20' '--max-filesize 256'; do
  grep -Fq -- "$flag" "$test_tmp/pointer-args" || fail "the pointer is fetched with $flag" "$(cat "$test_tmp/pointer-args")"
done
pass "a current release channel pointer replaces the GitHub release listing"

write_channel 2 "$source_commit"
TEST_POINTER=pointer-2 TEST_API=down discover pointer-up-to-date --check
expect_status pointer-up-to-date 1 "--check reports no update when the pointer names the installed channel"
! listing_read || fail "a pointer at the installed channel does not read the GitHub release listing"
TEST_POINTER=pointer-2 TEST_API=down discover pointer-up-to-date-update
expect_status pointer-up-to-date-update 0 "an update at the pointer's channel is up to date"
grep -Fxq 'Apple Silicon Quattro bundle is up to date' "$test_tmp/pointer-up-to-date-update.out" ||
  fail "an update at the pointer's channel is up to date" "$(cat "$test_tmp/pointer-up-to-date-update.out")"
pass "a pointer at the installed channel is up to date without the GitHub release listing"

write_channel 3 "$newer_commit"
TEST_POINTER=missing TEST_API_TAG=asahi-quattro-channel-3 discover pointer-missing --check
expect_status pointer-missing 0 "a missing pointer falls back to the GitHub release listing"
listing_read || fail "a missing pointer reads the GitHub release listing"
grep -Fxq "$(channel_asset 3)" "$test_tmp/curl.log" || fail "a missing pointer uses the listed channel"
! grep -Fq pointer "$test_tmp/pointer-missing.err" || fail "a missing pointer is not reported" "$(cat "$test_tmp/pointer-missing.err")"
pass "a missing release channel pointer falls back to the GitHub release listing"

TEST_POINTER=unreachable TEST_API=down discover pointer-unreachable --check
expect_status pointer-unreachable 3 "--check reports an unavailable channel when the pointer and listing are unreachable"
grep -Fq "could not download $api_url" "$test_tmp/pointer-unreachable.err" ||
  fail "an unreachable listing is reported" "$(cat "$test_tmp/pointer-unreachable.err")"
TEST_POINTER=unreachable TEST_API=down discover pointer-unreachable-update
expect_status pointer-unreachable-update 3 "an update defers when the pointer and listing are unreachable"
pass "an unreachable pointer and GitHub release listing defer the update"

printf 'format=1\nsequence=3\ntag=asahi-quattro-channel-3\nextra=1\n' >"$assets/malformed-extra-line"
printf 'sequence=3\nformat=1\ntag=asahi-quattro-channel-3\n' >"$assets/malformed-wrong-order"
printf 'format=1\nsequence=3\ntag=asahi-quattro-channel-4\n' >"$assets/malformed-tag-mismatch"
{ printf 'format=1\nsequence=3\ntag=asahi-quattro-channel-3\n'; printf '%0300d\n' 0; } >"$assets/malformed-oversized"
printf 'format=1\nsequence=03\ntag=asahi-quattro-channel-03\n' >"$assets/malformed-leading-zero"
printf 'format=1\nsequence=1234567890\ntag=asahi-quattro-channel-1234567890\n' >"$assets/malformed-ten-digits"
printf 'format=1\r\nsequence=3\r\ntag=asahi-quattro-channel-3\r\n' >"$assets/malformed-crlf"
printf 'format=1\nsequence=3\ntag=asahi-quattro-channel-3\njunk' >"$assets/malformed-trailing-junk"
printf 'format=1\nsequence=3\ntag=asahi-quattro-channel-3\n\0' >"$assets/malformed-trailing-nul"
printf 'format=1\nsequence=3\ntag=asahi-quattro-channel-3' >"$assets/malformed-missing-newline"
: >"$assets/malformed-empty"
for variant in extra-line wrong-order tag-mismatch oversized leading-zero ten-digits crlf trailing-junk \
  trailing-nul missing-newline empty; do
  TEST_POINTER="malformed-$variant" TEST_API_TAG=asahi-quattro-channel-3 discover "malformed-$variant" --check
  expect_status "malformed-$variant" 0 "the $variant pointer falls back to the GitHub release listing"
  grep -Fq "$pointer_warning" "$test_tmp/malformed-$variant.err" ||
    fail "the $variant pointer is reported as malformed" "$(cat "$test_tmp/malformed-$variant.err")"
  listing_read || fail "the $variant pointer reads the GitHub release listing"
done
TEST_POINTER=malformed-oversized TEST_POINTER_STREAMED=1 TEST_API_TAG=asahi-quattro-channel-3 \
  discover malformed-streamed --check
expect_status malformed-streamed 0 "an oversized streamed pointer falls back to the GitHub release listing"
grep -Fq "$pointer_warning" "$test_tmp/malformed-streamed.err" ||
  fail "an oversized streamed pointer is reported as malformed" "$(cat "$test_tmp/malformed-streamed.err")"
pass "a malformed release channel pointer warns and falls back to the GitHub release listing"

behind_warning='release channel pointer (1) is behind this Mac (2)'
TEST_POINTER=pointer-1 TEST_API_TAG=asahi-quattro-channel-3 discover behind-higher --check
expect_status behind-higher 0 "a stale pointer does not hide a newer listed channel"
grep -Fq "$behind_warning" "$test_tmp/behind-higher.err" ||
  fail "a stale pointer is reported" "$(cat "$test_tmp/behind-higher.err")"
listing_read || fail "a stale pointer reads the GitHub release listing"
grep -Fxq "$(channel_asset 3)" "$test_tmp/curl.log" || fail "a stale pointer uses the listed channel"

write_channel 2 "$source_commit"
TEST_POINTER=pointer-1 TEST_API_TAG=asahi-quattro-channel-2 discover behind-equal --check
expect_status behind-equal 1 "a stale pointer and a listing at the installed channel are up to date"
TEST_POINTER=pointer-1 TEST_API_TAG=asahi-quattro-channel-2 discover behind-equal-update
expect_status behind-equal-update 0 "an update with a stale pointer and a current listing is up to date"
grep -Fxq 'Apple Silicon Quattro bundle is up to date' "$test_tmp/behind-equal-update.out" ||
  fail "an update with a stale pointer and a current listing is up to date" "$(cat "$test_tmp/behind-equal-update.out")"

write_channel 1 "$other_commit"
TEST_POINTER=pointer-1 TEST_API_TAG=asahi-quattro-channel-1 discover behind-lower --check
expect_status behind-lower 2 "a lower listed channel is still refused as a rollback"
grep -Fq 'refusing signed release rollback from sequence 2 to 1' "$test_tmp/behind-lower.err" ||
  fail "a lower listed channel explains the refusal" "$(cat "$test_tmp/behind-lower.err")"

TEST_POINTER=pointer-1 TEST_API=down discover behind-unavailable --check
expect_status behind-unavailable 3 "a stale pointer with no listing defers instead of refusing"
grep -Fq 'release channel pointer is behind this Mac and the GitHub release listing is unavailable; nothing changed' \
  "$test_tmp/behind-unavailable.err" || fail "a stale pointer with no listing explains the deferral" "$(cat "$test_tmp/behind-unavailable.err")"
pass "a release channel pointer behind the installed channel defers to the GitHub release listing"

write_state "$state" 1 "$other_commit"
write_state "$state.pending" 3 "$source_commit"
write_channel 3 "$source_commit"
TEST_POINTER=pointer-2 TEST_API_TAG=asahi-quattro-channel-3 discover behind-pending --check
expect_status behind-pending 0 "a pointer behind pending migrations defers to the listing"
grep -Fq 'release channel pointer (2) is behind this Mac (3)' "$test_tmp/behind-pending.err" ||
  fail "a pointer behind pending migrations is reported" "$(cat "$test_tmp/behind-pending.err")"
listing_read || fail "a pointer behind pending migrations reads the GitHub release listing"
grep -Fxq 'Apple Silicon Quattro bundle asahi-quattro-test has pending migrations' "$test_tmp/behind-pending.out" ||
  fail "the listed channel resumes pending migrations" "$(cat "$test_tmp/behind-pending.out")"
rm -f "$state.pending"
pass "a release channel pointer behind pending migrations defers to the GitHub release listing"

write_state "$state" 2 "$source_commit"
write_channel 4 "$newer_commit"
TEST_POINTER=pointer-3 TEST_API_TAG=asahi-quattro-channel-4 discover pointer-sequence --check
expect_status pointer-sequence 2 "a pointer's channel release must carry its own sequence"
grep -Fq 'channel release asahi-quattro-channel-3 carries sequence 4' "$test_tmp/pointer-sequence.err" ||
  fail "a pointer's mismatched channel release explains the refusal" "$(cat "$test_tmp/pointer-sequence.err")"
! listing_read || fail "a signed channel failure after the pointer does not fall back to the GitHub release listing"
TEST_POINTER=missing TEST_API_TAG=asahi-quattro-channel-3 discover listing-sequence --check
expect_status listing-sequence 2 "a listed channel release must carry its own sequence"
grep -Fq 'channel release asahi-quattro-channel-3 carries sequence 4' "$test_tmp/listing-sequence.err" ||
  fail "a listed mismatched channel release explains the refusal" "$(cat "$test_tmp/listing-sequence.err")"
pass "a numbered channel release must carry its own signed sequence"

write_channel 3 "$newer_commit"
OMARCHY_ASAHI_CHANNEL_URL=https://example.test/asahi-quattro-channel-9/asahi-quattro-channel \
  TEST_POINTER=pointer-3 discover override --check
expect_status override 0 "an explicit channel URL keeps working"
[[ $(cat "$test_tmp/curl.log") == $'https://example.test/asahi-quattro-channel-9/asahi-quattro-channel\nhttps://example.test/asahi-quattro-channel-9/asahi-quattro-channel.sig' ]] ||
  fail "an explicit channel URL reads neither the pointer nor the listing" "$(cat "$test_tmp/curl.log")"
OMARCHY_ASAHI_CHANNEL_URL=https://example.test/unpublished/missing-channel \
  TEST_POINTER=pointer-3 discover override-unavailable --check
expect_status override-unavailable 3 "an unreachable explicit channel URL defers"
grep -Fxq 'https://example.test/unpublished/missing-channel' "$test_tmp/curl.log" &&
  (( $(wc -l <"$test_tmp/curl.log") == 1 )) ||
  fail "an unreachable explicit channel URL reads neither the pointer nor the listing" "$(cat "$test_tmp/curl.log")"
pass "an explicit channel URL bypasses the pointer and the GitHub release listing"

mkdir -p \
  "$test_tmp/root/boot/grub" \
  "$test_tmp/root/etc/NetworkManager/conf.d" \
  "$test_tmp/root/sys/module/zswap/parameters"
: >"$test_tmp/root/boot/vmlinuz-linux-asahi"
: >"$test_tmp/root/boot/grub/grub.cfg"
cat >"$test_tmp/root/etc/pacman.conf" <<'EOF'
[asahi-alarm]
[core]
[extra]
[alarm]
[aur]
EOF
printf '%s\n' 'wifi.backend=iwd' >"$test_tmp/root/etc/NetworkManager/conf.d/wifi_backend.conf"
cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
[[ $1 == "-Qq" && $2 == "linux-asahi" ]]
SH
chmod +x "$stub_bin/pacman"

run_update_to_manifest() {
  local curl_log="$1"
  TEST_ASSETS="$assets" \
    TEST_CURL_LOG="$curl_log" \
    OMARCHY_ASAHI_TESTING=1 \
    OMARCHY_ASAHI_ROOT="$test_tmp/root" \
    OMARCHY_ASAHI_BUNDLE_STATE="$state" \
    OMARCHY_ASAHI_KEY_FILE="$test_tmp/omarchy-release.gpg" \
    OMARCHY_ASAHI_PACKAGE_KEY_FILE="$test_tmp/asahi-repository-signing.asc" \
    OMARCHY_ASAHI_CHANNEL_URL="https://example.test/asahi-quattro-channel" \
    OMARCHY_ASAHI_RELEASE_BASE_URL="https://example.test/asahi-quattro-test" \
    PATH="$stub_bin:$PATH" \
    "$updater" --yes
}

cat >"$state" <<EOF
format=1
sequence=1
tag=asahi-quattro-old
source_commit=fedcba9876543210fedcba9876543210fedcba98
EOF
write_channel 2 "$source_commit"

printf '%s\n' 'Filename Type Size Used Priority' '/dev/zram0 partition 1048572 0 100' >"$test_tmp/root/proc/swaps"
printf '%s\n' N >"$test_tmp/root/sys/module/zswap/parameters/enabled"
set +e
run_update_to_manifest "$test_tmp/zram-curl.log" >"$test_tmp/zram.out" 2>"$test_tmp/zram.err"
status=$?
set -e
[[ $status -eq 3 ]] || fail "active zram reaches the immutable manifest download" "status $status: $(cat "$test_tmp/zram.err")"
grep -Fxq 'https://example.test/asahi-quattro-test/asahi-quattro-bundle.manifest' "$test_tmp/zram-curl.log" ||
  fail "active zram is not rejected before the immutable manifest download"
pass "bundle update permits active zram"

printf '%s\n' 'Filename Type Size Used Priority' >"$test_tmp/root/proc/swaps"
printf '%s\n' Y >"$test_tmp/root/sys/module/zswap/parameters/enabled"
set +e
run_update_to_manifest "$test_tmp/zswap-curl.log" >"$test_tmp/zswap.out" 2>"$test_tmp/zswap.err"
status=$?
set -e
[[ $status -eq 3 ]] || fail "active zswap reaches the immutable manifest download" "status $status: $(cat "$test_tmp/zswap.err")"
grep -Fxq 'https://example.test/asahi-quattro-test/asahi-quattro-bundle.manifest' "$test_tmp/zswap-curl.log" ||
  fail "active zswap is not rejected before the immutable manifest download"
pass "bundle update permits active zswap"

manifest_asset=https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-quattro-test/asahi-quattro-bundle.manifest
TEST_POINTER=pointer-2 TEST_API=down discover pointer-install --yes
expect_status pointer-install 3 "an update from the pointer reaches the signed manifest download"
grep -Fxq "$manifest_asset" "$test_tmp/curl.log" || fail "an update from the pointer downloads the signed manifest"
! listing_read || fail "an update from the pointer does not read the GitHub release listing"
pass "an update proceeds with the channel a current pointer names, up to its manifest download"

write_state "$state" 2 "$source_commit"
write_channel 3 "$newer_commit"
TEST_POINTER=pointer-1 TEST_API_TAG=asahi-quattro-channel-3 discover behind-install --yes
expect_status behind-install 3 "an update with a stale pointer reaches the listed manifest download"
listing_read || fail "an update with a stale pointer reads the GitHub release listing"
grep -Fxq "$(channel_asset 3)" "$test_tmp/curl.log" && grep -Fxq "$manifest_asset" "$test_tmp/curl.log" ||
  fail "an update with a stale pointer proceeds with the newer listed channel" "$(cat "$test_tmp/curl.log")"
pass "an update with a stale pointer proceeds with the newer listed channel, up to its manifest download"

cat >"$stub_bin/gpg" <<'SH'
#!/bin/bash
if [[ " $* " == *" --show-keys "* ]]; then
  if [[ $* == *asahi-repository-signing.asc* ]]; then
    echo 'fpr:::::::::C81AC3E2A99556F9B21D5FEA3DD49BC9F8360BDC:'
  else
    echo 'fpr:::::::::5983B1CA32CB778F4D74D24ECFF35022CA5B5959:'
  fi
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

TEST_POINTER=pointer-3 TEST_API_TAG=asahi-quattro-channel-3 discover pointer-signature --check
expect_status pointer-signature 2 "an unsigned channel named by the pointer fails closed"
grep -Fq 'signature verification failed' "$test_tmp/pointer-signature.err" ||
  fail "an unsigned channel named by the pointer explains the refusal" "$(cat "$test_tmp/pointer-signature.err")"
! listing_read || fail "a signature failure after the pointer does not fall back to the GitHub release listing"
pass "a signature failure after the pointer does not fall back to the GitHub release listing"
