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
(( $(wc -l <<<"$api_lines") == 3 )) || fail "only the three documented listing fallbacks in bin/ read the GitHub API" "$api_lines"
aurora_updater="$ROOT/bin/omarchy-update-aurora-repository"
aurora_api_line=$(grep -nF 'api.github.com' "$aurora_updater" || true)
grep -Fq 'releases_api_url="https://api.github.com/repos/$repo/releases?per_page=100"' <<<"$aurora_api_line" ||
  fail "the Aurora updater reads the GitHub API only as its edge release listing fallback" "$api_lines"
aurora_pointer_line=$(grep -nF 'https://downloads.aicodelabs.com.au/pointers/aurora-edge-channel' "$aurora_updater" | cut -d: -f1)
[[ -n $aurora_pointer_line ]] && (( aurora_pointer_line < ${aurora_api_line%%:*} )) ||
  fail "the Aurora updater tries its R2 pointer before the GitHub API"
for command in "$bundle_updater" "$updater"; do
  api_line=$(grep -nF 'api.github.com' "$command" || true)
  grep -Fq 'releases_api_url="${OMARCHY_ASAHI_RELEASES_API_URL:-https://api.github.com/repos/$repo/releases?per_page=100}"' <<<"$api_line" ||
    fail "$(basename "$command") reads the GitHub API only as its release listing fallback" "$api_lines"
  pointer_line=$(grep -nF 'https://downloads.aicodelabs.com.au/pointers/' "$command" | cut -d: -f1)
  [[ -n $pointer_line ]] && (( pointer_line < ${api_line%%:*} )) ||
    fail "$(basename "$command") tries its R2 pointer before the GitHub API"
done
pass "installed Macs read the GitHub API only as the fallback behind the bundle, package channel and Aurora edge pointers"

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
[[ ${TEST_PACMAN_FAIL:-0} != 1 ]] || exit 1
# A successful sync caches the configured Server's database, as pacman does.
if [[ -n ${TEST_PACMAN_SYNC_DIR:-} && " $* " == *" -Sy "* ]]; then
  mkdir -p "$TEST_PACMAN_SYNC_DIR"
  printf 'database synced from the new Server' >"$TEST_PACMAN_SYNC_DIR/omarchy.db"
  printf 'signature synced from the new Server' >"$TEST_PACMAN_SYNC_DIR/omarchy.db.sig"
fi
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
sudo:rm -f TEST/root/var/lib/pacman/sync/omarchy.db TEST/root/var/lib/pacman/sync/omarchy.db.sig
sudo:install -o root -g root -m 0644 WORK/pacman.conf TEST/root/etc/pacman.conf
sudo:env OMARCHY_UPDATE_PACMAN=1 pacman -Sy --noconfirm
pacman:-Sy --noconfirm OMARCHY_UPDATE_PACMAN=1
sudo:install -D -o root -g root -m 0644 WORK/state TEST/state"
[[ $(normalized_calls) == "$expected_calls" ]] ||
  fail "a legacy move backs up, trusts the ARM repository key, drops the cached database, rewrites, syncs and records state" \
    "$(diff <(echo "$expected_calls") <(normalized_calls) || true)"
legacy_backup=$(grep -Eo "$root/var/lib/omarchy/backups/asahi-repository-[0-9]{14}" "$calls" | head -1)
[[ $(cat "$legacy_backup/pacman.conf") == "$legacy_conf" ]] || fail "a legacy move backs up the legacy pacman.conf"
grep -Fxq "tag=$new_tag" "$state" && grep -Fxq 'channel_sequence=5' "$state" ||
  fail "a legacy move records the channel's set" "$(cat "$state")"
rm -f "$state"
pass "a legacy install-time pin the channel supersedes moves to the stable set as the old updater moved it, without its cached database"

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
mkdir -p "$root/var/lib/pacman/sync"
printf 'database of the previous set' >"$root/var/lib/pacman/sync/omarchy.db"
printf 'signature of the previous set' >"$root/var/lib/pacman/sync/omarchy.db.sig"
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
[[ ! -e $root/var/lib/pacman/sync/omarchy.db && ! -e $root/var/lib/pacman/sync/omarchy.db.sig ]] ||
  fail "a repoint drops the database cached for the previous set"
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

