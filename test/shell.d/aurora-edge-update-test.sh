#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command sha256sum
require_command jq
require_command flock

updater="$ROOT/bin/omarchy-update-aurora-repository"
subkey_fingerprint=CAB18E175BFB9ACCE185234474DE0C737AC186E4
repo=maralcbr/omarchy-pkgs
downloads="https://github.com/$repo/releases/download"
pointer_url=https://downloads.aicodelabs.com.au/pointers/aurora-edge-channel
api_url="https://api.github.com/repos/$repo/releases?per_page=100"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
assets="$test_tmp/assets"
root="$test_tmp/root"
omarchy_path="$test_tmp/omarchy"
state_dir="$root/var/lib/omarchy"
record="$state_dir/apple-silicon-channel"
lane_file="$state_dir/apple-silicon-aurora-lane"
staged="$state_dir/aurora-target.descriptor"
pacman_conf="$root/etc/pacman.conf"
sync_dir="$root/var/lib/pacman/sync"
calls="$test_tmp/calls"
channel_calls="$test_tmp/channel-calls"
curl_log="$test_tmp/curl.log"
versions="$test_tmp/versions"
targets="$test_tmp/targets"
reboot_blocked="$test_tmp/reboot-blocked"
old_tag=aurora-packages-412375933f5c94b304708576c9999c4cf5f88700
pin_tag=aurora-packages-1c5e34c99dc2510bf06c673165a79aa92c8f1f4c
candidate_tag=aurora-packages-4439238d23d28c8d3766a6dd040a9e5f9fd587e0
mkdir -p "$stub_bin" "$assets/api" "$root/etc" "$state_dir" "$sync_dir" "$omarchy_path/default" "$root/usr/share/omarchy"
chmod 0755 "$state_dir"
printf 'linux-aurora\n' >"$root/usr/share/omarchy/apple-silicon-kernel"
printf 'fixture key\n' >"$omarchy_path/default/omarchy-arm-repository.asc"

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$stub_bin/omarchy-update-lock" <<'SH'
#!/bin/bash
if [[ $1 == "held" ]]; then
  [[ ${TEST_LOCK_HELD:-1} == 1 ]]
  exit
fi
shift
TEST_LOCK_HELD=1 exec bash "$@"
SH
cat >"$stub_bin/omarchy-apple-silicon-boot-check" <<'SH'
#!/bin/bash
echo "boot-check $*" >>"$TEST_CALLS"
[[ ${TEST_BOOT_STATUS:-0} == 0 ]] || echo "Aurora boot check: m1n1/boot.bin on the system ESP is stale" >&2
exit "${TEST_BOOT_STATUS:-0}"
SH
# The pointer, the release listing pages and release assets, all from the fixture.
cat >"$stub_bin/curl" <<'SH'
#!/bin/bash
output="" url="" max_filesize=""
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
case "$url" in
  "https://downloads.aicodelabs.com.au/pointers/aurora-edge-channel") file=$TEST_ASSETS/pointer ;;
  "https://api.github.com/repos/maralcbr/omarchy-pkgs/releases?per_page=100&page="*) file=$TEST_ASSETS/api/page-${url##*page=}.json ;;
  "https://github.com/maralcbr/omarchy-pkgs/releases/download/"*) file=$TEST_ASSETS/${url#https://github.com/maralcbr/omarchy-pkgs/releases/download/} ;;
  *) exit 6 ;;
esac
[[ -f $file ]] || exit 22
if [[ -n $max_filesize ]] && (( $(wc -c <"$file") > max_filesize )); then
  exit 63
fi
cp "$file" "$output"
SH
cat >"$stub_bin/gpg" <<'SH'
#!/bin/bash
primary=C81AC3E2A99556F9B21D5FEA3DD49BC9F8360BDC
subkey=CAB18E175BFB9ACCE185234474DE0C737AC186E4
if [[ " $* " == *" --show-keys "* ]]; then
  printf 'pub:-:255:22:%s:::::::cSC::::::::0:\nfpr:::::::::%s:\n' "${primary:24}" "$primary"
  exit 0
