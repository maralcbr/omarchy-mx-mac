#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command sha256sum

updater="$ROOT/bin/omarchy-update-asahi-repository"
bundle_updater="$ROOT/bin/omarchy-update-asahi-bundle"
update="$ROOT/bin/omarchy-update"
update_available="$ROOT/bin/omarchy-update-available"
certificate="$ROOT/default/omarchy-arm-repository.asc"
release_certificate="$ROOT/default/omarchy-release.gpg"
primary_fingerprint=C81AC3E2A99556F9B21D5FEA3DD49BC9F8360BDC
subkey_fingerprint=CAB18E175BFB9ACCE185234474DE0C737AC186E4
release_fingerprint=5983B1CA32CB778F4D74D24ECFF35022CA5B5959
repo=maralcbr/omarchy-pkgs

[[ -s $certificate ]] || fail "Omarchy ARM repository certificate ships with the runtime"
[[ -s $release_certificate ]] || fail "Omarchy release certificate ships with the runtime"
if command -v gpg >/dev/null; then
  colons=$(gpg --batch --show-keys --with-colons "$certificate" 2>/dev/null || true)
  grep -Fxq "fpr:::::::::$primary_fingerprint:" <<<"$colons" ||
    fail "Omarchy ARM repository certificate has the pinned primary fingerprint"
  grep -Fxq "fpr:::::::::$subkey_fingerprint:" <<<"$colons" ||
    fail "Omarchy ARM repository certificate carries the pinned signing subkey"
  gpg --batch --show-keys --with-colons "$release_certificate" 2>/dev/null |
    grep -Fxq "fpr:::::::::$release_fingerprint:" ||
    fail "Omarchy release certificate has the pinned release fingerprint"
fi
grep -Fq "trusted_subkey=$subkey_fingerprint" "$updater" || fail "repository updater pins the signing subkey"
grep -Fq '$2 == "VALIDSIG" && $3 == key' "$updater" || fail "repository updater requires the descriptor signature from the subkey itself"
grep -Fq "release_trusted_key=$release_fingerprint" "$updater" || fail "repository updater pins the release key for the package channel"
grep -Fq 'release_trusted_key_file="${OMARCHY_ASAHI_KEY_FILE:-/usr/share/omarchy/default/omarchy-release.gpg}"' "$updater" ||
  fail "repository updater reads the release key the bundle updater reads"
grep -Fq 'verify_release_signature "$channel_file" "$channel_file.sig"' "$updater" ||
  fail "repository updater verifies the package channel with the release key"
grep -Fq 'https://downloads.aicodelabs.com.au/pointers/asahi-packages-channel' "$updater" ||
  fail "repository updater reads the published package channel pointer"
grep -Fq '# omarchy:hidden=true' "$updater" || fail "repository updater is hidden from command listings"
grep -Fq '# omarchy:requires-sudo=true' "$updater" || fail "repository updater declares its sudo requirement"
! grep -Eq 'installed_run|workflow_run >=' "$updater" || fail "repository updater does not order snapshots by workflow run"
grep -Fq 'omarchy-update-asahi-repository --yes' "$update" || fail "normal updates repoint the Apple Silicon package repository"
grep -Fq 'repository_status == 3' "$update" || fail "repository listing outages do not block platform package updates"
awk '/omarchy-update-asahi-repository --yes/ { seen = 1 } seen && /omarchy-update-system-pkgs([^-]|$)/ { ordered = 1 } END { exit !ordered }' "$update" ||
  fail "the repository is repointed before the system package upgrade"
grep -Fq 'omarchy-update-asahi-repository' "$update_available" || fail "availability checks include the package repository"
# A failed repoint leaves the previous signed snapshot pinned, which still
# installs, so it must not take the whole system update down with it.
awk '/repository_status != 0/ { getline; if ($0 ~ /exit/) exit 1 } END { exit 0 }' "$update" ||
  fail "a failed repository repoint continues to the package upgrade"
grep -Fq 'continuing with the pinned snapshot' "$update" ||
  fail "a failed repository repoint says the pinned snapshot is still in use"
grep -Fq '&page=$page' "$updater" || fail "repository updater pages through the release listing fallback"
pass "Apple Silicon package repository updates are wired into the update flow"

api_lines=$(cd "$ROOT" && grep -rnF 'api.github.com' bin | sort)
(( $(wc -l <<<"$api_lines") == 2 )) || fail "only the two documented listing fallbacks in bin/ read the GitHub API" "$api_lines"
for command in "$bundle_updater" "$updater"; do
  api_line=$(grep -nF 'api.github.com' "$command" || true)
  grep -Fq 'releases_api_url="${OMARCHY_ASAHI_RELEASES_API_URL:-https://api.github.com/repos/$repo/releases?per_page=100}"' <<<"$api_line" ||
    fail "$(basename "$command") reads the GitHub API only as its release listing fallback" "$api_lines"
  pointer_line=$(grep -nF 'https://downloads.aicodelabs.com.au/pointers/' "$command" | cut -d: -f1)
  [[ -n $pointer_line ]] && (( pointer_line < ${api_line%%:*} )) ||
    fail "$(basename "$command") tries its R2 pointer before the GitHub API"
done
pass "installed Macs read the GitHub API only as the fallback behind the bundle and package channel pointers"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub_bin="$test_tmp/bin"
assets="$test_tmp/assets"
state="$test_tmp/state"
calls="$test_tmp/calls"
root="$test_tmp/root"
pacman_conf="$root/etc/pacman.conf"
first_commit=0123456789abcdef0123456789abcdef01234567
old_commit=afd72814b7b29dddef2e07c7ed125101de34d4f4
new_commit=901e39bdc0dd42a93644bce14a07eeb9bb18a12c
hand_commit=e7574274c0ffee0123456789abcdef0123456789
legacy_commit=784daa3efaecfa81b5b4da888b524e6ec4574d24
legacy_server="https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-packages-$legacy_commit"
old_tag="asahi-packages-stable-$old_commit"
new_tag="asahi-packages-stable-$new_commit"
pointer_url="https://downloads.example.test/pointers/asahi-packages-channel"
api_url="https://api.github.test/repos/example/releases?per_page=100"
mkdir -p "$stub_bin" "$assets/pointers" "$assets/listings" "$assets/other" "$root/etc/pacman.d" "$root/proc/device-tree"
: >"$test_tmp/omarchy-arm-repository.asc"
: >"$test_tmp/omarchy-release.gpg"
printf 'apple,j314s\0apple,arm-platform\0' >"$root/proc/device-tree/compatible"

write_pacman_conf_server() {
  local server="$1"
  cat >"$pacman_conf" <<CONF
[options]
Architecture = aarch64
SigLevel = Required DatabaseOptional

[asahi-alarm]
Server = https://github.com/asahi-alarm/asahi-alarm/releases/download/\$arch

[omarchy]
SigLevel = Required DatabaseOptional
Server = $server

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[alarm]
Include = /etc/pacman.d/mirrorlist

[aur]
Include = /etc/pacman.d/mirrorlist
CONF
  printf 'Server = http://mirror.archlinuxarm.org/$arch/$repo\n' >"$root/etc/pacman.d/mirrorlist"
}

write_pacman_conf() {
  write_pacman_conf_server "https://github.com/$repo/releases/download/$1"
}