# --- Bootstrap: the fresh installer's first step ------------------------------
# A clean Asahi Arch Minimal has no [omarchy]; the fresh installer runs this
# before its first package transaction.

cat >"$stub_bin/pacman-conf" <<'SH'
#!/bin/bash
config=/etc/pacman.conf
while (($#)); do
  case $1 in
    --config) config=$2; shift 2 ;;
    --repo-list) shift ;;
    *) echo "unexpected pacman-conf argument $1" >&2; exit 2 ;;
  esac
done
# An Include file can define a repository ahead of every section in the file.
[[ -z ${TEST_INCLUDED_REPOSITORY:-} ]] || printf '%s\n' "$TEST_INCLUDED_REPOSITORY"
awk '/^[[:space:]]*\[[^]]+\][[:space:]]*$/ { gsub(/[][[:space:]]/, ""); if ($0 != "options") print }' "$config"
SH
# Each key is trusted on its own, so a fresh keyring shows both being added.
cat >"$stub_bin/pacman-key" <<'SH'
#!/bin/bash
printf 'pacman-key:%s\n' "$*" >>"$TEST_CALLS"
case $1 in
  --finger) [[ -f $TEST_KEY_STATE.$2 ]] ;;
  --add)
    if [[ $2 == *release* ]]; then
      : >"$TEST_KEY_STATE.5983B1CA32CB778F4D74D24ECFF35022CA5B5959"
    else
      : >"$TEST_KEY_STATE.C81AC3E2A99556F9B21D5FEA3DD49BC9F8360BDC"
    fi
    ;;
esac
SH
chmod +x "$stub_bin/pacman-conf" "$stub_bin/pacman-key"

write_minimal_pacman_conf() {
  cat >"$pacman_conf" <<'CONF'
[options]
Architecture = aarch64
SigLevel = Required DatabaseOptional

# Asahi Linux packages
[asahi-alarm]
Include = /etc/pacman.d/mirrorlist.asahi-alarm

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[alarm]
Include = /etc/pacman.d/mirrorlist

[aur]
Include = /etc/pacman.d/mirrorlist
CONF
}

# The minimal configuration with a block placed before a repository, or at the end.
write_bootstrap_conf() {
  local block="${1:-}" before="${2:-}" conf
  write_minimal_pacman_conf
  [[ -n $block ]] || return 0
  conf=$(cat "$pacman_conf")
  if [[ -n $before ]]; then
    conf=${conf/$'\n'"[$before]"$'\n'/$'\n'"$block"$'\n\n'"[$before]"$'\n'}
  else
    conf+=$'\n\n'"$block"
  fi
  printf '%s\n' "$conf" >"$pacman_conf"
}

canonical_block() {
  printf '[omarchy]\nSigLevel = Required DatabaseOptional\nServer = %s' "$1"
}

# What the minimal configuration becomes with [omarchy] leading the repositories.
bootstrapped_conf() {
  local conf
  write_minimal_pacman_conf
  conf=$(cat "$pacman_conf")
  printf '%s\n' "${conf/$'\n[asahi-alarm]\n'/$'\n'"$(canonical_block "$1")"$'\n\n[asahi-alarm]\n'}"
}

sync_dir="$root/var/lib/pacman/sync"
seed_sync_cache() {
  mkdir -p "$sync_dir"
  printf 'database of the previous Server' >"$sync_dir/omarchy.db"
  printf 'signature of the previous Server' >"$sync_dir/omarchy.db.sig"
}

untouched() {
  local name="$1" description="$2" original="$3"
  [[ $(cat "$pacman_conf") == "$original" ]] || fail "$description: pacman.conf is untouched" "$(diff <(echo "$original") "$pacman_conf" || true)"
  [[ ! -s $calls ]] || fail "$description: nothing is run as root" "$(cat "$calls")"
  [[ ! -e $state ]] || fail "$description: no repository state is written" "$(cat "$state")"
}