fi
[[ " $* " != *" --import "* ]] || exit 0
if [[ " $* " == *" --list-keys "* ]]; then
  printf 'pub:-:255:22:%s:::::::cSC::::::::0:\nfpr:::::::::%s:\nsub:-:255:22:%s:::::::s::::::::0:\nfpr:::::::::%s:\n' \
    "${primary:24}" "$primary" "${subkey:24}" "$subkey"
  exit 0
fi
[[ ${TEST_GPG_FAIL:-0} != 1 ]] || exit 1
echo "[GNUPG:] VALIDSIG $subkey 2026-01-01 0 4 0 1 22 00 $primary"
SH
# The channel helper's own writes are logged apart from pacman.conf's. Staging
# the descriptor can be made to fail, and the pacman.conf install to kill the
# updater outright, the way a power loss would.
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
if [[ $* == *apple-silicon-channel* || $* == *apple-silicon-aurora-lane* || $* == *aurora-target.descriptor* ]]; then
  printf 'sudo:%s\n' "$*" >>"$TEST_CHANNEL_CALLS"
  if [[ $1 == mktemp && $* == *aurora-target.descriptor* && ${TEST_FAIL_STAGE:-0} == 1 ]]; then
    exit 1
  fi
  exec "$@"
fi
printf 'sudo:%s\n' "$*" >>"$TEST_CALLS"
if [[ $1 == "install" && $* == *.omarchy-aurora && ${TEST_INTERRUPT_INSTALL:-0} == 1 ]]; then
  kill -KILL "$PPID"
  exit 1
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
cat >"$stub_bin/chown" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$stub_bin/pacman-key" <<'SH'
#!/bin/bash
[[ $1 != "--finger" ]]
SH
# Installed versions come from the fixture, as pacman -Q prints them.
cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
if [[ $* == "-Qq" ]]; then
  printf '%s\n' linux-aurora linux-aurora-headers m1n1-aurora
  exit 0
