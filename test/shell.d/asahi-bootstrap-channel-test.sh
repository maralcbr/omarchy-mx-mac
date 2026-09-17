#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

bootstrap="$ROOT/install-omarchy-mx-mac"
wrapper="$ROOT/install-omarchy-mx-mac.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/tmp"

bash -n "$bootstrap"

grep -Fq '[[ $(uname -m) == "aarch64" ]] || fail "Omarchy MX Mac requires aarch64"' "$bootstrap" ||
  fail "bootstrap keeps its architecture boundary"
grep -Fq "grep -aq 'apple,' /proc/device-tree/compatible" "$bootstrap" ||
  fail "bootstrap keeps its Apple Silicon boundary"
grep -Fq 'https://downloads.aicodelabs.com.au/pointers/asahi-quattro-channel' "$bootstrap" ||
  fail "bootstrap reads the published release channel pointer by default"
pointer_line=$(grep -nF 'https://downloads.aicodelabs.com.au/pointers/' "$bootstrap" | cut -d: -f1)
api_line=$(grep -nF 'api.github.com' "$bootstrap" | cut -d: -f1)
[[ -n $pointer_line && -n $api_line ]] && (( pointer_line < api_line )) ||
  fail "bootstrap tries its R2 pointer before the GitHub API"
# The silent fall back to the frozen un-numbered release is what pinned new
# installs to sequence 21 whenever the API answered with anything unexpected.
! grep -Eq 'channel_release_tag=asahi-quattro-channel$|=asahi-quattro-channel"?$' "$bootstrap" ||
  fail "bootstrap no longer falls back to the un-numbered legacy channel release"
pass "bootstrap discovery is pointer first, listing second, and never the legacy release"

api_users=$(cd "$ROOT" && grep -rlF 'api.github.com' bin install install-omarchy-mx-mac install-omarchy-mx-mac.sh migrations test/vm | sort)
[[ $api_users == $'bin/omarchy-update-asahi-bundle\nbin/omarchy-update-asahi-repository\ninstall-omarchy-mx-mac\ntest/vm/asahi-fresh/guest/install' ]] ||
  fail "only the documented listing fallbacks read the GitHub API" "$api_users"
harness_pointer_line=$(grep -nF 'https://downloads.aicodelabs.com.au/pointers/' "$ROOT/test/vm/asahi-fresh/guest/install" | cut -d: -f1)
harness_api_line=$(grep -nF 'api.github.com' "$ROOT/test/vm/asahi-fresh/guest/install" | cut -d: -f1)
[[ -n $harness_pointer_line ]] && (( harness_pointer_line < harness_api_line )) ||
  fail "the VM harness tries its R2 pointer before the GitHub API"
pass "the GitHub API is only a documented fallback behind a pointer"

# The hardware boundary is real on a Mac and unreachable here, so it is replaced
# the way the VM harness replaces the installer's own.
runnable="$test_tmp/install-omarchy-mx-mac"
sed -e '/^\[\[ \$(uname -m) == "aarch64" \]\] || fail /c\true # test-only hardware boundary' \
  -e "/^grep -aq 'apple,' \/proc\/device-tree\/compatible /c\\true # test-only hardware boundary" \
  "$bootstrap" >"$runnable"

cat >"$test_tmp/installer-stub" <<'STUB'
#!/bin/bash
{
  printf 'args=%s\n' "$*"
  printf 'channel_tag=%s\n' "${ASAHI_QUATTRO_CHANNEL_TAG:-}"
  printf 'identity_file=%s\n' "${ASAHI_QUATTRO_IDENTITY_FILE:-}"
} >>"$INVOCATION_LOG"
# A current installer records the release it resolved so the run that installs
# can be held to the one that was verified; an older asset records nothing.
if [[ ${INSTALLER_RECORDS_RELEASE:-1} == 1 && -n ${ASAHI_QUATTRO_IDENTITY_FILE:-} ]]; then
  grep -q '^release_tag=' "$ASAHI_QUATTRO_IDENTITY_FILE" ||
    printf 'release_tag=%s\n' "${STUB_RESOLVED_RELEASE:-asahi-quattro-abcd1234}" >>"$ASAHI_QUATTRO_IDENTITY_FILE"
fi
STUB