new_server="https://github.com/$repo/releases/download/$new_tag"
old_server="https://github.com/$repo/releases/download/$old_tag"
hand_server="https://github.com/$repo/releases/download/asahi-packages-stable-$hand_commit"
candidate_server="https://github.com/$repo/releases/download/asahi-packages-candidate-$new_commit"
mirror_server='https://mirror.example.test/omarchy/$arch'
rm -f "$state" "$test_tmp"/key-trusted*

write_bootstrap_conf
original=$(cat "$pacman_conf")
run bootstrap-without-yes --bootstrap
expect_status bootstrap-without-yes 2 "--bootstrap without --yes is refused"
grep -Fq -- '--bootstrap requires --yes' "$test_tmp/bootstrap-without-yes.err" || fail "--bootstrap without --yes explains the refusal"
run bootstrap-check --yes --bootstrap --check
expect_status bootstrap-check 2 "--bootstrap never runs as a check"
grep -Fq -- '--bootstrap cannot be combined with --check' "$test_tmp/bootstrap-check.err" || fail "--bootstrap --check explains the refusal"
untouched bootstrap-check "a refused bootstrap mode" "$original"
[[ ! -s $test_tmp/curl.log ]] || fail "a refused bootstrap mode fetches nothing"
pass "--bootstrap requires --yes and never runs as a check"

write_bootstrap_conf
seed_sync_cache
TEST_POINTER=pointer-3 run bootstrap-absent --yes --bootstrap
expect_status bootstrap-absent 0 "a missing [omarchy] section is bootstrapped"
[[ $(cat "$pacman_conf") == "$(bootstrapped_conf "$new_server")" ]] ||
  fail "the channel's stable set is inserted before the first repository, every other line kept" \
    "$(diff <(bootstrapped_conf "$new_server") "$pacman_conf" || true)"
[[ ! -e $sync_dir/omarchy.db && ! -e $sync_dir/omarchy.db.sig ]] || fail "a bootstrapped section drops any cached database"
for trusted in "--add $test_tmp/omarchy-release.gpg" "--lsign-key $release_fingerprint" \
  "--add $test_tmp/omarchy-arm-repository.asc" "--lsign-key $primary_fingerprint"; do
  grep -Fxq "pacman-key:$trusted" "$calls" || fail "a bootstrap trusts both Omarchy keys ($trusted)" "$(cat "$calls")"
done
drop_line=$(grep -n -m1 '^sudo:rm -f ' "$calls" | cut -d: -f1)
write_line=$(grep -n -m1 "^sudo:install -o root -g root -m 0644 [^ ]*/pacman.conf $pacman_conf\$" "$calls" | cut -d: -f1)
sync_line=$(grep -n -m1 '^pacman:-Sy --noconfirm' "$calls" | cut -d: -f1)
[[ -n $drop_line && -n $write_line && -n $sync_line ]] && (( drop_line < write_line && write_line < sync_line )) ||
  fail "the cache is dropped, then pacman.conf written, then synced" "$(cat "$calls")"
fetched "https://github.com/$repo/releases/download/$new_tag/omarchy.db" &&
  fetched "https://github.com/$repo/releases/download/$new_tag/omarchy.db.sig" || fail "a bootstrap verifies the database it points at"
grep -Fxq "tag=$new_tag" "$state" && grep -Fxq 'channel_sequence=3' "$state" ||
  fail "a bootstrap onto the channel's stable set records it" "$(cat "$state" 2>/dev/null)"
grep -Fq "Configured the Apple Silicon package repository on $new_tag" "$test_tmp/bootstrap-absent.out" ||
  fail "a bootstrap reports the set it configured" "$(cat "$test_tmp/bootstrap-absent.out")"
pass "a missing [omarchy] section gets the channel's stable set, first, with both keys trusted and the cache dropped"

rm -f "$state"
write_bootstrap_conf
original=$(cat "$pacman_conf")
TEST_POINTER=pointer-3 TEST_PACMAN_FAIL=1 run bootstrap-sync-fails --yes --bootstrap
expect_status bootstrap-sync-fails 2 "a bootstrap pacman cannot read fails"
grep -Fq "pacman could not read $new_tag; restored the previous repository" "$test_tmp/bootstrap-sync-fails.err" ||
  fail "a failed bootstrap sync explains the restore" "$(cat "$test_tmp/bootstrap-sync-fails.err")"