write_descriptor() {
  local commit="$1" workflow_run="$2" release_dir
  release_dir="$assets/asahi-packages-stable-$commit"
  mkdir -p "$release_dir"
  printf 'omarchy database for %s\n' "$commit" >"$release_dir/omarchy.db"
  printf 'signature\n' >"$release_dir/omarchy.db.sig"
  cat >"$release_dir/CANDIDATE" <<EOF
format=1
channel=candidate
release_tag=asahi-packages-candidate-$commit
source_commit=$commit
workflow_run=$workflow_run
runner_arch=aarch64
signing_fingerprint=$subkey_fingerprint
package_count=2
asset=omarchy.db|$(sha256sum "$release_dir/omarchy.db" | cut -d' ' -f1)
asset=omarchy.db.sig|$(sha256sum "$release_dir/omarchy.db.sig" | cut -d' ' -f1)
asset=omarchy.files|$(printf '%064d' 1)
asset=omarchy.files.sig|$(printf '%064d' 2)
package=1|aether|4.27.2-1|aarch64|aether-4.27.2-1-aarch64.pkg.tar.zst|$(printf '%064d' 3)|aether-4.27.2-1-aarch64.pkg.tar.zst.sig|$(printf '%064d' 4)
package=2|yay|12.6.0-1|aarch64|yay-12.6.0-1-aarch64.pkg.tar.zst|$(printf '%064d' 5)|yay-12.6.0-1-aarch64.pkg.tar.zst.sig|$(printf '%064d' 6)
EOF
  printf 'signature\n' >"$release_dir/CANDIDATE.sig"
}

descriptor_digest() {
  sha256sum "$assets/asahi-packages-stable-$1/CANDIDATE" | cut -d' ' -f1
}

# Writes a signed channel body; the directory defaults to the numbered release.
write_channel() {
  local sequence="$1" commit="$2" supersedes="$3" dir="${4:-$assets/asahi-packages-channel-$1}" descriptor="${5:-}"
  [[ -n $descriptor ]] || descriptor=$(descriptor_digest "$commit")
  mkdir -p "$dir"
  printf 'format=1\nchannel=asahi-packages\nsequence=%s\nstable_tag=asahi-packages-stable-%s\ndescriptor_sha256=%s\nsupersedes=%s\n' \
    "$sequence" "$commit" "$descriptor" "$supersedes" >"$dir/asahi-packages-channel"
  printf 'signature\n' >"$dir/asahi-packages-channel.sig"
}

write_pointer() {
  printf 'format=1\nsequence=%s\ntag=asahi-packages-channel-%s\n' "$1" "$1" >"$assets/pointers/pointer-$1"
}