cat >"$test_tmp/bin/curl" <<'EOF'
#!/bin/bash
url="" output=""
while (($#)); do
  case "$1" in
    --output|-o) output=$2; shift ;;
    https://*) url=$1 ;;
  esac
  shift
done
printf '%s\n' "$url" >>"$CURL_LOG"
case "$url" in
  *"/pointers/"*)
    (( ${POINTER_STATUS:-0} == 0 )) || exit "${POINTER_STATUS}"
    if [[ -n ${POINTER_SEQUENCE:-} ]]; then
      printf 'format=1\nsequence=%s\ntag=asahi-quattro-channel-%s\n' "$POINTER_SEQUENCE" "$POINTER_SEQUENCE" >"$output"
    else
      printf '%s' "${POINTER_BODY:-}" >"$output"
    fi
    ;;
  *api.github*)
    (( ${API_STATUS:-0} == 0 )) || exit "${API_STATUS}"
    if [[ -n $output ]]; then printf '%s' "${API_BODY:-}" >"$output"; else printf '%s' "${API_BODY:-}"; fi
    ;;
  */install-asahi-quattro)
    cp "$INSTALLER_STUB" "$output"
    ;;
  *)
    : >"$output"
    ;;
esac
EOF

cat >"$test_tmp/bin/gpg" <<'EOF'
#!/bin/bash
for argument in "$@"; do
  [[ $argument == "--show-keys" ]] || continue
  printf 'fpr:::::::::%s:\n' "${GPG_FINGERPRINT:-5983B1CA32CB778F4D74D24ECFF35022CA5B5959}"
  exit 0
done
exit 0
EOF