[[ $(cat "$pacman_conf") == "$original" && ! -e $state ]] || fail "a failed bootstrap sync restores pacman.conf and records nothing"
TEST_POINTER=pointer-3 TEST_INCLUDED_REPOSITORY=testing run bootstrap-order --yes --bootstrap
expect_status bootstrap-order 2 "a bootstrap that does not lead the repositories fails"
grep -Fq '[omarchy] does not come before every other repository; restored the previous repository' "$test_tmp/bootstrap-order.err" ||
  fail "a bootstrap behind an included repository explains the restore" "$(cat "$test_tmp/bootstrap-order.err")"
[[ $(cat "$pacman_conf") == "$original" && ! -e $state ]] || fail "a bootstrap behind an included repository restores pacman.conf"
pass "a bootstrap pacman cannot read, or one pacman would not put first, restores pacman.conf"

# A sync can succeed before the order check fails: the rollback must not leave the new
# Server's database cached under the restored one.
write_bootstrap_conf "$(printf '[omarchy]\nSigLevel = Required DatabaseOptional\nServer = %s' "$old_server")"
original=$(cat "$pacman_conf")
rm -f "$sync_dir/omarchy.db" "$sync_dir/omarchy.db.sig"
TEST_POINTER=pointer-3 TEST_INCLUDED_REPOSITORY=testing TEST_PACMAN_SYNC_DIR="$sync_dir" run bootstrap-order-after-sync --yes --bootstrap
expect_status bootstrap-order-after-sync 2 "a bootstrap that advanced and then failed the order check fails"
[[ $(cat "$pacman_conf") == "$original" ]] || fail "the advanced pin is restored after the order check fails"
[[ ! -e $sync_dir/omarchy.db && ! -e $sync_dir/omarchy.db.sig ]] ||
  fail "the rollback leaves the new Server's database cached under the restored Server"
pass "a rollback after a successful sync drops the new Server's cached database"

write_bootstrap_conf "$(printf '[omarchy]\nSigLevel = Never\nServer = %s' "$old_server")"
seed_sync_cache
TEST_POINTER=pointer-3 run bootstrap-superseded --yes --bootstrap
expect_status bootstrap-superseded 0 "a superseded pin is bootstrapped"
[[ $(cat "$pacman_conf") == "$(bootstrapped_conf "$new_server")" ]] ||
  fail "a superseded pin after [aur] is moved first, repaired and moved forward" "$(diff <(bootstrapped_conf "$new_server") "$pacman_conf" || true)"
[[ ! -e $sync_dir/omarchy.db ]] || fail "moving a pin forward drops its cached database"
grep -Fxq "tag=$new_tag" "$state" || fail "moving a pin forward records the channel's set"
rm -f "$state"
write_bootstrap_conf "$(printf '[omarchy]\nSigLevel = Never\nServer = %s\nServer = %s' "$old_server" "$old_server")" extra
TEST_POINTER=pointer-3 run bootstrap-duplicates --yes --bootstrap
expect_status bootstrap-duplicates 0 "byte-identical Servers are one Server"
[[ $(cat "$pacman_conf") == "$(bootstrapped_conf "$new_server")" ]] || fail "byte-identical Servers collapse into one"
rm -f "$state"
pass "a recognised pin keeps the ordinary move rules after its section is repaired and moved first"