write_state() {
  local commit="$1" sequence="${2:-}" descriptor="${3:-}"
  [[ -n $descriptor ]] || descriptor=$(descriptor_digest "$commit")
  printf 'format=1\ntag=asahi-packages-stable-%s\nsource_commit=%s\nworkflow_run=33000000000\ndescriptor_sha256=%s\n' \
    "$commit" "$commit" "$descriptor" >"$state"
  [[ -z $sequence ]] || printf 'channel_sequence=%s\n' "$sequence" >>"$state"
}

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 0
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
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
printf '%s\n' "$url" >>"$TEST_CURL_LOG"
[[ ${TEST_CURL_OFFLINE:-0} != 1 ]] || exit 7
case $url in
  */pointers/*)
    printf '%s\n' "$args" >"$TEST_POINTER_ARGS"
    case ${TEST_POINTER:-missing} in
      missing) exit 22 ;;
      unreachable) exit 7 ;;
    esac
    source="$TEST_ASSETS/pointers/$TEST_POINTER"
    ;;
  *"releases?per_page=100"*)
    case ${TEST_API:-forbidden} in
      forbidden) printf '%s\n' "$url" >>"$TEST_API_HITS"; exit 7 ;;
      down) exit 7 ;;
    esac
    page=1
    [[ $url != *"&page="* ]] || page=${url##*&page=}
    source="$TEST_ASSETS/listings/${TEST_LISTING:-channels}-$page.json"
    [[ -f $source ]] || source="$TEST_ASSETS/listings/empty.json"
    ;;
  https://github.com/maralcbr/omarchy-pkgs/releases/download/*)
    source="$TEST_ASSETS/${url#https://github.com/maralcbr/omarchy-pkgs/releases/download/}"
    ;;
  *)
    source="$TEST_ASSETS/other/${url#https://}"
    ;;
esac
[[ -f $source ]] || exit 22
# A streamed body has no length for curl to refuse up front.
if [[ -n $max_filesize && -z ${TEST_STREAMED:-} ]] && (( $(wc -c <"$source") > max_filesize )); then
  exit 63
fi
cp "$source" "$output"
SH
cat >"$stub_bin/gpg" <<'SH'
#!/bin/bash
primary=C81AC3E2A99556F9B21D5FEA3DD49BC9F8360BDC
subkey=CAB18E175BFB9ACCE185234474DE0C737AC186E4
release=5983B1CA32CB778F4D74D24ECFF35022CA5B5959
if [[ " $* " == *" --show-keys "* ]]; then
  if [[ $* == *omarchy-release.gpg* ]]; then
    printf 'pub:-:255:22:%s:::::::scESC::::::::0:\nfpr:::::::::%s:\n' "${release:24}" "$release"
  else
    printf 'pub:-:255:22:%s:::::::cSC::::::::0:\nfpr:::::::::%s:\n' "${primary:24}" "$primary"
  fi
  exit 0
fi
if [[ " $* " == *" --import "* ]]; then
  exit 0
fi
if [[ " $* " == *" --list-keys "* ]]; then
  printf 'pub:-:255:22:%s:::::::cSC::::::::0:\nfpr:::::::::%s:\nsub:-:255:22:%s:::::::s::::::::0:\nfpr:::::::::%s:\n' \
    "${primary:24}" "$primary" "${subkey:24}" "$subkey"
  exit 0
fi
file=${!#}
if [[ $(basename "$file") == asahi-packages-channel ]]; then
  [[ ${TEST_CHANNEL_GPG_FAIL:-0} != 1 ]] || exit 1
  signer=$release
  [[ ${TEST_CHANNEL_SIGNER:-release} == "release" ]] || signer=$primary
  echo "[GNUPG:] VALIDSIG $signer 2026-01-01 0 4 0 1 22 00 $signer"
  exit 0
fi
[[ ${TEST_GPG_FAIL:-0} != 1 ]] || exit 1
signer=$subkey
[[ ${TEST_GPG_SIGNER:-subkey} == "subkey" ]] || signer=$primary
echo "[GNUPG:] VALIDSIG $signer 2026-01-01 0 4 0 1 22 00 $primary"
SH
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$TEST_CALLS"
if [[ $1 == "env" ]]; then
  shift
  while [[ $1 == *=* ]]; do export "$1"; shift; done
fi
exec "$@"
SH
cat >"$stub_bin/install" <<'SH'
#!/bin/bash
args=()
while (($#)); do
  case "$1" in
    -o|-g) shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
exec /usr/bin/install "${args[@]}"
SH
cat >"$stub_bin/pacman-key" <<'SH'
#!/bin/bash
printf 'pacman-key:%s\n' "$*" >>"$TEST_CALLS"
if [[ $1 == "--finger" ]]; then
  [[ -f $TEST_KEY_STATE ]]
elif [[ $1 == "--add" ]]; then
  : >"$TEST_KEY_STATE"
fi
SH
cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
printf 'pacman:%s OMARCHY_UPDATE_PACMAN=%s\n' "$*" "${OMARCHY_UPDATE_PACMAN:-}" >>"$TEST_CALLS"
[[ ${TEST_PACMAN_FAIL:-0} != 1 ]]
SH
cat >"$stub_bin/gum" <<'SH'
#!/bin/bash
echo "gum must not prompt under --yes" >&2
exit 1
SH
chmod +x "$stub_bin"/*

run_updater() {
  TEST_ASSETS="$assets" \
    TEST_CURL_LOG="$test_tmp/curl.log" \
    TEST_POINTER_ARGS="$test_tmp/pointer-args" \
    TEST_API_HITS="$test_tmp/api-hits" \
    TEST_CALLS="$calls" \
    TEST_KEY_STATE="$test_tmp/key-trusted" \
    OMARCHY_ASAHI_TESTING=1 \
    OMARCHY_ASAHI_ROOT="$root" \
    OMARCHY_ASAHI_REPOSITORY_STATE="$state" \
    OMARCHY_ASAHI_PACKAGE_KEY_FILE="$test_tmp/omarchy-arm-repository.asc" \
    OMARCHY_ASAHI_KEY_FILE="$test_tmp/omarchy-release.gpg" \
    OMARCHY_ASAHI_PACKAGES_POINTER_URL="$pointer_url" \
    OMARCHY_ASAHI_RELEASES_API_URL="$api_url" \
    PATH="$stub_bin:$PATH" \
    "$updater" "$@"
}

# Sets status and leaves stdout, stderr, fetched URLs and system calls under $test_tmp.
run() {
  local name="$1"
  shift
  : >"$test_tmp/curl.log"
  : >"$calls"
  rm -f "$test_tmp/api-hits" "$test_tmp/pointer-args"
  set +e
  run_updater "$@" >"$test_tmp/$name.out" 2>"$test_tmp/$name.err"
  status=$?
  set -e
}

expect_status() {
  local name="$1" expected="$2" description="$3"
  (( status == expected )) ||
    fail "$description" "status $status, expected $expected: $(cat "$test_tmp/$name.out" "$test_tmp/$name.err")"
}

fetched() {
  grep -Fxq "$1" "$test_tmp/curl.log"
}

listing_read() {
  grep -Fq "$api_url" "$test_tmp/curl.log"
}

channel_asset() {
  printf 'https://github.com/%s/releases/download/asahi-packages-channel-%s/asahi-packages-channel\n' "$repo" "$1"
}

candidate_asset() {
  printf 'https://github.com/%s/releases/download/asahi-packages-stable-%s/CANDIDATE\n' "$repo" "$1"
}

no_system_changes() {
  local description="$1" state_before="${2:-absent}"
  [[ ! -s $calls ]] || fail "$description: nothing is run as root" "$(cat "$calls")"
  if [[ $state_before == absent ]]; then
    [[ ! -e $state ]] || fail "$description: no repository state is written" "$(cat "$state")"
  else
    [[ $(sha256sum "$state" | cut -d' ' -f1) == "$state_before" ]] || fail "$description: repository state is untouched" "$(cat "$state")"
  fi
}

state_digest() {
  sha256sum "$state" | cut -d' ' -f1
}

write_descriptor "$first_commit" 32000000000
write_descriptor "$old_commit" 33000000000
write_descriptor "$new_commit" 33487927893
write_descriptor "$hand_commit" 34000000000
write_channel 1 "$first_commit" ""
write_channel 2 "$old_commit" "$first_commit"
write_channel 3 "$new_commit" "$first_commit,$old_commit"
for sequence in 1 2 3 4; do
  write_pointer "$sequence"
done
echo '[]' >"$assets/listings/empty.json"
cat >"$assets/listings/channels-1.json" <<EOF
[
  {"tag_name":"asahi-packages-channel-9","draft":true,"prerelease":false},
  {"tag_name":"asahi-packages-channel-8","draft":false,"prerelease":true},
  {"tag_name":"asahi-packages-channel-03","draft":false,"prerelease":false},
  {"tag_name":"asahi-quattro-channel-40","draft":false,"prerelease":false},
  {"tag_name":"asahi-packages-stable-ffffffffffffffffffffffffffffffffffffffff","draft":false,"prerelease":false,"immutable":true},
  {"tag_name":"asahi-packages-channel-2","draft":false,"prerelease":false},
  {"tag_name":"asahi-packages-channel-3","draft":false,"prerelease":false},
  {"tag_name":"asahi-packages-channel-1","draft":false,"prerelease":false}
]
EOF
cat >"$assets/listings/stable-only-1.json" <<EOF
[
  {"tag_name":"$new_tag","draft":false,"prerelease":false,"immutable":true},
  {"tag_name":"asahi-quattro-channel-40","draft":false,"prerelease":false,"immutable":true}
]
EOF
jq -n '[range(100) | {tag_name: "asahi-quattro-channel-\(. + 1)", draft: false, prerelease: false}]' >"$assets/listings/paged-1.json"
cp "$assets/listings/channels-1.json" "$assets/listings/paged-2.json"

write_pacman_conf "$old_tag"
TEST_POINTER=pointer-3 run pointer-check --check
expect_status pointer-check 0 "a pointer to a channel that supersedes the pinned snapshot offers it"
grep -Fxq "Apple Silicon package repository $new_tag is available" "$test_tmp/pointer-check.out" ||
  fail "availability names the stable snapshot the channel names" "$(cat "$test_tmp/pointer-check.out")"
[[ ! -e $test_tmp/api-hits ]] || fail "a current pointer never reads the GitHub API" "$(cat "$test_tmp/api-hits")"
fetched "$(channel_asset 3)" && fetched "$(channel_asset 3).sig" || fail "the pointer's numbered channel release is downloaded with its signature"
fetched "$(candidate_asset "$new_commit")" && fetched "$(candidate_asset "$new_commit").sig" ||
  fail "the descriptor the channel names is downloaded with its signature"
! grep -Fq 'omarchy.db' "$test_tmp/curl.log" || fail "availability checks do not download the repository database"
[[ ! -s $test_tmp/pointer-check.err ]] || fail "a current pointer is silent" "$(cat "$test_tmp/pointer-check.err")"
for flag in '--proto =https' '--tlsv1.2' '--max-time 20' '--max-filesize 256'; do
  grep -Fq -- "$flag" "$test_tmp/pointer-args" || fail "the pointer is fetched with $flag" "$(cat "$test_tmp/pointer-args")"
done
no_system_changes "an availability check"
pass "a package channel pointer replaces the GitHub release listing"

TEST_POINTER=missing TEST_API=up run listing-check --check
expect_status listing-check 0 "a missing pointer falls back to the GitHub release listing"
listing_read || fail "a missing pointer reads the GitHub release listing"
fetched "$(channel_asset 3)" || fail "the listing picks the highest published channel" "$(cat "$test_tmp/curl.log")"
[[ ! -s $test_tmp/listing-check.err ]] || fail "a missing pointer is not reported" "$(cat "$test_tmp/listing-check.err")"
TEST_POINTER=missing TEST_API=up TEST_LISTING=paged run listing-paged --check
expect_status listing-paged 0 "a channel past a full first page is still found"
fetched "$api_url&page=2" && fetched "$(channel_asset 3)" || fail "the listing pages until a page holds a channel" "$(cat "$test_tmp/curl.log")"
pass "drafts, prereleases, runtime channels and snapshots are ignored in favour of the highest listed package channel"

TEST_POINTER=pointer-3 run pointer-yes --yes
expect_status pointer-yes 0 "an update follows the pointer"
[[ ! -e $test_tmp/api-hits ]] || fail "an update from the pointer never reads the GitHub API"
grep -Fxq "Server = https://github.com/$repo/releases/download/$new_tag" "$pacman_conf" || fail "an update from the pointer repoints [omarchy]"
write_pacman_conf "$old_tag"
rm -f "$state"
pass "an update follows the package channel pointer without the GitHub API"

TEST_POINTER=unreachable TEST_API=down run unreachable-check --check
expect_status unreachable-check 3 "an unreachable pointer and listing defer the check"
grep -Fq "could not download $api_url" "$test_tmp/unreachable-check.err" ||
  fail "an unreachable listing is reported" "$(cat "$test_tmp/unreachable-check.err")"
TEST_POINTER=unreachable TEST_API=down run unreachable-yes --yes
expect_status unreachable-yes 3 "an unreachable pointer and listing defer the update"
no_system_changes "a deferred update"
TEST_CURL_OFFLINE=1 run offline --check
expect_status offline 3 "an offline Mac defers"
TEST_POINTER=pointer-4 run missing-channel --check
expect_status missing-channel 3 "a pointer naming an unpublished channel defers"
grep -Fq "could not download $(channel_asset 4)" "$test_tmp/missing-channel.err" ||
  fail "an unpublished channel is reported" "$(cat "$test_tmp/missing-channel.err")"
TEST_POINTER=missing TEST_API=up TEST_LISTING=stable-only run no-channel-check --check
expect_status no-channel-check 3 "a listing without package channels defers the check"
grep -Fq 'could not discover a signed Apple Silicon package channel' "$test_tmp/no-channel-check.err" ||
  fail "a listing without package channels is reported" "$(cat "$test_tmp/no-channel-check.err")"
! fetched "$(candidate_asset "$new_commit")" || fail "a listed stable snapshot without a channel is never used"
TEST_POINTER=missing TEST_API=up TEST_LISTING=stable-only run no-channel-yes --yes
expect_status no-channel-yes 3 "a listing without package channels defers the update"
no_system_changes "an update without package channels"
pass "transport failures and a listing without package channels defer instead of failing"

pointer_warning='package channel pointer is malformed; using the GitHub release listing'
printf 'format=1\nsequence=3\ntag=asahi-packages-channel-3\nextra=1\n' >"$assets/pointers/malformed-extra-line"
printf 'sequence=3\nformat=1\ntag=asahi-packages-channel-3\n' >"$assets/pointers/malformed-wrong-order"
printf 'format=1\nsequence=3\ntag=asahi-packages-channel-4\n' >"$assets/pointers/malformed-tag-mismatch"
printf 'format=1\nsequence=3\ntag=asahi-quattro-channel-3\n' >"$assets/pointers/malformed-runtime-kind"
{ printf 'format=1\nsequence=3\ntag=asahi-packages-channel-3\n'; printf '%0300d\n' 0; } >"$assets/pointers/malformed-oversized"
printf 'format=1\nsequence=03\ntag=asahi-packages-channel-03\n' >"$assets/pointers/malformed-leading-zero"
printf 'format=1\nsequence=1234567890\ntag=asahi-packages-channel-1234567890\n' >"$assets/pointers/malformed-ten-digits"
printf 'format=1\r\nsequence=3\r\ntag=asahi-packages-channel-3\r\n' >"$assets/pointers/malformed-crlf"
printf 'format=1\nsequence=3\ntag=asahi-packages-channel-3\njunk' >"$assets/pointers/malformed-trailing-junk"
printf 'format=1\nsequence=3\ntag=asahi-packages-channel-3\n\0' >"$assets/pointers/malformed-trailing-nul"
printf 'format=1\nsequence=3\ntag=asahi-packages-channel-3' >"$assets/pointers/malformed-missing-newline"
: >"$assets/pointers/malformed-empty"
for variant in extra-line wrong-order tag-mismatch runtime-kind oversized leading-zero ten-digits crlf trailing-junk \
  trailing-nul missing-newline empty; do
  TEST_POINTER="malformed-$variant" TEST_API=up run "malformed-$variant" --check
  expect_status "malformed-$variant" 0 "the $variant pointer falls back to the GitHub release listing"
  grep -Fq "$pointer_warning" "$test_tmp/malformed-$variant.err" ||
    fail "the $variant pointer is reported as malformed" "$(cat "$test_tmp/malformed-$variant.err")"
  listing_read || fail "the $variant pointer reads the GitHub release listing"
done
TEST_POINTER=malformed-oversized TEST_STREAMED=1 TEST_API=up run malformed-streamed --check
expect_status malformed-streamed 0 "an oversized streamed pointer falls back to the GitHub release listing"
grep -Fq "$pointer_warning" "$test_tmp/malformed-streamed.err" ||
  fail "an oversized streamed pointer is reported as malformed" "$(cat "$test_tmp/malformed-streamed.err")"
pass "a malformed package channel pointer warns and falls back to the GitHub release listing"

write_state "$old_commit" 2
TEST_POINTER=pointer-1 TEST_API=up run behind-check --check
expect_status behind-check 0 "a pointer behind this Mac does not hide a newer listed channel"
grep -Fq 'package channel pointer (1) is behind this Mac (2)' "$test_tmp/behind-check.err" ||
  fail "a pointer behind this Mac is reported" "$(cat "$test_tmp/behind-check.err")"
listing_read && fetched "$(channel_asset 3)" || fail "a pointer behind this Mac uses the listed channel" "$(cat "$test_tmp/curl.log")"
! fetched "$(channel_asset 1)" || fail "a pointer behind this Mac is not followed"
TEST_POINTER=pointer-1 TEST_API=down run behind-down --check
expect_status behind-down 3 "a pointer behind this Mac with no listing defers"
grep -Fq 'package channel pointer is behind this Mac and the GitHub release listing is unavailable; nothing changed' \
  "$test_tmp/behind-down.err" || fail "a pointer behind this Mac with no listing explains the deferral" "$(cat "$test_tmp/behind-down.err")"
TEST_POINTER=pointer-2 run at-floor --check
expect_status at-floor 1 "a pointer at this Mac's channel is followed"
fetched "$(channel_asset 2)" || fail "a pointer at this Mac's channel selects that channel" "$(cat "$test_tmp/curl.log")"
[[ ! -e $test_tmp/api-hits ]] || fail "a pointer at this Mac's channel never reads the GitHub API"
rm -f "$state"
pass "a package channel pointer behind this Mac defers to the GitHub release listing"

mkdir -p "$assets/asahi-packages-channel-4"
cp "$assets/asahi-packages-channel-3/asahi-packages-channel" "$assets/asahi-packages-channel-3/asahi-packages-channel.sig" \
  "$assets/asahi-packages-channel-4/"
TEST_POINTER=pointer-4 run sequence-mismatch --check
expect_status sequence-mismatch 2 "a channel release must carry its own signed sequence"
grep -Fq 'channel release asahi-packages-channel-4 carries sequence 3' "$test_tmp/sequence-mismatch.err" ||
  fail "a mismatched channel release explains the refusal" "$(cat "$test_tmp/sequence-mismatch.err")"
! listing_read || fail "a signed channel failure after the pointer does not fall back to the GitHub release listing"
rm -rf "$assets/asahi-packages-channel-4"
pass "a numbered package channel release must carry its own signed sequence"

TEST_POINTER=pointer-3 TEST_CHANNEL_GPG_FAIL=1 run channel-badsig --check
expect_status channel-badsig 2 "an unsigned package channel fails closed"
grep -Fq 'signature verification failed for asahi-packages-channel' "$test_tmp/channel-badsig.err" ||
  fail "an unsigned package channel explains the refusal" "$(cat "$test_tmp/channel-badsig.err")"
! listing_read || fail "a channel signature failure does not fall back to the GitHub release listing"
TEST_POINTER=pointer-3 TEST_CHANNEL_SIGNER=other run channel-wrong-key --check
expect_status channel-wrong-key 2 "a package channel signed by another key fails closed"
grep -Fq 'asahi-packages-channel was not signed by the trusted Omarchy release key' "$test_tmp/channel-wrong-key.err" ||
  fail "a package channel signed by another key explains the refusal" "$(cat "$test_tmp/channel-wrong-key.err")"
no_system_changes "a rejected channel signature"
pass "only package channels signed by the release key are accepted"

write_channel 3 "$new_commit" "$first_commit,$old_commit" "$assets/asahi-packages-channel-3" "$(printf '%064d' 7)"
TEST_POINTER=pointer-3 run descriptor-mismatch --check
expect_status descriptor-mismatch 2 "a descriptor that does not match the signed channel fails closed"
grep -Fq "the CANDIDATE of $new_tag does not match the signed package channel" "$test_tmp/descriptor-mismatch.err" ||
  fail "a descriptor mismatch explains the refusal" "$(cat "$test_tmp/descriptor-mismatch.err")"
write_pacman_conf "$new_tag"
TEST_POINTER=pointer-3 run descriptor-mismatch-current --yes
expect_status descriptor-mismatch-current 2 "a Mac already on the target still authenticates its descriptor"
no_system_changes "a descriptor mismatch"
write_pacman_conf "$old_tag"
write_channel 3 "$new_commit" "$first_commit,$old_commit"
pass "the stable descriptor must match the digest in the signed channel"

schema_case() {
  local name="$1"
  mkdir -p "$assets/other/channels.example.test/$name"
  cat >"$assets/other/channels.example.test/$name/asahi-packages-channel"
  printf 'signature\n' >"$assets/other/channels.example.test/$name/asahi-packages-channel.sig"
}
valid_body() {
  printf 'format=1\nchannel=asahi-packages\nsequence=3\nstable_tag=%s\ndescriptor_sha256=%s\nsupersedes=%s\n' \
    "$new_tag" "$(descriptor_digest "$new_commit")" "${1-$first_commit,$old_commit}"
}
new_digest=$(descriptor_digest "$new_commit")
valid_body | sed '1{h;d};2G' | schema_case wrong-order
{ valid_body; printf 'note=1\n'; } | schema_case extra-key
valid_body | sed '3p' | schema_case duplicate-key
valid_body | sed '$d' | schema_case missing-key
valid_body | sed 's/^format=1$/format=2/' | schema_case format
valid_body | sed 's/^channel=.*/channel=asahi-quattro/' | schema_case channel-name
valid_body | sed 's/^sequence=3$/sequence=03/' | schema_case leading-zero
valid_body | sed 's/^sequence=3$/sequence=1234567890/' | schema_case ten-digits
valid_body | sed "s/^stable_tag=.*/stable_tag=asahi-packages-stable-${new_commit^^}/" | schema_case uppercase-tag
valid_body | sed "s/^descriptor_sha256=.*/descriptor_sha256=${new_digest:1}/" | schema_case short-descriptor
valid_body | sed 's/$/\r/' | schema_case crlf
{ valid_body; printf 'junk'; } | schema_case trailing-junk
{ valid_body; printf '\0'; } | schema_case trailing-nul
valid_body | head -c -1 | schema_case missing-newline
valid_body "$old_commit,$first_commit" | schema_case unsorted
valid_body "$first_commit,$first_commit" | schema_case duplicate-entry
valid_body "$first_commit,$old_commit," | schema_case trailing-comma
valid_body ",$first_commit" | schema_case leading-comma
valid_body "$first_commit,,$old_commit" | schema_case empty-entry
valid_body "$first_commit,$new_commit" | schema_case supersedes-target
valid_body "${first_commit:1}" | schema_case short-entry
valid_body "$first_commit, $old_commit" | schema_case space
valid_body "$(for ((i = 1; i <= 2049; i++)); do printf '%040x,' "$i"; done | head -c -1)" | schema_case too-many
{ valid_body; head -c 131072 /dev/zero | tr '\0' 'a'; } | schema_case oversized
: | schema_case empty
for variant in wrong-order extra-key duplicate-key missing-key format channel-name leading-zero ten-digits uppercase-tag \
  short-descriptor crlf trailing-junk trailing-nul missing-newline unsorted duplicate-entry trailing-comma leading-comma \
  empty-entry supersedes-target short-entry space too-many oversized empty; do
  OMARCHY_ASAHI_PACKAGES_CHANNEL_URL="https://channels.example.test/$variant/asahi-packages-channel" run "schema-$variant" --yes
  expect_status "schema-$variant" 2 "the $variant package channel fails closed"
  no_system_changes "the $variant package channel"