chmod +x "$test_tmp/bin"/* "$test_tmp/installer-stub"

pointer_url="https://downloads.example.test/pointers/asahi-quattro-channel"
api_url="https://api.github.test/repos/example/releases?per_page=100"
curl_log="$test_tmp/curl.log"
invocations="$test_tmp/invocations"

api_listing() {
  printf '[{"tag_name": "asahi-quattro-channel-%s"},{"tag_name": "asahi-quattro-channel-1"}]' "$1"
}

# Leading NAME=VALUE arguments configure the stubs; the rest reach the bootstrap.
run_bootstrap() {
  local assignments=()
  while (($#)) && [[ $1 == *=* && $1 != -* ]]; do
    assignments+=("$1")
    shift
  done
  : >"$curl_log"
  env -u POINTER_SEQUENCE -u POINTER_BODY -u POINTER_STATUS -u API_BODY -u API_STATUS -u INSTALLER_RECORDS_RELEASE -u OMARCHY_PACKAGE_RELEASE_BASE_URL -u ASAHI_QUATTRO_CHANNEL_TAG \
    -u ASAHI_QUATTRO_RELEASE_TAG -u OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE \
    PATH="$test_tmp/bin:$(dirname "$BASH"):/usr/bin:/bin" \
    TMPDIR="$test_tmp/tmp" \
    CURL_LOG="$curl_log" \
    INVOCATION_LOG="$invocations" \
    INSTALLER_STUB="$test_tmp/installer-stub" \
    OMARCHY_ASAHI_CHANNEL_POINTER_URL="$pointer_url" \
    OMARCHY_ASAHI_RELEASES_API_URL="$api_url" \
    "${assignments[@]}" "$BASH" "$runnable" "$@"
}

installer_source() {
  grep -F '/install-asahi-quattro' "$curl_log" | grep -v '\.sig$' | tail -1
}

# --- Discovery ---------------------------------------------------------------

: >"$invocations"
run_bootstrap POINTER_SEQUENCE=35 API_STATUS=7 >/dev/null
[[ $(installer_source) == "https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-quattro-channel-35/install-asahi-quattro" ]] ||
  fail "the pointer selects the channel the installer is fetched from" "$(cat "$curl_log")"
! grep -Fq 'api.github' "$curl_log" || fail "a usable pointer makes no GitHub API call"
pass "the pointer alone selects the release channel"

run_bootstrap POINTER_STATUS=22 API_BODY="$(api_listing 33)" >/dev/null
[[ $(installer_source) == *"/asahi-quattro-channel-33/install-asahi-quattro" ]] ||
  fail "an unreachable pointer falls back to the release listing"
pass "an unreachable pointer falls back to the GitHub release listing"

run_bootstrap POINTER_BODY='format=1
sequence=35
tag=asahi-quattro-channel-36
' API_BODY="$(api_listing 33)" 2>"$test_tmp/malformed.err" >/dev/null
[[ $(installer_source) == *"/asahi-quattro-channel-33/install-asahi-quattro" ]] ||
  fail "a malformed pointer falls back to the release listing"
grep -Fq 'Release channel pointer is malformed' "$test_tmp/malformed.err" ||
  fail "a malformed pointer is reported"
pass "a malformed pointer is reported and the listing is used"

: >"$invocations"
if run_bootstrap POINTER_STATUS=22 API_STATUS=7 >"$test_tmp/nodiscovery.out" 2>&1; then
  fail "an undiscoverable channel fails the bootstrap"
fi
grep -Fq 'Could not discover the release channel' "$test_tmp/nodiscovery.out" ||
  fail "an undiscoverable channel says so" "$(cat "$test_tmp/nodiscovery.out")"
[[ ! -s $invocations ]] || fail "an undiscoverable channel runs no installer"
pass "neither a pointer nor a listing fails instead of pinning the legacy release"

run_bootstrap POINTER_STATUS=7 API_STATUS=7 \
  OMARCHY_PACKAGE_RELEASE_BASE_URL="https://downloads.example.test/pinned" >/dev/null
[[ $(installer_source) == "https://downloads.example.test/pinned/install-asahi-quattro" ]] ||
  fail "an explicit base URL is used as given"
! grep -Fq '/pointers/' "$curl_log" || fail "an explicit base URL reads no pointer"
pass "an explicit release base URL overrides discovery"

# --- Handover between the wrapper's two runs ---------------------------------

identity="$test_tmp/channel-identity"

run_pair() {
  local first_env=("${!1}") second_env=("${!2}")
  : >"$identity"
  : >"$invocations"
  run_bootstrap OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE="$identity" "${first_env[@]}" --verify-only >/dev/null 2>"$test_tmp/first.err"
  run_bootstrap OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE="$identity" "${second_env[@]}" >/dev/null 2>"$test_tmp/second.err"
}

discovery_first=(POINTER_SEQUENCE=35)
discovery_second=(POINTER_SEQUENCE=36)
run_pair discovery_first[@] discovery_second[@]
grep -Fxq 'selector=channel' "$identity" || fail "a discovered channel is recorded as a channel selection"
grep -Fxq 'value=asahi-quattro-channel-35' "$identity" || fail "the verified channel is recorded"
grep -Fxq 'release_tag=asahi-quattro-abcd1234' "$identity" || fail "the installer records the release it resolved"
[[ $(installer_source) == *"/asahi-quattro-channel-35/install-asahi-quattro" ]] ||
  fail "a pointer that advances between the runs does not change the channel installed"
[[ $(grep -c '^channel_tag=asahi-quattro-channel-35$' "$invocations") == 2 ]] ||
  fail "both runs hand the same channel to the installer"
[[ $(grep -c "^identity_file=$identity\$" "$invocations") == 2 ]] ||
  fail "both runs hand the installer the wrapper's identity file"
pass "a pointer that advances between the two runs installs the channel that was verified"

channel_env=(ASAHI_QUATTRO_CHANNEL_TAG=asahi-quattro-channel-31)
run_pair channel_env[@] channel_env[@]
grep -Fxq 'value=asahi-quattro-channel-31' "$identity" || fail "an explicit channel tag is recorded"
! grep -Fq '/pointers/' "$curl_log" || fail "an explicit channel tag reads no pointer"
pass "an explicit channel tag is honoured by both runs"

release_env=(ASAHI_QUATTRO_RELEASE_TAG=asahi-quattro-fe8d2bf8 INSTALLER_RECORDS_RELEASE=0 POINTER_SEQUENCE=35)
run_pair release_env[@] release_env[@]
grep -Fxq 'selector=release' "$identity" || fail "an explicit release is recorded as a release selection"
grep -Fxq 'value=asahi-quattro-fe8d2bf8' "$identity" || fail "the explicit release is recorded"
grep -q '^args=.*--verify-only' "$invocations" || fail "the verification run still runs"
[[ $(grep -c '^args=' "$invocations") == 2 ]] || fail "an explicit release needs no recorded release to install"
pass "an exact release is installed by both runs without a recorded release"

base_env=(OMARCHY_PACKAGE_RELEASE_BASE_URL="https://downloads.example.test/pinned")
run_pair base_env[@] base_env[@]
grep -Fxq 'selector=base-url' "$identity" || fail "an explicit base URL is recorded as a base-url selection"
grep -Fxq 'value=https://downloads.example.test/pinned' "$identity" || fail "the explicit base URL is recorded"
[[ $(grep -c '^args=' "$invocations") == 2 ]] || fail "a pinned base URL installs after verifying"
pass "a pinned installer asset URL is recorded and reused"

# A pinned URL only chooses which installer asset runs; an asset that does not
# record what it resolved could verify one release and install a later one.
old_base=(OMARCHY_PACKAGE_RELEASE_BASE_URL="https://downloads.example.test/pinned" INSTALLER_RECORDS_RELEASE=0)
: >"$identity"
: >"$invocations"
run_bootstrap OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE="$identity" "${old_base[@]}" --verify-only >/dev/null
if run_bootstrap OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE="$identity" "${old_base[@]}" >"$test_tmp/norecord.out" 2>&1; then
  fail "an installer that records no release refuses the installation run"
fi
grep -Fq 'does not record its release' "$test_tmp/norecord.out" ||
  fail "an unrecorded release says to pass --release-tag" "$(cat "$test_tmp/norecord.out")"
[[ $(grep -c '^args=' "$invocations") == 1 ]] || fail "an unrecorded release runs no second installer"
pass "a verification run that recorded no release refuses to install"

: >"$identity"
run_bootstrap OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE="$identity" \
  OMARCHY_PACKAGE_RELEASE_BASE_URL="https://downloads.example.test/pinned" --verify-only >/dev/null
if run_bootstrap OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE="$identity" \
  OMARCHY_PACKAGE_RELEASE_BASE_URL="https://downloads.example.test/other" >"$test_tmp/mismatch.out" 2>&1; then
  fail "a changed explicit override refuses the installation run"
fi
grep -Fq 'were given different releases' "$test_tmp/mismatch.out" ||
  fail "a changed explicit override says the runs disagree" "$(cat "$test_tmp/mismatch.out")"
pass "an explicit override that changes between the runs is refused"

: >"$identity"
run_bootstrap OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE="$identity" \
  ASAHI_QUATTRO_RELEASE_TAG=asahi-quattro-fe8d2bf8 POINTER_SEQUENCE=35 --verify-only >/dev/null
if run_bootstrap OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE="$identity" \
  POINTER_SEQUENCE=35 >"$test_tmp/unpinned.out" 2>&1; then
  fail "an installation run that drops the verification run's pin is refused"
fi
grep -Fq 'was pinned to a release and this run was not' "$test_tmp/unpinned.out" ||
  fail "dropping the pin explains itself" "$(cat "$test_tmp/unpinned.out")"
pass "an installation run that drops the verification run's exact release is refused"

printf 'format=2\nselector=channel\nvalue=asahi-quattro-channel-35\n' >"$identity"
if run_bootstrap OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE="$identity" \
  POINTER_SEQUENCE=35 >"$test_tmp/malformed-identity.out" 2>&1; then
  fail "a malformed handover file is refused"
fi
grep -Fq 'release identity handed over by the wrapper is malformed' "$test_tmp/malformed-identity.out" ||
  fail "a malformed handover file says so"
printf 'format=1\nselector=channel\nvalue=asahi-quattro-channel-0\n' >"$identity"
if run_bootstrap OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE="$identity" \
  POINTER_SEQUENCE=35 >/dev/null 2>&1; then
  fail "a handover value that fails its selector's pattern is refused"
fi
pass "a malformed handover file is refused without installing"

: >"$invocations"
run_bootstrap POINTER_SEQUENCE=35 --user example >/dev/null
[[ $(grep -c '^identity_file=$' "$invocations") == 1 ]] ||
  fail "a direct run hands the installer no identity file"
grep -q '^args=.*--user example$' "$invocations" || fail "a direct run forwards its arguments"
pass "a direct run of the bootstrap behaves as before"

# --- The wrapper owns the handover file --------------------------------------

bash -n "$wrapper"
grep -Fq 'export OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE="$identity_file"' "$wrapper" ||
  fail "the wrapper exports the handover file it owns"
grep -Fq 'identity_file="$work_dir/channel-identity"' "$wrapper" ||
  fail "the wrapper keeps the handover file in its own work directory"
grep -Fq ': >"$identity_file"' "$wrapper" ||
  fail "the wrapper starts the handover file empty"
grep -Fq 'bash install-omarchy-mx-mac --verify-only "$@"' "$wrapper" ||
  fail "the wrapper forwards its arguments to the verification run"
pass "the wrapper owns the handover file and pins both of its runs"