for kept in "$candidate_server" "$mirror_server" "$hand_server"; do
  write_bootstrap_conf "$(printf '[omarchy]\nSigLevel = Never\nServer = %s' "$kept")" alarm
  seed_sync_cache
  rm -f "$test_tmp"/key-trusted*
  TEST_POINTER=pointer-3 run bootstrap-kept --yes --bootstrap
  expect_status bootstrap-kept 0 "a bootstrap keeps a Server it does not move ($kept)"
  [[ $(cat "$pacman_conf") == "$(bootstrapped_conf "$kept")" ]] ||
    fail "a kept Server's section is moved first and repaired ($kept)" "$(diff <(bootstrapped_conf "$kept") "$pacman_conf" || true)"
  [[ -e $sync_dir/omarchy.db ]] || fail "a kept Server keeps its cached database ($kept)"
  [[ ! -e $state ]] || fail "a kept Server is never recorded as the channel's set ($kept)" "$(cat "$state")"
  grep -Fxq "pacman-key:--lsign-key $release_fingerprint" "$calls" && grep -Fxq "pacman-key:--lsign-key $primary_fingerprint" "$calls" ||
    fail "a kept Server still gets both keys trusted ($kept)"
  grep -Fxq 'pacman:-Sy --noconfirm OMARCHY_UPDATE_PACMAN=1' "$calls" || fail "a kept Server is synced ($kept)"
  fetched "https://github.com/$repo/releases/download/$new_tag/omarchy.db.sig" ||
    fail "a kept Server does not skip verifying the channel's database ($kept)"
  grep -Fq "Kept the Apple Silicon package repository on $kept" "$test_tmp/bootstrap-kept.out" ||
    fail "a kept Server is reported ($kept)" "$(cat "$test_tmp/bootstrap-kept.out")"
done
pass "a candidate, mirror or newer pin keeps its Server while its section is repaired and moved first"

write_bootstrap_conf "$(canonical_block "$new_server")" asahi-alarm
original=$(cat "$pacman_conf")
TEST_POINTER=pointer-3 run bootstrap-current --yes --bootstrap
expect_status bootstrap-current 0 "a bootstrap on the channel's set succeeds"
[[ $(cat "$pacman_conf") == "$original" ]] || fail "a bootstrap on the channel's set leaves pacman.conf as it was"
fetched "https://github.com/$repo/releases/download/$new_tag/omarchy.db" ||
  fail "a bootstrap on the channel's set still verifies its database"
grep -Fxq 'pacman:-Sy --noconfirm OMARCHY_UPDATE_PACMAN=1' "$calls" && ! grep -q '^sudo:rm ' "$calls" ||
  fail "a bootstrap on the channel's set syncs without dropping its cache" "$(cat "$calls")"
grep -Fxq "tag=$new_tag" "$state" || fail "a bootstrap on the channel's set records it"
pass "a bootstrap bypasses the up-to-date exit"

write_state "$new_commit" 5
state_before=$(state_digest)
write_bootstrap_conf
original=$(cat "$pacman_conf")
TEST_POINTER=pointer-3 TEST_API=up run bootstrap-floor --yes --bootstrap
expect_status bootstrap-floor 2 "a bootstrap below this Mac's channel writes nothing"
grep -Fq 'package channel 3 is older than channel 5 recorded on this Mac; nothing changed' "$test_tmp/bootstrap-floor.err" ||
  fail "a bootstrap below this Mac's channel explains itself" "$(cat "$test_tmp/bootstrap-floor.err")"
[[ $(cat "$pacman_conf") == "$original" && ! -s $calls && $(state_digest) == "$state_before" ]] ||
  fail "a bootstrap below this Mac's channel changes nothing"
write_bootstrap_conf "$(canonical_block "$new_server")" asahi-alarm
TEST_POINTER=pointer-3 TEST_API=up run bootstrap-floor-kept --yes --bootstrap
expect_status bootstrap-floor-kept 0 "a bootstrap below this Mac's channel keeps the existing Server"
[[ $(state_digest) == "$state_before" ]] || fail "a bootstrap below this Mac's channel never lowers its record"
rm -f "$state"
pass "a bootstrap never follows a channel below the one this Mac recorded"

for shape in sections servers none; do
  case $shape in
    sections) write_bootstrap_conf "$(canonical_block "$new_server")"$'\n\n'"$(canonical_block "$old_server")" asahi-alarm ;;
    servers) write_bootstrap_conf "$(printf '[omarchy]\nSigLevel = Required DatabaseOptional\nServer = %s\nServer = %s' "$new_server" "$mirror_server")" asahi-alarm ;;
    none) write_bootstrap_conf "$(printf '[omarchy]\nSigLevel = Required DatabaseOptional')" asahi-alarm ;;
  esac
  original=$(cat "$pacman_conf")
  TEST_POINTER=pointer-3 run "bootstrap-$shape" --yes --bootstrap
  expect_status "bootstrap-$shape" 2 "an ambiguous [omarchy] ($shape) is refused"
  untouched "bootstrap-$shape" "an ambiguous [omarchy] ($shape)" "$original"
  [[ ! -s $test_tmp/curl.log ]] || fail "an ambiguous [omarchy] ($shape) is refused before anything is fetched"