done
grep -Fq 'the signed package channel is larger than 128 KiB' "$test_tmp/schema-oversized.err" ||
  fail "an oversized package channel explains the refusal" "$(cat "$test_tmp/schema-oversized.err")"
OMARCHY_ASAHI_PACKAGES_CHANNEL_URL="https://channels.example.test/oversized/asahi-packages-channel" TEST_STREAMED=1 \
  run schema-streamed --check
expect_status schema-streamed 2 "an oversized streamed package channel fails closed"
grep -Fq 'the signed package channel is larger than 128 KiB' "$test_tmp/schema-streamed.err" ||
  fail "an oversized streamed package channel explains the refusal" "$(cat "$test_tmp/schema-streamed.err")"
grep -Fq 'supersedes more than 2048 snapshots' "$test_tmp/schema-too-many.err" ||
  fail "a supersedes list over the limit explains the refusal" "$(cat "$test_tmp/schema-too-many.err")"
limit_commit=$(printf '%040x' 2048)
valid_body "$(for ((i = 1; i <= 2048; i++)); do printf '%040x,' "$i"; done | head -c -1)" | schema_case at-limit
write_pacman_conf "asahi-packages-stable-$limit_commit"
OMARCHY_ASAHI_PACKAGES_CHANNEL_URL="https://channels.example.test/at-limit/asahi-packages-channel" run schema-at-limit --check
expect_status schema-at-limit 0 "a supersedes list at the limit is accepted"
write_pacman_conf "$old_tag"
pass "the package channel must be exactly six canonical keys within the size limits"