fi
if [[ $1 == "-Q" && $# == 2 ]]; then
  version=$(awk -v name="$2" '$1 == name { print $2 }' "$TEST_VERSIONS")
  [[ -n $version ]] || exit 1
  echo "$2 $version"
  exit 0
fi
printf 'pacman:%s\n' "$*" >>"$TEST_CALLS"
SH
chmod +x "$stub_bin"/*

# A signed descriptor in the format aurora-package-descriptor writes; edge ones
# carry the sequence, and $2 overrides any field to break a cross-check.
write_release() {
  local tag=$1 extra=${2:-} kernel channel=aurora sequence=""
  if [[ $tag == aurora-edge-* ]]; then
    channel=aurora-edge sequence=${tag#aurora-edge-} kernel=6.18.0.aurora1.$sequence-1
  else
    kernel=6.17.0.aurora1-1
  fi
  mkdir -p "$assets/$tag"
  {
    printf 'format=1\nchannel=%s\nrelease_tag=%s\n' "$channel" "$tag"
    [[ -z $sequence ]] || printf 'sequence=%s\naurora_commit=%040d\nsource_sha256=%064d\n' "$sequence" "$sequence" "$sequence"
    printf 'source_commit=%040d\nworkflow_run=1\nrunner_arch=aarch64\nsigning_fingerprint=%s\npackage_count=3\n' 7 "$subkey_fingerprint"
    printf 'package=1|linux-aurora|%s|aarch64|linux-aurora.pkg.tar.zst|%064d|linux-aurora.pkg.tar.zst.sig|%064d\n' "$kernel" 1 2
    printf 'package=2|linux-aurora-headers|%s|aarch64|headers.pkg.tar.zst|%064d|headers.pkg.tar.zst.sig|%064d\n' "$kernel" 3 4
    printf 'package=3|m1n1-aurora|1.5.2-1|aarch64|m1n1.pkg.tar.zst|%064d|m1n1.pkg.tar.zst.sig|%064d\n' 5 6
    printf 'asset=omarchy-aurora.db|%s\n' "$(printf '%s' "$tag" | sha256sum | cut -d' ' -f1)"
    [[ -z $extra ]] || printf '%s\n' "$extra"
  } >"$assets/$tag/AURORA"
  printf 'signature\n' >"$assets/$tag/AURORA.sig"
}

digest() {
  sha256sum "$assets/$1/AURORA" | cut -d' ' -f1
}

# Release listing pages: each argument is one page of tag[:draft|:prerelease] words.
write_listing() {
  local page=0 entry tag kind
  rm -f "$assets"/api/page-*.json
  for words in "$@"; do
    (( page += 1 ))
    for entry in $words; do
      tag=${entry%%:*} kind=${entry#*:}
      [[ $entry == *:* ]] || kind=""
      jq -n --arg tag "$tag" --arg kind "$kind" \
        '{tag_name: $tag, draft: ($kind == "draft"), prerelease: ($kind == "prerelease")}'
    done | jq -s . >"$assets/api/page-$page.json"
  done
  printf '[]\n' >"$assets/api/page-$((page + 1)).json"
}

write_pointer() {
  printf 'format=1\nsequence=%s\ntag=aurora-edge-%s\n' "$1" "$1" >"$assets/pointer"
}

write_lane() {
  printf "$@" >"$lane_file"
  chmod 0644 "$lane_file"
}

expect_lane() {
  local description=$1
  shift
  printf "$@" >"$test_tmp/expected-lane"
  cmp -s "$test_tmp/expected-lane" "$lane_file" || fail "$description" "$(diff "$test_tmp/expected-lane" "$lane_file" || true)"
}

installed_from() {
  awk -F'|' '/^package=/ { print $2, $3 }' "$assets/$1/AURORA" >"$versions"
}

conf_on() {
  {
    printf '[options]\nArchitecture = aarch64\n\n'
    [[ -z $1 ]] || printf '# Aurora kernel and bootloader, kept on the qualified release by omarchy update\n[omarchy-aurora]\nSigLevel = Required DatabaseOptional\nServer = %s\n\n' "$1"
    printf '[omarchy]\nSigLevel = Required DatabaseOptional\nServer = https://example.test/omarchy\n\n[core]\nServer = https://example.test/$arch/$repo\n'
  } >"$pacman_conf"
}

section_tag() {
  sed -n "s|^Server = $downloads/||p" "$pacman_conf"
}

run_step() {
  : >"$curl_log"
  : >"$calls"
  : >"$channel_calls"
  rm -f "$targets"
  : >"$targets"
  printf 'cached database' >"$sync_dir/omarchy-aurora.db"
  set +e
  TEST_ASSETS="$assets" \
    TEST_CURL_LOG="$curl_log" \
    TEST_CALLS="$calls" \
    TEST_CHANNEL_CALLS="$channel_calls" \
    TEST_VERSIONS="$versions" \
    TEST_INSTALLED="linux-aurora linux-aurora-headers m1n1-aurora" \
    OMARCHY_APPLE_SILICON_CHANNEL_ROOT="$root" \
    OMARCHY_APPLE_SILICON_CHANNEL_TESTING=1 \
    OMARCHY_APPLE_SILICON_CHANNEL_LOCK_TIMEOUT=10 \
    OMARCHY_AURORA_ROOT="$root" \
    OMARCHY_AURORA_TARGETS="$targets" \
    OMARCHY_REBOOT_BLOCKED="$reboot_blocked" \
    OMARCHY_PATH="$omarchy_path" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$updater" "$@" >"$test_tmp/out" 2>"$test_tmp/err"
  status=$?
  set -e
}

expect_status() {
  (( status == $1 )) || fail "$2 exits $1" "status $status: $(cat "$test_tmp/out" "$test_tmp/err")"
}

expect_targets() {
  [[ $(cat "$targets") == $'omarchy-aurora/linux-aurora\nomarchy-aurora/linux-aurora-headers\nomarchy-aurora/m1n1-aurora' ]] ||
    fail "$1 names the three packages for the upgrade" "$(cat "$targets")"
}

expect_no_targets() {
  [[ ! -s $targets ]] || fail "$1 names no targets" "$(cat "$targets")"
}

write_release "$old_tag"
write_release "$pin_tag"
for sequence in 3 4 5 6 7; do
  write_release "aurora-edge-$sequence"
done
printf '# pinned for the test\ntag=%s\ndescriptor_sha256=%s\npredecessors=%s\n' "$pin_tag" "$(digest "$pin_tag")" "$old_tag" \
  >"$omarchy_path/default/aurora-qualified-release"
printf 'format=1\nchannel=rc\nkernel=linux-aurora\n' >"$record"
installed_from "$pin_tag"

# An rc Mac with no lane file: the pin, staged, and nothing for the upgrade to name.
conf_on "$downloads/$pin_tag"
run_step
expect_status 0 "an rc Mac on the pin"
cmp -s "$assets/$pin_tag/AURORA" "$staged" || fail "an rc Mac on the pin stages the pin's descriptor"
expect_no_targets "an rc Mac without a switch"
[[ ! -e $lane_file ]] || fail "an rc Mac gets no lane file"
run_step --complete
expect_status 0 "completing on an rc Mac with nothing open"
! grep -q boot-check "$calls" || fail "nothing open, nothing to check"
pass "an rc Mac without a lane keeps its pin, stages its descriptor and has nothing to complete"

# rc -> edge, first contact: the listing's highest full release, whatever the pointer says.
write_lane 'format=1\nlane=edge\nswitch=edge\n'
write_pointer 4
write_listing "aurora-edge-7:prerelease aurora-edge-6:draft aurora-edge-5 $pin_tag" "aurora-edge-3 aurora-edge-4"
run_step
expect_status 0 "a first edge update"
[[ $(section_tag) == aurora-edge-5 ]] || fail "first contact follows the listing's highest full release" "$(section_tag)"
expect_lane "the release is journaled as pending" 'format=1\nlane=edge\nswitch=edge\nedge_pending=5:%s\n' "$(digest aurora-edge-5)"
cmp -s "$assets/aurora-edge-5/AURORA" "$staged" || fail "the edge release's descriptor is staged"
expect_targets "a switch to edge"
for page in 1 2 3; do
  grep -Fxq "$api_url&page=$page" "$curl_log" || fail "the listing is read to its empty page" "$(cat "$curl_log")"
done
[[ ! -e $sync_dir/omarchy-aurora.db ]] || fail "the previous release's cached database is dropped"
cmp -s "$record" <(printf 'format=1\nchannel=rc\nkernel=linux-aurora\n') || fail "the format-1 record is never written"
pass "first contact follows the highest full edge release in the listing, skipping drafts, prereleases and a stale pointer"

run_step --complete
expect_status 1 "completing before the upgrade installed the release"
grep -Fq "linux-aurora 6.17.0.aurora1-1 is installed, but aurora-edge-5 has 6.18.0.aurora1.5-1" "$test_tmp/err" ||
  fail "an uninstalled release is named" "$(cat "$test_tmp/err")"
grep -Fq "aurora-edge-5 is not verified" "$reboot_blocked" || fail "an unverified move blocks the reboot"
expect_lane "an unverified move keeps the journal" 'format=1\nlane=edge\nswitch=edge\nedge_pending=5:%s\n' "$(digest aurora-edge-5)"
installed_from aurora-edge-5
TEST_BOOT_STATUS=1 run_step --complete
expect_status 1 "a boot chain the hooks left stale"
grep -Fq "the boot files do not match the installed kernel" "$test_tmp/err" || fail "a stale boot chain is named" "$(cat "$test_tmp/err")"
expect_lane "a failed boot check keeps the journal" 'format=1\nlane=edge\nswitch=edge\nedge_pending=5:%s\n' "$(digest aurora-edge-5)"
run_step --complete
expect_status 0 "completing an installed, bootable edge release"
grep -qx 'boot-check linux-aurora' "$calls" || fail "completion checks linux-aurora's boot chain" "$(cat "$calls")"
expect_lane "completion accepts the release and closes the switch" 'format=1\nlane=edge\nedge_accepted=5:%s\n' "$(digest aurora-edge-5)"
[[ ! -e $reboot_blocked ]] || fail "a verified move lifts the reboot block"
grep -Fq "now runs aurora-edge-5 from edge" "$test_tmp/out" || fail "completion says what the Mac runs" "$(cat "$test_tmp/out")"
pass "completion needs the staged release installed and a matching boot chain; until then the journal stays and the reboot is blocked"

# A section someone already pointed at the release first contact picks is not
# proof: the release is journaled all the same, and completes only once proven.
conf_on "$downloads/aurora-edge-5"
installed_from "$pin_tag"
write_lane 'format=1\nlane=edge\nswitch=edge\n'
write_listing "aurora-edge-5"
rm -f "$assets/pointer"
run_step
expect_status 0 "first contact on a section that already names the release"
expect_lane "a release not yet accepted is journaled though the section does not move" 'format=1\nlane=edge\nswitch=edge\nedge_pending=5:%s\n' "$(digest aurora-edge-5)"
[[ ! -s $calls ]] || fail "the section is not rewritten" "$(cat "$calls")"
expect_targets "a release journaled in place"
run_step --complete
expect_status 1 "completing before the journaled release is installed"
expect_lane "the unproven release stays pending" 'format=1\nlane=edge\nswitch=edge\nedge_pending=5:%s\n' "$(digest aurora-edge-5)"
installed_from aurora-edge-5
run_step --complete
expect_status 0 "completing the release proven in place"
expect_lane "the release proven in place is accepted" 'format=1\nlane=edge\nedge_accepted=5:%s\n' "$(digest aurora-edge-5)"
rm -f "$reboot_blocked"
for lane in 'format=1\nlane=edge\nswitch=edge\n' 'format=1\nlane=rc\nswitch=edge\n' 'format=1\nlane=edge\nswitch=rc\n'; do
  write_lane "$lane"
  run_step --complete
  expect_status 1 "completing a switch that names no release ($lane)"
  grep -Fq "no release was journaled" "$test_tmp/err" || fail "an unresolved switch says so" "$(cat "$test_tmp/err")"
  [[ -s $reboot_blocked ]] || fail "an unresolved switch blocks the reboot"
  ! grep -q boot-check "$calls" || fail "an unresolved switch is never checked into success"
  rm -f "$reboot_blocked"
done
pass "first contact journals a release the section already names, and a switch that names no release never completes"

# Interruptions between each step resume the journaled release, even once a newer one is out.
conf_on "$downloads/$pin_tag"
cp "$assets/$pin_tag/AURORA" "$staged"
installed_from "$pin_tag"
write_lane 'format=1\nlane=edge\nswitch=edge\n'
write_listing "aurora-edge-5"
rm -f "$assets/pointer"
TEST_FAIL_STAGE=1 run_step
expect_status 2 "an update stopped between the journal and the staging"
expect_lane "the journal lands before anything else" 'format=1\nlane=edge\nswitch=edge\nedge_pending=5:%s\n' "$(digest aurora-edge-5)"
[[ $(section_tag) == "$pin_tag" ]] || fail "nothing moves before the descriptor is staged"
write_pointer 6
write_listing "aurora-edge-6 aurora-edge-5"
run_step
expect_status 0 "the rerun"
[[ $(section_tag) == aurora-edge-5 ]] || fail "the rerun finishes the journaled release, not the newer one" "$(section_tag)"
! grep -Fq "$pointer_url" "$curl_log" && ! grep -Fq "$api_url" "$curl_log" || fail "a pending release is not rediscovered" "$(cat "$curl_log")"
expect_targets "the resumed switch"
run_step
expect_status 0 "a rerun after the section moved"
[[ ! -s $calls ]] && ! grep -q 'aurora-lane' "$channel_calls" || fail "a rerun after the move writes nothing" "$(cat "$calls" "$channel_calls")"
expect_targets "a rerun of the open switch"
installed_from aurora-edge-5
run_step --complete
expect_status 0 "the completion that was interrupted"
conf_on "$downloads/aurora-edge-5"
{ TEST_INTERRUPT_INSTALL=1 run_step; } 2>/dev/null
(( status != 0 )) || fail "an update killed at the pacman.conf install does not report success"
expect_lane "the journal survives the kill" 'format=1\nlane=edge\nedge_accepted=5:%s\nedge_pending=6:%s\n' "$(digest aurora-edge-5)" "$(digest aurora-edge-6)"
cmp -s "$assets/aurora-edge-6/AURORA" "$staged" && [[ $(section_tag) == aurora-edge-5 ]] ||
  fail "the kill leaves the new descriptor staged and the old section"
write_pointer 7
run_step
[[ $(section_tag) == aurora-edge-6 ]] || fail "the rerun after the kill moves to the journaled release" "$(section_tag)"
installed_from aurora-edge-6
run_step --complete
expect_lane "edge follows on to the next release" 'format=1\nlane=edge\nedge_accepted=6:%s\n' "$(digest aurora-edge-6)"
pass "an update interrupted before staging, at the repin, after it or before completion resumes the journaled release"

# Following edge: the pointer is enough while it is not behind; the listing decides when it is.
write_pointer 7
run_step
expect_status 0 "following the pointer"
[[ $(section_tag) == aurora-edge-7 ]] || fail "an edge Mac follows a newer pointer" "$(section_tag)"
! grep -Fq "$api_url" "$curl_log" || fail "a usable pointer needs no listing" "$(cat "$curl_log")"
expect_targets "an edge move"
installed_from aurora-edge-7
run_step --complete
run_step
expect_status 0 "a pointer at the accepted release"
[[ $(section_tag) == aurora-edge-7 ]] && [[ ! -s $calls ]] || fail "nothing moves while the pointer names the accepted release"
expect_no_targets "an edge Mac on the newest release"
grep -Fxq "$downloads/aurora-edge-7/AURORA" "$curl_log" || fail "the accepted release's descriptor is fetched again to compare" "$(cat "$curl_log")"
write_pointer 5
write_listing "aurora-edge-7 aurora-edge-6"
run_step
expect_status 0 "a stale pointer"
grep -Fq "$api_url&page=1" "$curl_log" || fail "a pointer behind the accepted release sends the Mac to the listing" "$(cat "$curl_log")"
[[ $(section_tag) == aurora-edge-7 ]] || fail "a stale pointer never moves a Mac back" "$(section_tag)"
write_listing "aurora-edge-5"
run_step
[[ $(section_tag) == aurora-edge-7 ]] || fail "a listing missing the accepted release never moves a Mac back" "$(section_tag)"
write_release aurora-edge-8
write_listing "aurora-edge-8 aurora-edge-7"
run_step
[[ $(section_tag) == aurora-edge-8 ]] || fail "the listing moves a Mac past a stale pointer" "$(section_tag)"
installed_from aurora-edge-8
run_step --complete
pass "a newer pointer is followed alone, a stale one sends the Mac to the listing, and neither moves it back"

# A release that changes after this Mac verified it is refused.
cp "$assets/aurora-edge-8/AURORA" "$test_tmp/edge-8"
write_release aurora-edge-8 'note=signed again'
write_pointer 8
cp "$lane_file" "$test_tmp/lane-before"
run_step
expect_status 2 "an equivocating release"
grep -Fq "AURORA in aurora-edge-8 is not the one this Mac already verified" "$test_tmp/err" || fail "equivocation is named" "$(cat "$test_tmp/err")"
cmp -s "$test_tmp/lane-before" "$lane_file" && [[ $(section_tag) == aurora-edge-8 && ! -s $calls ]] ||
  fail "an equivocating release changes nothing"
cp "$test_tmp/edge-8" "$assets/aurora-edge-8/AURORA"
write_release aurora-edge-9
write_lane 'format=1\nlane=edge\nedge_accepted=8:%s\nedge_pending=9:%064d\n' "$(digest aurora-edge-8)" 0
run_step
expect_status 2 "a journaled release that changed"
[[ $(section_tag) == aurora-edge-8 ]] || fail "a journaled release that changed is not installed"
pass "a release whose descriptor changed after it was accepted or journaled is refused"

# Descriptors must describe exactly the release they are fetched from.
write_lane 'format=1\nlane=edge\nedge_accepted=8:%s\n' "$(digest aurora-edge-8)"
write_pointer 9
for broken in 'sequence=8' 'channel=aurora' 'release_tag=aurora-edge-8'; do
  write_release aurora-edge-9 "$broken"
  run_step
  expect_status 2 "a descriptor with a second $broken"
  grep -Fq "AURORA in aurora-edge-9 does not describe that Aurora release" "$test_tmp/err" || fail "$broken is named" "$(cat "$test_tmp/err")"
done
write_release aurora-edge-9
sed -i 's/^sequence=9$/sequence=8/' "$assets/aurora-edge-9/AURORA"
run_step
expect_status 2 "a descriptor whose sequence is not its tag's"
write_release aurora-edge-9
sed -i '/^package=3|/d' "$assets/aurora-edge-9/AURORA"
run_step
expect_status 2 "a descriptor without m1n1-aurora"
write_release aurora-edge-9
TEST_GPG_FAIL=1 run_step
expect_status 2 "a descriptor with a bad signature"
[[ $(section_tag) == aurora-edge-8 && ! -s $calls ]] || fail "a descriptor that fails its checks changes nothing"
pass "channel, tag, sequence, package lines and the signature are all cross-checked"

# Edge that cannot be followed this time: exit 3, and the section stays where it can be proven.
defer_expected() {
  local description=$1 section=$2
  expect_status 3 "$description"
  [[ $(section_tag) == "$section" ]] || fail "$description leaves the section" "$(section_tag)"
  cmp -s "$assets/$section/AURORA" "$staged" || fail "$description stages the release it stays on"
  expect_no_targets "$description"
  grep -Fq "Aurora edge: " "$test_tmp/err" || fail "$description says why" "$(cat "$test_tmp/err")"
}
rm -f "$assets/pointer"
pages=()
for page in $(seq 10); do
  pages+=("aurora-edge-$page")
done
write_listing "${pages[@]}"
run_step
defer_expected "a listing that does not end within 10 pages" aurora-edge-8
grep -Fq "$api_url&page=10" "$curl_log" && ! grep -Fq "$api_url&page=11" "$curl_log" || fail "the listing stops at 10 pages" "$(cat "$curl_log")"
write_listing "aurora-edge-9" "aurora-edge-3"
rm "$assets/api/page-2.json"
run_step
defer_expected "a listing page that does not answer" aurora-edge-8
printf '{"message": "API rate limit exceeded"}\n' >"$assets/api/page-1.json"
run_step
defer_expected "a listing that is not a list" aurora-edge-8
printf 'format=1\nsequence=9\ntag=aurora-edge-9\nextra\n' >"$assets/pointer"
run_step
defer_expected "a malformed pointer with the listing down" aurora-edge-8
grep -Fq "edge pointer is malformed" "$test_tmp/err" || fail "a malformed pointer is named" "$(cat "$test_tmp/err")"
write_pointer 9
rm -rf "$assets/aurora-edge-9"
run_step
defer_expected "a release whose descriptor cannot be downloaded" aurora-edge-8
pass "a capped, failing or malformed listing, a malformed pointer or a missing descriptor defer on the accepted release"

conf_on "$downloads/$pin_tag"
installed_from "$pin_tag"
write_lane 'format=1\nlane=edge\nswitch=edge\n'
rm -f "$assets/pointer"
run_step
defer_expected "first contact with neither pointer nor listing" "$pin_tag"
expect_lane "a deferred switch stays open" 'format=1\nlane=edge\nswitch=edge\n'
write_listing ""
run_step
defer_expected "first contact with no edge release published" "$pin_tag"
grep -Fq "no edge release is published yet" "$test_tmp/err" || fail "an empty edge lane is named" "$(cat "$test_tmp/err")"
printf '[\n' >"$assets/api/page-1.json"
write_pointer 7
run_step
expect_status 0 "first contact with the listing down and a pointer"
[[ $(section_tag) == aurora-edge-7 ]] || fail "first contact follows the pointer when the listing is down" "$(section_tag)"
grep -Fq "follows the edge pointer to aurora-edge-7" "$test_tmp/err" || fail "following the pointer alone is logged" "$(cat "$test_tmp/err")"
pass "first contact defers on the rc pin without a listing or a pointer, and otherwise logs following the pointer alone"

# edge -> rc: only a switch moves an edge section back, completed the same way.
installed_from aurora-edge-7
run_step --complete
write_lane 'format=1\nlane=rc\nedge_accepted=7:%s\n' "$(digest aurora-edge-7)"
run_step
expect_status 0 "an rc lane left on edge without a switch"
grep -Fq "Leaving [omarchy-aurora] on aurora-edge-7" "$test_tmp/err" || fail "an edge section without a switch is left alone" "$(cat "$test_tmp/err")"
[[ ! -s $curl_log && $(section_tag) == aurora-edge-7 ]] || fail "an edge section without a switch is untouched"
expect_no_targets "an edge section without a switch"
write_lane 'format=1\nlane=rc\nswitch=rc\nedge_accepted=7:%s\nedge_pending=8:%s\n' "$(digest aurora-edge-7)" "$(digest aurora-edge-8)"
run_step
expect_status 0 "a switch back to rc"
[[ $(section_tag) == "$pin_tag" ]] || fail "a switch to rc moves the section back to the pin" "$(section_tag)"
cmp -s "$assets/$pin_tag/AURORA" "$staged" || fail "the pin's descriptor is staged for the way back"
expect_targets "the way back, which installs older packages"
run_step --complete
expect_status 1 "completing rc while the edge kernel is still installed"
installed_from "$pin_tag"
run_step --complete
expect_status 0 "completing the way back"
expect_lane "rc keeps what edge accepted and closes the rest" 'format=1\nlane=rc\nedge_accepted=7:%s\n' "$(digest aurora-edge-7)"
grep -Fq "back on rc ($pin_tag)" "$test_tmp/out" || fail "the way back says so" "$(cat "$test_tmp/out")"
pass "an edge section goes back to the pin only on a switch to rc, which completes like any other"

# Opposing switches: the last request wins, even with the first one half done.
write_lane 'format=1\nlane=edge\nswitch=edge\nedge_accepted=7:%s\n' "$(digest aurora-edge-7)"
write_pointer 8
run_step
[[ $(section_tag) == aurora-edge-8 ]] || fail "the switch to edge moved the section"
write_lane 'format=1\nlane=rc\nswitch=rc\nedge_accepted=7:%s\nedge_pending=8:%s\n' "$(digest aurora-edge-7)" "$(digest aurora-edge-8)"
run_step
[[ $(section_tag) == "$pin_tag" ]] || fail "the opposing switch to rc moves it back" "$(section_tag)"
run_step --complete
expect_lane "the opposing switch completes on rc" 'format=1\nlane=rc\nedge_accepted=7:%s\n' "$(digest aurora-edge-7)"
pass "an opposing switch replaces a half-done one and completes on its own target"

# Holds, hand pins and a lane file that cannot be read.
write_lane 'format=1\nlane=edge\nswitch=edge\n'
printf 'format=1\nchannel=rc\nkernel=linux-aurora\nhold=qualifying by hand\n' >"$record"
run_step
expect_status 0 "a held edge Mac"
[[ ! -s $curl_log && $(section_tag) == "$pin_tag" ]] || fail "a held edge Mac discovers and moves nothing"
expect_no_targets "a held edge Mac"
printf 'format=1\nchannel=rc\nkernel=linux-aurora\n' >"$record"
conf_on "$downloads/$candidate_tag"
run_step
expect_status 0 "an edge Mac on a hand-pinned candidate"
grep -Fq "this Mac follows edge, but omarchy update only moves it from" "$test_tmp/err" || fail "a hand pin is left alone and named" "$(cat "$test_tmp/err")"
[[ ! -s $curl_log && $(section_tag) == "$candidate_tag" ]] || fail "a hand-pinned candidate is untouched"
write_lane 'format=2\nlane=edge\n'
run_step
expect_status 2 "a lane file this runtime cannot read"
grep -Fq "omarchy-apple-silicon-channel reset-rc" "$test_tmp/err" && grep -Fq "$lane_file has unsupported format 2" "$test_tmp/err" ||
  fail "an unreadable lane file names the file and the repair" "$(cat "$test_tmp/err")"
pass "a hold or a hand pin stops an edge Mac without discovery, and an unreadable lane file stops the update with its repair"