done
grep -Fxq "  $new_server" "$test_tmp/bootstrap-servers.err" && grep -Fxq "  $mirror_server" "$test_tmp/bootstrap-servers.err" ||
  fail "several Servers are named in the refusal" "$(cat "$test_tmp/bootstrap-servers.err")"
pass "several sections, several Servers or no Server are refused untouched"

write_bootstrap_conf
original=$(cat "$pacman_conf")
TEST_POINTER=pointer-3 TEST_GPG_FAIL=1 run bootstrap-badsig --yes --bootstrap
expect_status bootstrap-badsig 2 "a bootstrap with a bad descriptor signature fails closed"
untouched bootstrap-badsig "a bootstrap with a bad descriptor signature" "$original"
cp "$assets/$new_tag/omarchy.db" "$test_tmp/omarchy.db.good"
printf 'tampered\n' >"$assets/$new_tag/omarchy.db"
TEST_POINTER=pointer-3 run bootstrap-baddb --yes --bootstrap
expect_status bootstrap-baddb 2 "a bootstrap with a database the descriptor does not name fails closed"
grep -Fq 'omarchy.db does not match the signed descriptor' "$test_tmp/bootstrap-baddb.err" ||
  fail "a mismatched database explains the refusal" "$(cat "$test_tmp/bootstrap-baddb.err")"
untouched bootstrap-baddb "a bootstrap with a mismatched database" "$original"
cp "$test_tmp/omarchy.db.good" "$assets/$new_tag/omarchy.db"
TEST_POINTER=unreachable TEST_API=down run bootstrap-offline --yes --bootstrap
expect_status bootstrap-offline 3 "an unreachable package channel stops a bootstrap"
untouched bootstrap-offline "an unreachable package channel" "$original"
pass "a bootstrap writes nothing unless the channel, descriptor and database all verify"

# --- Fresh installation flow --------------------------------------------------
# The fresh installer's own bootstrap step, run with the real updater and then
# the real install/hardware/pacman.sh: system setup must leave the Server the
# bootstrap kept, or the channel's stable set when there was none.
if (( EUID != 0 )); then
  pass "not root; skipping the fresh installation flow, whose sudo stand-in only runs as root"
else
  require_command bsdtar
  fresh_installer="$ROOT/bin/omarchy-install-asahi-fresh"
  configure_function=$(sed -n '/^configure_package_repository() {$/,/^}$/p' "$fresh_installer")
  [[ -n $configure_function ]] || fail "the fresh installer defines its repository bootstrap as a function"
  flow="$test_tmp/flow"
  mkdir -p "$flow/dev/usr/bin" "$flow/settings/usr/share/omarchy/default" "$flow/setup-bin"
  # The runtime puts its usr/bin ahead of the system's, so these stand-ins for
  # the network, gpg, the keyring and pacman shadow the real tools; sudo is the
  # installer's own stand-in.
  cp "$updater" "$flow/dev/usr/bin/omarchy-update-asahi-repository"
  cp "$stub_bin"/{omarchy-cmd-present,curl,gpg,pacman-key,pacman,pacman-conf} "$flow/dev/usr/bin/"
  cat >"$flow/dev/usr/bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