write_pacman_conf "$new_tag"
TEST_POINTER=pointer-3 run target-check --check
expect_status target-check 1 "a Mac already on the channel's snapshot reports no update"
fetched "$(channel_asset 3)" && fetched "$(candidate_asset "$new_commit")" ||
  fail "a Mac already on the channel's snapshot still authenticates the channel and descriptor" "$(cat "$test_tmp/curl.log")"
no_system_changes "a current --check"
TEST_POINTER=pointer-3 TEST_GPG_FAIL=1 run target-badsig --check
expect_status target-badsig 2 "a Mac already on the channel's snapshot still rejects a bad descriptor signature"
TEST_POINTER=pointer-3 run target-yes --yes
expect_status target-yes 0 "a Mac already on the channel's snapshot is a successful no-op"
grep -Fxq 'Apple Silicon package repository is up to date' "$test_tmp/target-yes.out" || fail "a current snapshot reports up to date"
(( $(wc -l <"$calls") == 1 )) && grep -Eq "^sudo:install -D -o root -g root -m 0644 [^ ]+ $state\$" "$calls" ||
  fail "a current repository is not rewritten; only its state is" "$(cat "$calls")"
grep -Fxq "tag=$new_tag" "$state" && grep -Fxq 'channel_sequence=3' "$state" && grep -Fxq 'workflow_run=33487927893' "$state" &&
  grep -Fxq "descriptor_sha256=$(descriptor_digest "$new_commit")" "$state" ||
  fail "an update on the channel's snapshot records the bookkeeping a crash could have lost" "$(cat "$state" 2>/dev/null)"