grep -aq 'apple,' "${OMARCHY_PROC_ROOT:-/proc}/device-tree/compatible"
SH
  chmod +x "$flow/dev/usr/bin/"*
  cp "$test_tmp/omarchy-release.gpg" "$test_tmp/omarchy-arm-repository.asc" "$flow/settings/usr/share/omarchy/default/"
  dev_archive="$flow/omarchy-dev-4.0.3-1-aarch64.pkg.tar.zst"
  settings_archive="$flow/omarchy-settings-dev-4.0.3-1-any.pkg.tar.zst"
  bsdtar -cf "$dev_archive" -C "$flow/dev" usr
  bsdtar -cf "$settings_archive" -C "$flow/settings" usr
  printf '#!/bin/bash\nexit 0\n' >"$flow/setup-bin/omarchy-hw-apple-silicon"
  printf '#!/bin/bash\nexit 0\n' >"$flow/setup-bin/lspci"
  chmod +x "$flow/setup-bin/"*

  fresh_flow() {
    local name="$1"
    : >"$calls"
    : >"$test_tmp/curl.log"
    rm -f "$test_tmp"/key-trusted*
    (
      fail() { echo "fresh installer: $*" >&2; exit 1; }
      eval "$configure_function"
      export TEST_ASSETS="$assets" TEST_CURL_LOG="$test_tmp/curl.log" TEST_POINTER_ARGS="$test_tmp/pointer-args" \
        TEST_API_HITS="$test_tmp/api-hits" TEST_CALLS="$calls" TEST_KEY_STATE="$test_tmp/key-trusted" TEST_POINTER=pointer-3 \
        OMARCHY_ASAHI_TESTING=1 OMARCHY_ASAHI_ROOT="$root" OMARCHY_ASAHI_REPOSITORY_STATE="$state" \
        OMARCHY_ASAHI_PACKAGES_POINTER_URL="$pointer_url" OMARCHY_ASAHI_RELEASES_API_URL="$api_url" \
        OMARCHY_PROC_ROOT="$root/proc" PATH="$stub_bin:$PATH"
      configure_package_repository "$pacman_conf" "$settings_archive" "$dev_archive"
      [[ ! -e $package_runtime_root ]] || fail "the unpacked runtime is removed"
      [[ -z ${OMARCHY_ASAHI_PACKAGE_KEY_FILE:-}${OMARCHY_ASAHI_KEY_FILE:-} ]] || fail "the runtime's key files stay with the updater"
      # System setup: omarchy-apply-system sources this writer with the installed runtime.
      OMARCHY_PATH="$flow/settings/usr/share/omarchy" OMARCHY_PACMAN_CONF="$pacman_conf" PATH="$flow/setup-bin:$PATH" \
        bash -euo pipefail -c 'source "$1"' _ "$ROOT/install/hardware/pacman.sh"
    ) >"$test_tmp/flow-$name.out" 2>&1 || fail "the fresh installation flow succeeds ($name)" "$(cat "$test_tmp/flow-$name.out")"
    ! grep -q '^sudo:' "$calls" || fail "the updater runs through the installer's sudo stand-in, not a test stub ($name)"
    [[ $(awk '/^[[:space:]]*\[[^]]+\][[:space:]]*$/ && !/\[options\]/ { print; exit }' "$pacman_conf") == "[omarchy]" ]] ||
      fail "[omarchy] leads the repositories after system setup ($name)" "$(cat "$pacman_conf")"
  }

  # DBPath keeps both writers' cache handling inside the test root.
  write_bootstrap_conf
  sed -i "s|^Architecture = aarch64\$|&\nDBPath = $root/var/lib/pacman/|" "$pacman_conf"
  fresh_flow none
  [[ $(awk '/^Server = /' "$pacman_conf") == "Server = $new_server" ]] ||
    fail "a fresh installation without a pin ends on the channel's stable set" "$(cat "$pacman_conf")"
  grep -Fxq "tag=$new_tag" "$state" || fail "a fresh installation without a pin records the channel's set"
  rm -f "$state"
  for kept in "$candidate_server" "$mirror_server"; do
    write_bootstrap_conf "$(canonical_block "$kept")" extra
    sed -i "s|^Architecture = aarch64\$|&\nDBPath = $root/var/lib/pacman/|" "$pacman_conf"
    fresh_flow kept
    [[ $(awk '/^Server = /' "$pacman_conf") == "Server = $kept" ]] ||
      fail "a fresh installation ends on the Server the operator pinned ($kept)" "$(cat "$pacman_conf")"
    [[ ! -e $state ]] || fail "a fresh installation on a kept Server records no promoted set ($kept)"
  done
  pass "a fresh installation keeps a pinned candidate or mirror through system setup, and otherwise ends on the channel's set"
fi