before=$(state_digest)
TEST_POINTER=pointer-3 run target-again --yes
expect_status target-again 0 "a second current update is a no-op"
no_system_changes "a current update with current state" "$before"
pass "a Mac already on the channel's snapshot authenticates it and only refreshes its state on update"

write_state "$new_commit"
before=$(state_digest)
TEST_POINTER=pointer-3 run old-state-check --check
expect_status old-state-check 1 "state written before the package channel is still read"
no_system_changes "a --check with old state" "$before"
TEST_POINTER=pointer-3 run old-state-yes --yes
expect_status old-state-yes 0 "an update with old state succeeds"
grep -Fxq 'channel_sequence=3' "$state" || fail "an update adds the channel sequence to old state" "$(cat "$state")"
printf 'channel_sequence=\n' >>"$state"
TEST_POINTER=pointer-3 run empty-sequence-state --check
expect_status empty-sequence-state 2 "an empty channel sequence in state fails closed"
pass "repository state from before the package channel is accepted and upgraded on update"

write_state "$new_commit" "" "$(printf '%064d' 9)"
before=$(state_digest)
TEST_POINTER=pointer-3 run contradiction --yes
expect_status contradiction 2 "state naming the channel's snapshot with another descriptor fails closed"
grep -Fq "repository state contradicts the signed channel: $new_tag has a different descriptor" "$test_tmp/contradiction.err" ||
  fail "a contradictory descriptor explains the refusal" "$(cat "$test_tmp/contradiction.err")"
no_system_changes "a contradictory state" "$before"
write_state "$old_commit" 3
before=$(state_digest)
write_pacman_conf "$old_tag"
TEST_POINTER=pointer-3 run sequence-contradiction --yes
expect_status sequence-contradiction 2 "state recording another snapshot for the same sequence fails closed"
grep -Fq "repository state contradicts the signed channel: sequence 3 names $new_tag" "$test_tmp/sequence-contradiction.err" ||
  fail "a contradictory sequence explains the refusal" "$(cat "$test_tmp/sequence-contradiction.err")"
no_system_changes "a contradictory sequence" "$before"
rm -f "$state"
pass "repository state that contradicts the signed channel is never overwritten"

write_pacman_conf "asahi-packages-stable-$hand_commit"
TEST_POINTER=pointer-3 run hand-check --check
expect_status hand-check 1 "a pinned snapshot the channel does not supersede reports no update"
[[ ! -s $test_tmp/hand-check.out ]] || fail "a preserved snapshot check prints nothing an update list would pick up" "$(cat "$test_tmp/hand-check.out")"
grep -Fxq "Apple Silicon package repository: the pinned package set ${hand_commit:0:8} is not older than channel 3 (${new_commit:0:8}); leaving it" \
  "$test_tmp/hand-check.err" || fail "a preserved snapshot explains itself" "$(cat "$test_tmp/hand-check.err")"
before_conf=$(sha256sum "$pacman_conf")
TEST_POINTER=pointer-3 run hand-yes --yes
expect_status hand-yes 0 "an update leaves a snapshot the channel does not supersede"
[[ $(sha256sum "$pacman_conf") == "$before_conf" ]] || fail "a preserved snapshot keeps its Server"
no_system_changes "a preserved snapshot"
write_state "$old_commit" 2
before=$(state_digest)
TEST_POINTER=pointer-3 run hand-state --yes
expect_status hand-state 0 "an update leaves a hand-pinned snapshot even when state names a superseded one"
no_system_changes "a preserved snapshot with state" "$before"
rm -f "$state"
pass "a stable snapshot the signed channel does not supersede is preserved without writes"

for server in \
  "https://mirror.example.test/omarchy/aarch64" \
  "https://github.com/$repo/releases/download/asahi-packages-candidate-$old_commit" \
  "https://github.com/$repo/releases/download/asahi-packages-channel-3" \
  "https://github.com/$repo/releases/download/asahi-packages-$legacy_commit/extra" \
  "https://github.com/someone/omarchy-pkgs/releases/download/asahi-packages-$legacy_commit" \
  "https://github.com/someone/omarchy-pkgs/releases/download/$old_tag" \
  "https://github.com/$repo/releases/download/$old_tag/extra"; do
  write_pacman_conf_server "$server"
  before_conf=$(sha256sum "$pacman_conf")
  TEST_POINTER=pointer-3 run unknown-check --check
  expect_status unknown-check 1 "an unrecognised Server reports no update ($server)"
  [[ ! -s $test_tmp/unknown-check.out ]] || fail "an unrecognised Server check prints nothing an update list would pick up ($server)"
  grep -Fxq 'Apple Silicon package repository: unrecognised [omarchy] Server; not moving it' "$test_tmp/unknown-check.err" ||
    fail "an unrecognised Server explains itself" "$(cat "$test_tmp/unknown-check.err")"
  TEST_POINTER=pointer-3 run unknown-yes --yes
  expect_status unknown-yes 0 "an update leaves an unrecognised Server ($server)"
  [[ $(sha256sum "$pacman_conf") == "$before_conf" ]] || fail "an unrecognised Server is kept ($server)"
  no_system_changes "an unrecognised Server"
done
write_pacman_conf "$old_tag"
pass "an unrecognised [omarchy] Server is never moved and nothing is recorded for it"

# The same shape install/hardware/pacman.sh leaves: its own [omarchy] block appended at the end.
write_legacy_pacman_conf() {
  write_pacman_conf "$old_tag"
  awk '
    /^\[omarchy\][[:space:]]*$/ { skip = 1; next }
    skip && /^\[[^]]+\][[:space:]]*$/ { skip = 0 }
    !skip { print }
  ' "$pacman_conf" >"$pacman_conf.legacy"
  printf '\n[omarchy]\nSigLevel = Required DatabaseOptional\nServer = %s\n' "$legacy_server" >>"$pacman_conf.legacy"
  mv "$pacman_conf.legacy" "$pacman_conf"
}

normalized_calls() {
  sed -E -e "s|$test_tmp|TEST|g" -e 's|TEST/root/var/lib/omarchy/backups/asahi-repository-[0-9]{14}|BACKUP|g' \
    -e 's|[^ ]*/tmp\.[A-Za-z0-9]+|WORK|g' "$calls"
}

write_descriptor "$legacy_commit" 31000000000
write_channel 5 "$new_commit" "$first_commit,$legacy_commit,$old_commit"
write_channel 6 "$legacy_commit" "$first_commit"
write_pointer 5
write_pointer 6

write_legacy_pacman_conf
legacy_conf=$(cat "$pacman_conf")
TEST_POINTER=pointer-5 run legacy-check --check
expect_status legacy-check 0 "a legacy pin the channel supersedes is offered the channel's set"
grep -Fxq "Apple Silicon package repository $new_tag is available" "$test_tmp/legacy-check.out" ||
  fail "a legacy pin is offered the channel's stable set" "$(cat "$test_tmp/legacy-check.out")"
no_system_changes "a legacy --check"
rm -f "$test_tmp/key-trusted"
TEST_POINTER=pointer-5 run legacy-yes --yes
expect_status legacy-yes 0 "a legacy pin the channel supersedes moves"
grep -Fq "Switched the Apple Silicon package repository to $new_tag" "$test_tmp/legacy-yes.out" ||
  fail "a legacy move reports the new set" "$(cat "$test_tmp/legacy-yes.out")"
[[ $(cat "$pacman_conf") == "${legacy_conf/"Server = $legacy_server"/"Server = https://github.com/$repo/releases/download/$new_tag"}" ]] ||
  fail "a legacy move changes only the Server line and keeps SigLevel" "$(diff <(echo "$legacy_conf") "$pacman_conf" || true)"
fetched "https://github.com/$repo/releases/download/$new_tag/omarchy.db" && fetched "https://github.com/$repo/releases/download/$new_tag/omarchy.db.sig" ||
  fail "a legacy move verifies the new repository database first"
expected_calls="sudo:find TEST/root/etc/pacman.conf TEST/root/etc/pacman.d -type f -exec sha256sum {} +
sudo:install -d -o root -g root -m 0700 BACKUP
sudo:cp -a WORK/. BACKUP/
sudo:pacman-key --finger $primary_fingerprint
pacman-key:--finger $primary_fingerprint
sudo:pacman-key --add TEST/omarchy-arm-repository.asc
pacman-key:--add TEST/omarchy-arm-repository.asc
sudo:pacman-key --lsign-key $primary_fingerprint
pacman-key:--lsign-key $primary_fingerprint
sudo:install -o root -g root -m 0644 WORK/pacman.conf TEST/root/etc/pacman.conf
sudo:env OMARCHY_UPDATE_PACMAN=1 pacman -Sy --noconfirm
pacman:-Sy --noconfirm OMARCHY_UPDATE_PACMAN=1
sudo:install -D -o root -g root -m 0644 WORK/state TEST/state"
[[ $(normalized_calls) == "$expected_calls" ]] ||
  fail "a legacy move backs up, trusts the ARM repository key, rewrites, syncs and records state as the old updater did" \
    "$(diff <(echo "$expected_calls") <(normalized_calls) || true)"
legacy_backup=$(grep -Eo "$root/var/lib/omarchy/backups/asahi-repository-[0-9]{14}" "$calls" | head -1)
[[ $(cat "$legacy_backup/pacman.conf") == "$legacy_conf" ]] || fail "a legacy move backs up the legacy pacman.conf"
grep -Fxq "tag=$new_tag" "$state" && grep -Fxq 'channel_sequence=5' "$state" ||
  fail "a legacy move records the channel's set" "$(cat "$state")"
rm -f "$state"
pass "a legacy install-time pin the channel supersedes moves to the stable set exactly as the old updater moved it"

write_legacy_pacman_conf
TEST_POINTER=pointer-3 run legacy-kept-check --check
expect_status legacy-kept-check 1 "a legacy pin the channel does not supersede reports no update"
[[ ! -s $test_tmp/legacy-kept-check.out ]] || fail "a preserved legacy pin check prints nothing an update list would pick up"
grep -Fxq "Apple Silicon package repository: the pinned package set ${legacy_commit:0:8} is not older than channel 3 (${new_commit:0:8}); leaving it" \
  "$test_tmp/legacy-kept-check.err" || fail "a preserved legacy pin explains itself" "$(cat "$test_tmp/legacy-kept-check.err")"
TEST_POINTER=pointer-3 run legacy-kept-yes --yes
expect_status legacy-kept-yes 0 "an update leaves a legacy pin the channel does not supersede"
[[ $(cat "$pacman_conf") == "$legacy_conf" ]] || fail "a preserved legacy pin keeps its Server"
no_system_changes "a preserved legacy pin"
pass "a legacy pin the signed channel does not supersede is preserved without writes"

TEST_POINTER=pointer-6 run legacy-target-check --check
expect_status legacy-target-check 0 "a legacy pin on the target's commit is not up to date"
grep -Fxq "Apple Silicon package repository asahi-packages-stable-$legacy_commit is available" "$test_tmp/legacy-target-check.out" ||
  fail "a legacy pin on the target's commit is offered its stable release" "$(cat "$test_tmp/legacy-target-check.out")"
no_system_changes "a legacy --check on the target's commit"
TEST_POINTER=pointer-6 run legacy-target-yes --yes
expect_status legacy-target-yes 0 "a legacy pin on the target's commit moves"
[[ $(cat "$pacman_conf") == "${legacy_conf/"Server = $legacy_server"/"Server = https://github.com/$repo/releases/download/asahi-packages-stable-$legacy_commit"}" ]] ||
  fail "a legacy pin on the target's commit moves to the stable URL" "$(diff <(echo "$legacy_conf") "$pacman_conf" || true)"
grep -Fxq 'pacman:-Sy --noconfirm OMARCHY_UPDATE_PACMAN=1' "$calls" && grep -Fxq 'channel_sequence=6' "$state" ||
  fail "a legacy pin on the target's commit syncs and records state" "$(cat "$calls" "$state")"
TEST_POINTER=pointer-6 run legacy-target-again --check
expect_status legacy-target-again 1 "the stable URL on the target's commit is then up to date"
rm -f "$state"
write_pacman_conf "$old_tag"
pass "a legacy pin on the channel's own commit moves to that commit's stable URL"

write_state "$hand_commit" 5
before=$(state_digest)
TEST_POINTER=pointer-3 TEST_API=up run floor-check --check
expect_status floor-check 1 "a channel below this Mac's reports no update even when it supersedes the pin"
[[ ! -s $test_tmp/floor-check.out ]] || fail "a channel below this Mac prints nothing an update list would pick up"
grep -Fq 'package channel pointer (3) is behind this Mac (5)' "$test_tmp/floor-check.err" ||
  fail "the pointer below this Mac is reported first" "$(cat "$test_tmp/floor-check.err")"
grep -Fxq 'Apple Silicon package repository: package channel 3 is older than channel 5 on this Mac; leaving [omarchy] unchanged' \
  "$test_tmp/floor-check.err" || fail "a channel below this Mac explains itself" "$(cat "$test_tmp/floor-check.err")"
no_system_changes "a channel below this Mac" "$before"
TEST_POINTER=pointer-3 TEST_API=up run floor-yes --yes
expect_status floor-yes 0 "an update does not move to a channel below this Mac"
grep -Fxq "Server = https://github.com/$repo/releases/download/$old_tag" "$pacman_conf" || fail "a channel below this Mac does not move [omarchy]"
no_system_changes "an update below this Mac" "$before"
OMARCHY_ASAHI_PACKAGES_CHANNEL_URL="https://github.com/$repo/releases/download/asahi-packages-channel-3/asahi-packages-channel" \
  run floor-override --yes
expect_status floor-override 0 "an explicit channel below this Mac does not move [omarchy]"
no_system_changes "an explicit channel below this Mac" "$before"
rm -f "$state"
pass "an authenticated channel below this Mac's never moves [omarchy]"

write_pacman_conf "$old_tag"
cat >"$state" <<EOF
format=1
tag=$old_tag
source_commit=$old_commit
workflow_run=99999999999
descriptor_sha256=$(descriptor_digest "$old_commit")
EOF
before=$(state_digest)
TEST_POINTER=pointer-3 run higher-run --check
expect_status higher-run 0 "a superseded snapshot moves even when its recorded build run is higher"
no_system_changes "a --check over a higher build run" "$before"
rm -f "$state"
pass "workflow run numbers no longer decide whether the repository moves"

mkdir -p "$assets/other/channels.example.test/override"
write_channel 7 "$new_commit" "$first_commit,$old_commit" "$assets/other/channels.example.test/override"
OMARCHY_ASAHI_PACKAGES_CHANNEL_URL=https://channels.example.test/override/asahi-packages-channel TEST_POINTER=pointer-3 \
  run override --check
expect_status override 0 "an explicit channel URL is followed"
[[ $(cat "$test_tmp/curl.log") == "https://channels.example.test/override/asahi-packages-channel"$'\n'"https://channels.example.test/override/asahi-packages-channel.sig"$'\n'"$(candidate_asset "$new_commit")"$'\n'"$(candidate_asset "$new_commit").sig" ]] ||
  fail "an explicit channel URL reads neither the pointer nor the listing, and its sequence need not match a tag" "$(cat "$test_tmp/curl.log")"
OMARCHY_ASAHI_PACKAGES_CHANNEL_URL=https://channels.example.test/unpublished/asahi-packages-channel TEST_POINTER=pointer-3 \
  run override-missing --check
expect_status override-missing 3 "an unreachable explicit channel URL defers"
(( $(wc -l <"$test_tmp/curl.log") == 1 )) || fail "an unreachable explicit channel URL reads nothing else" "$(cat "$test_tmp/curl.log")"
pass "an explicit package channel URL bypasses the pointer and the GitHub release listing"

sed -i "s/^source_commit=.*/source_commit=$old_commit/" "$assets/$new_tag/CANDIDATE"
write_channel 3 "$new_commit" "$first_commit,$old_commit"
TEST_POINTER=pointer-3 run source --check
expect_status source 2 "descriptor for another source fails closed"
grep -Fq 'source commit does not match the stable tag' "$test_tmp/source.err" ||
  fail "descriptor source mismatch explains the refusal" "$(cat "$test_tmp/source.err")"
write_descriptor "$new_commit" 33487927893
write_channel 3 "$new_commit" "$first_commit,$old_commit"
pass "a stable tag whose descriptor names another source is rejected"

TEST_POINTER=pointer-3 TEST_GPG_SIGNER=primary run primary --check
expect_status primary 2 "descriptor signed by the primary key fails closed"
grep -Fq 'was not signed by the Omarchy ARM repository signing subkey' "$test_tmp/primary.err" ||
  fail "primary key signature explains the refusal" "$(cat "$test_tmp/primary.err")"
TEST_POINTER=pointer-3 TEST_GPG_FAIL=1 run badsig --check
expect_status badsig 2 "invalid descriptor signature fails closed"
grep -Fq 'signature verification failed for CANDIDATE' "$test_tmp/badsig.err" ||
  fail "invalid signature explains the refusal" "$(cat "$test_tmp/badsig.err")"
pass "only descriptors signed by the shipped repository subkey are accepted"

sed -i '/^\[aur\]$/d' "$pacman_conf"
TEST_POINTER=pointer-3 run aur --yes
expect_status aur 2 "missing platform repository fails closed"
grep -Fq 'required [aur] repository is missing' "$test_tmp/aur.err" || fail "missing repository is named" "$(cat "$test_tmp/aur.err")"
write_pacman_conf "$old_tag"
printf '\n[omarchy]\nServer = https://example.test/other\n' >>"$pacman_conf"
TEST_POINTER=pointer-3 run twice --yes
expect_status twice 2 "duplicate [omarchy] blocks fail closed"
grep -Fq 'exactly one [omarchy] repository' "$test_tmp/twice.err" || fail "duplicate block refusal is explained" "$(cat "$test_tmp/twice.err")"
[[ ! -s $calls ]] || fail "malformed pacman configuration is never rewritten" "$(cat "$calls")"
pass "protected pacman configuration is validated before any change"

write_pacman_conf "$old_tag"
write_state "$old_commit" 2
before=$(sed "s|$old_tag|$new_tag|" "$pacman_conf")
rm -f "$test_tmp/key-trusted"
TEST_POINTER=pointer-3 run apply --yes
expect_status apply 0 "repository switch succeeds"
grep -Fq "Switched the Apple Silicon package repository to $new_tag" "$test_tmp/apply.out" ||
  fail "repository switch reports the new snapshot" "$(cat "$test_tmp/apply.out")"
[[ $(cat "$pacman_conf") == "$before" ]] || fail "only the [omarchy] Server line changes" "$(diff <(echo "$before") "$pacman_conf" || true)"
fetched "https://github.com/$repo/releases/download/$new_tag/omarchy.db" || fail "the repository database is downloaded before switching"
grep -Fq 'sudo:pacman-key --finger C81AC3E2A99556F9B21D5FEA3DD49BC9F8360BDC' "$calls" || fail "the repository key trust is checked"
grep -Fxq "pacman-key:--add $test_tmp/omarchy-arm-repository.asc" "$calls" || fail "a missing repository key is imported into pacman"
grep -Fxq 'pacman-key:--lsign-key C81AC3E2A99556F9B21D5FEA3DD49BC9F8360BDC' "$calls" || fail "the imported repository key is locally signed"
grep -Fxq 'pacman:-Sy --noconfirm OMARCHY_UPDATE_PACMAN=1' "$calls" || fail "the new repository is synced through the update guard"
grep -Eq "^sudo:install -d -o root -g root -m 0700 $root/var/lib/omarchy/backups/asahi-repository-[0-9]{14}\$" "$calls" ||
  fail "a root-owned backup directory is created" "$(cat "$calls")"
[[ -f $(ls -d "$root"/var/lib/omarchy/backups/asahi-repository-*/pacman.conf | tail -1) ]] || fail "the previous pacman.conf is backed up"
[[ -f $state ]] || fail "repository state is recorded"
[[ $(cat "$state") == "format=1"$'\n'"tag=$new_tag"$'\n'"source_commit=$new_commit"$'\n'"workflow_run=33487927893"$'\n'"descriptor_sha256=$(descriptor_digest "$new_commit")"$'\n'"channel_sequence=3" ]] ||
  fail "repository state records the snapshot, its signed build, its descriptor digest and the channel sequence" "$(cat "$state")"
pass "the [omarchy] repository is repointed from a superseded snapshot to the channel's snapshot"

TEST_POINTER=pointer-3 run again --check
expect_status again 1 "the switched repository is current"
pass "a switched repository is not offered again"

write_pacman_conf "$old_tag"
rm -f "$state"
: >"$test_tmp/key-trusted"
TEST_POINTER=pointer-3 TEST_PACMAN_FAIL=1 run sync --yes
expect_status sync 2 "a failed repository sync fails closed"
grep -Fq 'restored the previous repository' "$test_tmp/sync.err" || fail "sync failure explains the restore" "$(cat "$test_tmp/sync.err")"
grep -Fxq "Server = https://github.com/$repo/releases/download/$old_tag" "$pacman_conf" || fail "a failed sync restores the previous Server"
! grep -Fq 'pacman-key:--add' "$calls" || fail "an already trusted key is not re-imported"
[[ ! -f $state ]] || fail "a failed sync records no state"
pass "a snapshot pacman cannot read leaves the previous repository in place"
