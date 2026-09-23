#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command sha256sum
require_command truncate

updater="$ROOT/bin/omarchy-update-aurora-repository"
system_packages="$ROOT/bin/omarchy-update-system-pkgs"
shipped_pin="$ROOT/default/aurora-qualified-release"
shipped_stable_pin="$ROOT/default/aurora-stable-release"
subkey_fingerprint=CAB18E175BFB9ACCE185234474DE0C737AC186E4
repo=maralcbr/omarchy-pkgs
release_ere='aurora-packages-[0-9a-f]{40}'
stable_ere='aurora-(packages|stable-packages)-[0-9a-f]{40}'

grep -Fq '# omarchy:hidden=true' "$updater" || fail "Aurora repository updater is hidden from command listings"
grep -Fq '# omarchy:requires-sudo=true' "$updater" || fail "Aurora repository updater declares its sudo requirement"
grep -Fq "trusted_subkey=$subkey_fingerprint" "$updater" || fail "Aurora repository updater pins the signing subkey"
grep -Fq '$2 == "VALIDSIG" && $3 == key' "$updater" ||
  fail "Aurora repository updater requires the descriptor signature from the subkey itself"
! grep -Fq '/usr/share/omarchy/default' "$updater" || fail "Aurora repository updater reads the runtime through OMARCHY_PATH"
grep -Exq "tag=$release_ere" "$shipped_pin" || fail "the runtime pins an aurora-packages release"
grep -Exq 'descriptor_sha256=[0-9a-f]{64}' "$shipped_pin" || fail "the runtime pins that release's descriptor digest"
grep -Exq "predecessors=($release_ere( $release_ere)*)?" "$shipped_pin" || fail "the runtime lists the releases the pin replaces"
(( $(grep -c '^tag=' "$shipped_pin") == 1 && $(grep -c '^descriptor_sha256=' "$shipped_pin") == 1 )) ||
  fail "the runtime pins exactly one Aurora release"
pass "the qualified Aurora release is pinned in the runtime"

grep -Exq "tag=$stable_ere" "$shipped_stable_pin" || fail "the runtime pins a stable aurora-packages or aurora-stable-packages release"
grep -Exq 'descriptor_sha256=[0-9a-f]{64}' "$shipped_stable_pin" || fail "the runtime pins that stable release's descriptor digest"
grep -Exq "predecessors=($stable_ere( $stable_ere)*)?" "$shipped_stable_pin" || fail "the runtime lists the releases the stable pin replaces"
(( $(grep -c '^tag=' "$shipped_stable_pin") == 1 && $(grep -c '^descriptor_sha256=' "$shipped_stable_pin") == 1 )) ||
  fail "the runtime pins exactly one stable Aurora release"
grep -Fq "Stable follows rc's hardware-qualified kernel" "$shipped_stable_pin" ||
  fail "the stable pin is commented as following rc's qualified kernel"
pass "the stable Aurora release is pinned in the runtime"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# omarchy-update-system-pkgs: the repin comes before every upgrade, and its
# failure is the end of the update.
pkgs_bin="$test_tmp/pkgs-bin"
mkdir -p "$pkgs_bin"
cat >"$pkgs_bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH
cat >"$pkgs_bin/pacman" <<'SH'
#!/bin/bash
printf 'pacman %s\n' "$*" >>"$TEST_ORDER"
SH
cat >"$pkgs_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$pkgs_bin/omarchy-update-aurora-repository" <<'SH'
#!/bin/bash
echo aurora >>"$TEST_ORDER"
exit "${TEST_AURORA_STATUS:-0}"
SH
chmod +x "$pkgs_bin"/*

run_system_packages() {
  : >"$test_tmp/order"
  set +e
  TEST_ORDER="$test_tmp/order" PATH="$pkgs_bin:$ROOT/bin:$PATH" \
    bash "$system_packages" </dev/null >"$test_tmp/pkgs.out" 2>"$test_tmp/pkgs.err"
  status=$?
  set -e
}

run_system_packages
(( status == 0 )) || fail "system packages update with a current Aurora repository" "$(cat "$test_tmp/pkgs.err")"
[[ $(head -1 "$test_tmp/order") == aurora && $(sed -n 2p "$test_tmp/order") == "pacman -Syu"* ]] ||
  fail "the Aurora repository is pinned before the system upgrade" "$(cat "$test_tmp/order")"
OMARCHY_UPDATE_CONFLICT=1 OMARCHY_UPDATE_INTERACTIVE=1 run_system_packages
[[ $(head -1 "$test_tmp/order") == aurora && $(sed -n 2p "$test_tmp/order") == "pacman -Syu"* ]] ||
  fail "the Aurora repository is pinned before the interactive conflict retry" "$(cat "$test_tmp/order")"
for aurora_status in 1 2; do
  TEST_AURORA_STATUS=$aurora_status run_system_packages
  (( status == 1 )) || fail "a failed Aurora repin fails the system update without its own status" "status $status"
  ! grep -q '^pacman' "$test_tmp/order" || fail "a failed Aurora repin stops before pacman" "$(cat "$test_tmp/order")"
done
TEST_AURORA_STATUS=3 run_system_packages
(( status == 0 )) || fail "edge that cannot be followed this time leaves the upgrade running" "status $status: $(cat "$test_tmp/pkgs.err")"
[[ $(sed -n 2p "$test_tmp/order") == "pacman -Syu"* ]] || fail "a deferred edge move still upgrades on the current pin" "$(cat "$test_tmp/order")"
pass "omarchy-update-system-pkgs pins the Aurora repository before pacman, stops when it cannot, and upgrades on the current pin when edge is deferred"

stub_bin="$test_tmp/bin"
assets="$test_tmp/assets"
root="$test_tmp/root"
omarchy_path="$test_tmp/omarchy"
pin_file="$omarchy_path/default/aurora-qualified-release"
key_file="$omarchy_path/default/omarchy-arm-repository.asc"
pacman_conf="$root/etc/pacman.conf"
marker="$root/usr/share/omarchy/apple-silicon-kernel"
channel_record="$root/var/lib/omarchy/apple-silicon-channel"
channel_dir="$root/var/lib/omarchy"
channel_calls="$test_tmp/channel-calls"
staged_descriptor="$root/var/lib/omarchy/aurora-target.descriptor"
sync_dir="$root/var/lib/pacman/sync"
calls="$test_tmp/calls"
curl_log="$test_tmp/curl.log"
lock_log="$test_tmp/lock.log"
oldest_tag=aurora-packages-f0af33325a071092cf7883cc0a79ae755b15b0c7
old_tag=aurora-packages-412375933f5c94b304708576c9999c4cf5f88700
new_tag=aurora-packages-1c5e34c99dc2510bf06c673165a79aa92c8f1f4c
candidate_tag=aurora-packages-4439238d23d28c8d3766a6dd040a9e5f9fd587e0
old_server="https://github.com/$repo/releases/download/$old_tag"
new_server="https://github.com/$repo/releases/download/$new_tag"
candidate_server="https://github.com/$repo/releases/download/$candidate_tag"
asahi_server="https://github.com/$repo/releases/download/asahi-packages-stable-83973903b7deb9b56ce75f02b432fba0561d6293"
comment='# Aurora kernel and bootloader, kept on the qualified release by omarchy update'
mkdir -p "$stub_bin" "$assets" "$root/etc/pacman.d" "$(dirname "$marker")" "$sync_dir" "$omarchy_path/default" "$channel_dir"
chmod 0755 "$channel_dir"
printf 'Server = http://mirror.archlinuxarm.org/$arch/$repo\n' >"$root/etc/pacman.d/mirrorlist"

write_release() {
  local tag=$1
  mkdir -p "$assets/$tag"
  cat >"$assets/$tag/AURORA" <<EOF
format=1
channel=aurora
release_tag=$tag
source_commit=${tag#aurora-packages-}
workflow_run=34750870698
runner_arch=aarch64
signing_fingerprint=$subkey_fingerprint
package_count=3
package=1|linux-aurora|6.17.0.aurora1-1|aarch64|linux-aurora-6.17.0.aurora1-1-aarch64.pkg.tar.zst|$(printf '%064d' 1)|linux-aurora-6.17.0.aurora1-1-aarch64.pkg.tar.zst.sig|$(printf '%064d' 2)
package=2|linux-aurora-headers|6.17.0.aurora1-1|aarch64|linux-aurora-headers-6.17.0.aurora1-1-aarch64.pkg.tar.zst|$(printf '%064d' 3)|linux-aurora-headers-6.17.0.aurora1-1-aarch64.pkg.tar.zst.sig|$(printf '%064d' 4)
package=3|m1n1-aurora|1.5.2-1|aarch64|m1n1-aurora-1.5.2-1-aarch64.pkg.tar.zst|$(printf '%064d' 5)|m1n1-aurora-1.5.2-1-aarch64.pkg.tar.zst.sig|$(printf '%064d' 6)
asset=omarchy-aurora.db|$(printf '%s' "$tag" | sha256sum | cut -d' ' -f1)
asset=omarchy-aurora.db.sig|$(printf '%064d' 7)
EOF
  printf 'signature\n' >"$assets/$tag/AURORA.sig"
}

write_pin() {
  printf '# pinned for the test\ntag=%s\ndescriptor_sha256=%s\npredecessors=%s\n' \
    "$1" "$2" "${3-$oldest_tag $old_tag}" >"$pin_file"
}

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
[[ ${TEST_APPLE_SILICON:-1} == 1 ]]
SH
cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$stub_bin/omarchy-update-lock" <<'SH'
#!/bin/bash
printf '%s\n' "$1" >>"$TEST_LOCK_LOG"
# Side effects belong to the first question, before the updater re-enters under the channel lock.
if [[ $1 == "held" && ${OMARCHY_APPLE_SILICON_CHANNEL_LOCKED:-} != 1 ]]; then
  if [[ -n ${TEST_HOLD_BEFORE_LOCK:-} ]]; then
    printf 'hold=%s\n' "$TEST_HOLD_BEFORE_LOCK" >>"$TEST_CHANNEL_RECORD"
  fi
  if [[ ${TEST_TAKE_CHANNEL_LOCK:-0} == 1 ]]; then
    (
      exec 9<"$TEST_CHANNEL_LOCK"
      flock -x 9
      : >"$TEST_CHANNEL_LOCK_READY"
      exec sleep 30
    ) >/dev/null 2>&1 &
    echo $! >"$TEST_CHANNEL_LOCK_HOLDER"
    until [[ -e $TEST_CHANNEL_LOCK_READY ]]; do sleep 0.05; done
  fi
fi
if [[ $1 == "held" ]]; then
  [[ ${TEST_LOCK_HELD:-1} == 1 ]]
  exit
fi
shift
# The command is the updater script; run it with the bash the test runs under.
TEST_LOCK_HELD=1 exec bash "$@"
SH
cat >"$stub_bin/curl" <<'SH'
#!/bin/bash
output=""
url=""
while (($#)); do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
printf '%s\n' "$url" >>"$TEST_CURL_LOG"
if [[ -n ${TEST_CURL_GATE:-} ]]; then
  : >"$TEST_CURL_GATE.waiting"
  until [[ -e $TEST_CURL_GATE.go ]]; do sleep 0.05; done
fi
[[ ${TEST_CURL_OFFLINE:-0} != 1 ]] || exit 7
path=${url#https://github.com/maralcbr/omarchy-pkgs/releases/download/}
[[ -f $TEST_ASSETS/$path ]] || exit 22
cp "$TEST_ASSETS/$path" "$output"
SH
cat >"$stub_bin/gpg" <<'SH'
#!/bin/bash
primary=C81AC3E2A99556F9B21D5FEA3DD49BC9F8360BDC
subkey=CAB18E175BFB9ACCE185234474DE0C737AC186E4
if [[ " $* " == *" --show-keys "* ]]; then
  # gpg reads nothing from a file that is not a key and exits 2.
  [[ $(cat "${@: -1}") != "malformed" ]] || exit 2
  printf 'pub:-:255:22:%s:::::::cSC::::::::0:\nfpr:::::::::%s:\n' "${primary:24}" "$primary"
  exit 0
fi
if [[ " $* " == *" --import "* ]]; then
  exit 0
fi
if [[ " $* " == *" --list-keys "* ]]; then
  [[ ${TEST_GPG_LIST_FAIL:-0} != 1 ]] || exit 2
  printf 'pub:-:255:22:%s:::::::cSC::::::::0:\nfpr:::::::::%s:\nsub:-:255:22:%s:::::::s::::::::0:\nfpr:::::::::%s:\n' \
    "${primary:24}" "$primary" "${subkey:24}" "$subkey"
  exit 0
fi
[[ ${TEST_GPG_FAIL:-0} != 1 ]] || exit 1
signer=$subkey
[[ ${TEST_GPG_SIGNER:-subkey} == "subkey" ]] || signer=$primary
echo "[GNUPG:] VALIDSIG $signer 2026-01-01 0 4 0 1 22 00 $primary"
SH
# The channel helper's own writes (the record, the lane, the staged descriptor)
# are logged apart, so "nothing privileged runs" keeps meaning pacman.conf, its
# backup and its cache.
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
if [[ $* == *apple-silicon-channel* || $* == *apple-silicon-aurora-lane* || $* == *aurora-target.descriptor* ]]; then
  printf 'sudo:%s\n' "$*" >>"$TEST_CHANNEL_CALLS"
  exec "$@"
fi
printf 'sudo:%s\n' "$*" >>"$TEST_CALLS"
if [[ $1 == "rm" && ${TEST_RM_FAIL:-0} == 1 ]]; then
  echo "rm: cannot remove: Read-only file system" >&2
  exit 1
fi
if [[ $1 == "install" && $* == *.omarchy-aurora && ${TEST_INTERRUPT_INSTALL:-0} == 1 ]]; then
  # Stop the updater itself, the way a power loss or kill would.
  kill -KILL "$PPID"
  exit 1
fi
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
cat >"$stub_bin/chown" <<'SH'
#!/bin/bash
exit 0
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
if [[ $1 == "-Qi" || $1 == "-Si" ]]; then
  groups=()
  for entry in ${TEST_GROUPS:-}; do
    [[ ${entry%%:*} != "$2" ]] || groups+=("${entry#*:}")
  done
  printf 'Name            : %s\nGroups          : %s\n' "$2" "${groups[*]:-None}"
  exit 0
fi
if [[ $* == "-Qq" ]]; then
  printf '%s\n' $TEST_INSTALLED
  exit 0
fi
if [[ $1 == "-Q" ]]; then
  [[ " $TEST_INSTALLED " == *" $2 "* ]]
  exit
fi
printf 'pacman:%s\n' "$*" >>"$TEST_CALLS"
SH
chmod +x "$stub_bin"/*

run_status() {
  set +e
  TEST_ASSETS="$assets" \
    TEST_CURL_LOG="$curl_log" \
    TEST_CALLS="$calls" \
    TEST_LOCK_LOG="$lock_log" \
    TEST_CHANNEL_CALLS="$channel_calls" \
    TEST_CHANNEL_RECORD="$channel_record" \
    TEST_CHANNEL_LOCK="$channel_dir" \
    TEST_CHANNEL_LOCK_READY="$test_tmp/channel-lock-ready" \
    TEST_CHANNEL_LOCK_HOLDER="$test_tmp/channel-lock-holder" \
    OMARCHY_APPLE_SILICON_CHANNEL_ROOT="$root" \
    OMARCHY_APPLE_SILICON_CHANNEL_TESTING=1 \
    OMARCHY_APPLE_SILICON_CHANNEL_LOCK_TIMEOUT="${TEST_CHANNEL_LOCK_TIMEOUT:-10}" \
    TEST_KEY_STATE="$test_tmp/key-trusted" \
    TEST_INSTALLED="${TEST_INSTALLED-linux-aurora linux-aurora-headers m1n1-aurora}" \
    TEST_GROUPS="${TEST_GROUPS:-}" \
    OMARCHY_AURORA_ROOT="$root" \
    OMARCHY_PATH="${TEST_OMARCHY_PATH:-$omarchy_path}" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "${TEST_SCRIPT:-$updater}" "$@" >"$test_tmp/out" 2>"$test_tmp/err"
  status=$?
  set -e
}

reset_run() {
  : >"$curl_log"
  : >"$calls"
  : >"$lock_log"
  : >"$channel_calls"
  rm -f "$test_tmp/key-trusted"
  rm -rf "$root/var/lib/omarchy/backups"
  printf 'fixture key\n' >"$key_file"
  printf 'stale database' >"$sync_dir/omarchy-aurora.db"
  printf 'stale signature' >"$sync_dir/omarchy-aurora.db.sig"
  cp "$pacman_conf" "$test_tmp/before"
}

options_conf() {
  cat <<CONF
[options]
HoldPkg = pacman glibc
Architecture = aarch64
SigLevel = Required DatabaseOptional
${1:-#IgnorePkg   =}
  # spacing and comments here are not ours to tidy

CONF
}

omarchy_conf() {
  printf '[omarchy]\nSigLevel = Required DatabaseOptional\nServer = %s\n\n' "$asahi_server"
}

aurora_conf() {
  printf '%s\n[omarchy-aurora]\nSigLevel = Required DatabaseOptional\nServer = %s\n\n' "$comment" "$1"
}

remaining_conf() {
  cat <<'CONF'
[asahi-alarm]
SigLevel = Required DatabaseOptional
Server = https://github.com/asahi-alarm/asahi-alarm/releases/download/aarch64

[core]
Server = https://ca.us.mirror.archlinuxarm.org/$arch/$repo
Server = https://fl.us.mirror.archlinuxarm.org/$arch/$repo
CONF
}

expect_conf() {
  cmp -s "$test_tmp/expected" "$pacman_conf" || fail "$1" "$(diff "$test_tmp/expected" "$pacman_conf" || true)"
}

expect_untouched() {
  cmp -s "$test_tmp/before" "$pacman_conf" || fail "$1: pacman.conf is byte-identical" "$(diff "$test_tmp/before" "$pacman_conf" || true)"
  [[ ! -s $calls ]] || fail "$1: nothing privileged runs" "$(cat "$calls")"
  [[ ! -e $root/var/lib/omarchy/backups ]] || fail "$1: no backup is taken"
  [[ -e $sync_dir/omarchy-aurora.db && -e $sync_dir/omarchy-aurora.db.sig ]] || fail "$1: the cached Aurora database is kept"
}

# A repin writes pacman.conf, drops the cached database, and leaves syncing to
# the package upgrade that follows.
expect_repinned() {
  (( status == 0 )) || fail "$1 succeeds" "status $status: $(cat "$test_tmp/err")"
  expect_conf "$1"
  [[ ! -e $sync_dir/omarchy-aurora.db && ! -e $sync_dir/omarchy-aurora.db.sig ]] || fail "$1: the previous release's cached database is dropped"
  ! grep -q '^pacman:' "$calls" || fail "$1: the updater runs no pacman itself" "$(cat "$calls")"
}

write_release "$old_tag"
write_release "$new_tag"
new_digest=$(sha256sum "$assets/$new_tag/AURORA" | cut -d' ' -f1)
write_pin "$new_tag" "$new_digest"

# Machines that do not follow rc, each without a channel record yet. Evidence
# too ambiguous to record says so once and still leaves the update running.
{ options_conf; omarchy_conf; remaining_conf; } >"$pacman_conf"
not_aurora() {
  local description=$1 notice=${2:-}
  reset_run
  rm -f "$channel_record"
  run_status
  (( status == 0 )) || fail "$description exits cleanly" "status $status: $(cat "$test_tmp/err")"
  [[ ! -s $test_tmp/out ]] || fail "$description prints nothing" "$(cat "$test_tmp/out")"
  if [[ -z $notice ]]; then
    [[ ! -s $test_tmp/err ]] || fail "$description is silent" "$(cat "$test_tmp/err")"
  else
    (( $(wc -l <"$test_tmp/err") == 1 )) && grep -Fq "$notice" "$test_tmp/err" ||
      fail "$description says in one line why no channel is recorded" "$(cat "$test_tmp/err")"
    [[ ! -e $channel_record ]] || fail "$description records no channel" "$(cat "$channel_record")"
  fi
  [[ ! -s $curl_log && ! -s $lock_log ]] || fail "$description downloads nothing and takes no lock"
  expect_untouched "$description"
}
rm -f "$marker"
TEST_INSTALLED="linux-asahi linux-asahi-headers m1n1" not_aurora "an Asahi install without the marker"
printf 'format=1\nchannel=stable\nkernel=linux-asahi\n' | cmp -s - "$channel_record" ||
  fail "an Asahi install is recorded as stable" "$(cat "$channel_record")"
printf 'linux-asahi\n' >"$marker"
not_aurora "an Asahi marker, even with linux-aurora installed" "names linux-asahi, but linux-aurora is installed"
printf 'linux-aurora\n' >"$marker"
TEST_INSTALLED="linux-asahi" not_aurora "an Aurora marker without linux-aurora installed" "names linux-aurora, but linux-asahi is installed"
printf 'linux-aurora\n' >"$test_tmp/linked-marker"
rm -f "$marker"
ln -s "$test_tmp/linked-marker" "$marker"
not_aurora "a symlinked kernel marker" "is not a readable regular file"
rm -f "$marker"
TEST_INSTALLED="linux-aurora linux-asahi" not_aurora "linux-aurora and linux-asahi both installed without a marker" \
  "both linux-aurora and linux-asahi are installed"
{ options_conf; remaining_conf; } >"$pacman_conf"
TEST_APPLE_SILICON=0 not_aurora "an x86 machine"
[[ ! -e $channel_record && ! -s $channel_calls ]] || fail "an x86 machine records no channel"
pass "only Aurora installs are touched: Asahi and x86 are silent no-ops, and ambiguous kernel evidence says why once"

# The pin that ships is one the updater accepts. Even a Mac already on it
# stages that release's descriptor, which is not among the test's assets, so it
# gets as far as asking for it and changes nothing.
shipped_tag=$(sed -n 's/^tag=//p' "$shipped_pin")
{ options_conf; aurora_conf "https://github.com/$repo/releases/download/$shipped_tag"; omarchy_conf; remaining_conf; } >"$pacman_conf"
reset_run
TEST_OMARCHY_PATH="$ROOT" run_status
(( status == 2 )) || fail "the shipped pin parses" "status $status: $(cat "$test_tmp/err")"
grep -Fxq "https://github.com/$repo/releases/download/$shipped_tag/AURORA" "$curl_log" ||
  fail "a Mac already on the shipped pin stages its descriptor" "$(cat "$curl_log" "$test_tmp/err")"
expect_untouched "a Mac already on the shipped pin"
[[ ! -e $staged_descriptor ]] || fail "nothing is staged without the descriptor"
printf 'format=1\nchannel=rc\nkernel=linux-aurora\n' | cmp -s - "$channel_record" ||
  fail "an Aurora install without a marker is recorded as rc" "$(cat "$channel_record")"
pass "the shipped pin is accepted, and a Mac already on it asks for its descriptor before anything else"

# A missing section is added right before [omarchy], with the legacy evidence.
{ options_conf; omarchy_conf; remaining_conf; } >"$pacman_conf"
{ options_conf; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } >"$test_tmp/expected"
reset_run
run_status
expect_repinned "[omarchy-aurora] is inserted just before [omarchy] and nothing else changes"
grep -Fxq "Pinned the Aurora kernel repository to $new_tag (backup: $(ls -d "$root"/var/lib/omarchy/backups/aurora-repository-*))" "$test_tmp/out" ||
  fail "the repin names the release and the backup" "$(cat "$test_tmp/out")"
! grep -Fq 'omarchy update will sync it' "$test_tmp/out" || fail "a repin inside omarchy update does not tell the user to run it"
grep -Fxq "$new_server/AURORA" "$curl_log" && grep -Fxq "$new_server/AURORA.sig" "$curl_log" ||
  fail "the pinned release's descriptor and signature are downloaded" "$(cat "$curl_log")"
cmp -s "$test_tmp/before" "$root"/var/lib/omarchy/backups/aurora-repository-*/pacman.conf || fail "the previous pacman.conf is backed up"
[[ $(stat -c '%a' "$pacman_conf") == 644 ]] || fail "pacman.conf stays 0644"
[[ ! -e $pacman_conf.omarchy-aurora ]] || fail "the staged pacman.conf is renamed into place"
grep -Eq "^sudo:mv -f $pacman_conf.omarchy-aurora $pacman_conf\$" "$calls" || fail "pacman.conf is replaced by rename" "$(cat "$calls")"
grep -Fxq "pacman-key:--add $key_file" "$calls" || fail "a missing repository key is imported into pacman"
pass "a missing [omarchy-aurora] is inserted before [omarchy] after the release is proven"

reset_run
run_status
(( status == 0 )) || fail "a current Aurora repository is a successful no-op" "status $status: $(cat "$test_tmp/err")"
[[ ! -s $test_tmp/out && ! -s $test_tmp/err && ! -s $curl_log ]] || fail "a current Aurora repository is silent and offline"
expect_untouched "a second run"
pass "a second run makes no write and keeps the cached database"

# A listed predecessor is repointed in place, marker evidence.
printf 'linux-aurora\n' >"$marker"
{
  options_conf
  printf '# The signed Aurora kernel.\n[omarchy-aurora]\nServer = %s\nSigLevel = Optional TrustAll\nServer = %s/\nUsage = Sync Search\n\n' "$old_server" "$old_server"
  omarchy_conf
  remaining_conf
} >"$pacman_conf"
{
  options_conf
  printf '# The signed Aurora kernel.\n[omarchy-aurora]\nSigLevel = Required DatabaseOptional\nServer = %s\nUsage = Sync Search\n\n' "$new_server"
  omarchy_conf
  remaining_conf
} >"$test_tmp/expected"
reset_run
run_status
expect_repinned "a predecessor pin gets exactly one Server on the qualified release and the required SigLevel"
pass "an [omarchy-aurora] on a listed predecessor is repointed at the qualified release"

# A section already on the pin is only tidied.
{ options_conf; printf '[omarchy-aurora]\nServer = %s\n\n' "$new_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
{ options_conf; printf '[omarchy-aurora]\nSigLevel = Required DatabaseOptional\nServer = %s\n\n' "$new_server"; omarchy_conf; remaining_conf; } >"$test_tmp/expected"
reset_run
run_status
expect_repinned "a section on the pin gets the required SigLevel"
pass "an [omarchy-aurora] already on the pin is fixed up"

# A predecessor behind [omarchy] moves in front of it, its comment with it.
{
  options_conf
  omarchy_conf
  printf '# The signed Aurora kernel.\n[omarchy-aurora]\nSigLevel = Required DatabaseOptional\nServer = %s\n\n' "$old_server"
  remaining_conf
} >"$pacman_conf"
{
  options_conf
  printf '# The signed Aurora kernel.\n[omarchy-aurora]\nSigLevel = Required DatabaseOptional\nServer = %s\n\n' "$new_server"
  omarchy_conf
  remaining_conf
} >"$test_tmp/expected"
reset_run
run_status
expect_repinned "the misplaced section moves to just before [omarchy]"
pass "an [omarchy-aurora] section after [omarchy] is moved in front of it"

# A file that ends without a newline keeps ending that way, and CRLF stays CRLF.
{ options_conf; omarchy_conf; remaining_conf; } | head -c -1 >"$pacman_conf"
{ options_conf; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } | head -c -1 >"$test_tmp/expected"
reset_run
run_status
expect_repinned "a missing final newline is preserved"
{ options_conf; omarchy_conf; remaining_conf; } | sed 's/$/\r/' >"$pacman_conf"
{ options_conf; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } | sed 's/$/\r/' >"$test_tmp/expected"
reset_run
run_status
expect_repinned "CRLF line endings are kept on inserted lines"
pass "unrelated bytes, a missing final newline, and CRLF line endings are preserved"

# Sections on a release the pin does not replace are somebody's choice.
left_alone() {
  local description=$1 current=$2
  reset_run
  run_status
  (( status == 0 )) || fail "$description does not stop the update" "status $status: $(cat "$test_tmp/err")"
  grep -Fq "Leaving [omarchy-aurora] on $current: it is neither the runtime's qualified release $new_tag" "$test_tmp/err" ||
    fail "$description names the current and runtime releases" "$(cat "$test_tmp/err")"
  [[ ! -s $test_tmp/out && ! -s $curl_log ]] || fail "$description downloads nothing"
  expect_untouched "$description"
}
{ options_conf; aurora_conf "$candidate_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
left_alone "a hand-pinned newer candidate" "$candidate_tag"
{ options_conf; omarchy_conf; aurora_conf "$candidate_server"; remaining_conf; } >"$pacman_conf"
left_alone "a hand-pinned candidate behind [omarchy]" "$candidate_tag"
{ options_conf; aurora_conf "https://example.test/aurora"; omarchy_conf; remaining_conf; } >"$pacman_conf"
left_alone "a server outside the aurora-packages releases" "https://example.test/aurora"
{ options_conf; printf '[omarchy-aurora]\nServer = %s\nServer = %s\n\n' "$old_server" "$candidate_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
left_alone "servers naming different releases" "$old_tag $candidate_tag"
{ options_conf; printf '[omarchy-aurora]\nInclude = /etc/pacman.d/mirrorlist\n\n'; omarchy_conf; remaining_conf; } >"$pacman_conf"
left_alone "an [omarchy-aurora] that includes a server list" "Include = /etc/pacman.d/mirrorlist"
{ options_conf; printf '[omarchy-aurora]\nSigLevel = Required DatabaseOptional\n\n'; omarchy_conf; remaining_conf; } >"$pacman_conf"
left_alone "an [omarchy-aurora] without a server" "no server"
pass "a newer candidate, an unknown server, mixed releases, Include and no server are left alone with a warning"

# A descriptor proven under the pin's digest is staged, and the pin's digest is
# proof enough to reuse it: the section moves without going back to the network.
{ options_conf; aurora_conf "$old_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
{ options_conf; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } >"$test_tmp/expected"
cmp -s "$assets/$new_tag/AURORA" "$staged_descriptor" || fail "the pinned release's descriptor is staged" "$(cat "$staged_descriptor" 2>&1)"
[[ $(stat -c '%a' "$staged_descriptor") == 644 ]] || fail "the staged descriptor is 0644"
reset_run
TEST_CURL_OFFLINE=1 run_status
expect_repinned "a repin with the pinned descriptor already staged"
[[ ! -s $curl_log ]] || fail "a descriptor staged under the pin's digest is not downloaded again" "$(cat "$curl_log")"
pass "the pinned release's descriptor is staged, and reused while it has the pin's digest"

# Nothing is written unless the pinned release is proven.
{ options_conf; aurora_conf "$old_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
rm -f "$staged_descriptor"
failed_closed() {
  local description=$1 expected_status=$2 message=$3
  (( status == expected_status )) || fail "$description fails closed" "status $status: $(cat "$test_tmp/err")"
  grep -Fq "$message" "$test_tmp/err" || fail "$description is explained" "$(cat "$test_tmp/err")"
  expect_untouched "$description"
  [[ ! -e $staged_descriptor ]] || fail "$description stages nothing"
}
reset_run
write_pin "$new_tag" "$(printf '%064d' 0)"
run_status
failed_closed "a digest mismatch" 2 "AURORA in $new_tag does not match the qualified digest"
write_pin "$new_tag" "$new_digest"

reset_run
TEST_GPG_FAIL=1 run_status
failed_closed "a bad descriptor signature" 2 'signature verification failed for AURORA'
reset_run
TEST_GPG_SIGNER=primary run_status
failed_closed "a primary-key signature" 2 'was not signed by the Omarchy ARM repository signing subkey'
reset_run
TEST_CURL_OFFLINE=1 run_status
failed_closed "a download failure" 2 "could not download $new_server/AURORA"

reset_run
printf 'malformed' >"$key_file"
run_status
failed_closed "a malformed repository key" 2 'could not read the trusted Omarchy ARM repository key'
reset_run
TEST_GPG_LIST_FAIL=1 run_status
failed_closed "a key gpg cannot list" 2 'could not list the trusted Omarchy ARM repository key'

# Another release's descriptor under this tag, with a pin that matches it.
reset_run
mv "$assets/$new_tag/AURORA" "$test_tmp/new-descriptor"
cp "$assets/$old_tag/AURORA" "$assets/$new_tag/AURORA"
write_pin "$new_tag" "$(sha256sum "$assets/$old_tag/AURORA" | cut -d' ' -f1)"
run_status
failed_closed "a descriptor for another release" 2 "does not describe that Aurora release"
mv "$test_tmp/new-descriptor" "$assets/$new_tag/AURORA"
write_pin "$new_tag" "$new_digest"
pass "a digest mismatch, bad signature, download failure, bad key or wrong descriptor leaves pacman.conf and its cache as they were"

# Configurations and pins this cannot safely act on are refused before any download.
refused() {
  local description=$1 message=$2
  reset_run
  run_status
  (( status == 2 )) || fail "$description is refused" "status $status"
  grep -Fq "$message" "$test_tmp/err" || fail "$description is explained" "$(cat "$test_tmp/err")"
  [[ ! -s $curl_log ]] || fail "$description is refused before downloading"
  expect_untouched "$description"
}
{ options_conf; aurora_conf "$old_server"; omarchy_conf; aurora_conf "$new_server"; remaining_conf; } >"$pacman_conf"
refused "a duplicate [omarchy-aurora]" 'more than one [omarchy-aurora] repository'
{ options_conf; aurora_conf "$old_server"; remaining_conf; } >"$pacman_conf"
refused "a configuration without [omarchy]" 'exactly one [omarchy] repository'
{ options_conf; omarchy_conf; remaining_conf; } >"$pacman_conf"
printf 'tag=%s\npredecessors=\n' "$new_tag" >"$pin_file"
refused "a pin without a digest" 'pin is malformed'
printf 'tag=%s\ndescriptor_sha256=%s\n' "$new_tag" "$new_digest" >"$pin_file"
refused "a pin without predecessors" 'pin is malformed'
write_pin "$new_tag" "$new_digest" "$old_tag $new_tag"
refused "a pin that replaces itself" 'pin is malformed'
write_pin "$new_tag" "$new_digest" "$old_tag aurora-packages-412375933f5c"
refused "a pin with an abbreviated predecessor" 'pin is malformed'
write_pin "$new_tag" "$new_digest"
pass "duplicate sections, a missing [omarchy] and malformed pins are refused without edits"

# A hold is kept, and named.
{ options_conf 'IgnorePkg = linux-aurora linux-aurora-headers'; omarchy_conf; remaining_conf; } >"$pacman_conf"
{ options_conf 'IgnorePkg = linux-aurora linux-aurora-headers'; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } >"$test_tmp/expected"
reset_run
run_status
expect_repinned "the IgnorePkg hold is preserved while the section is added"
grep -Fq 'holds linux-aurora linux-aurora-headers, so omarchy update cannot install a newer Aurora kernel until that hold is removed' "$test_tmp/err" ||
  fail "the hold is named with what it blocks" "$(cat "$test_tmp/err")"
{ options_conf 'IgnoreGroup = asahi-*'; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
reset_run
TEST_GROUPS="m1n1-aurora:asahi-boot" run_status
(( status == 0 )) || fail "a current repository with a glob hold is a no-op" "status $status"
grep -Fq 'holds m1n1-aurora,' "$test_tmp/err" || fail "a glob hold on a group m1n1-aurora is in is named" "$(cat "$test_tmp/err")"
expect_untouched "a current repository with a hold"
{ options_conf 'IgnoreGroup = m1n1-*'; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
reset_run
TEST_GROUPS="m1n1-aurora:asahi-boot" run_status
! grep -Fq 'holds' "$test_tmp/err" || fail "an IgnoreGroup glob is matched against groups, not package names" "$(cat "$test_tmp/err")"
pass "IgnorePkg and IgnoreGroup holds on the Aurora packages are preserved and warned about, as pacman applies them"

# The cache goes before the new pin lands, so no failure pairs the new pin with
# a stale database that a rerun would never revisit.
{ options_conf; aurora_conf "$old_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
{ options_conf; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } >"$test_tmp/expected"
reset_run
TEST_RM_FAIL=1 run_status
(( status == 2 )) || fail "a cache that cannot be removed stops the repin" "status $status: $(cat "$test_tmp/err")"
grep -Fq "could not remove the cached Aurora database in $sync_dir; pacman.conf is unchanged" "$test_tmp/err" ||
  fail "a failed cache removal is explained" "$(cat "$test_tmp/err")"
cmp -s "$test_tmp/before" "$pacman_conf" || fail "a failed cache removal leaves pacman.conf byte-identical"
! grep -Fq "sudo:install -o root -g root -m 0644" "$calls" || fail "a failed cache removal installs no pacman.conf" "$(cat "$calls")"
reset_run
run_status
expect_repinned "the retry after a failed cache removal"
grep -Fq "sudo:rm -f $sync_dir/omarchy-aurora.db $sync_dir/omarchy-aurora.db.sig" "$calls" || fail "the retry removes the cache" "$(cat "$calls")"
pass "a cache that cannot be removed leaves pacman.conf alone, and the retry does both"

{ options_conf; aurora_conf "$old_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
reset_run
{ TEST_INTERRUPT_INSTALL=1 run_status; } 2>/dev/null
(( status != 0 )) || fail "an interrupted repin does not report success"
cmp -s "$test_tmp/before" "$pacman_conf" || fail "an interrupted repin leaves the old pacman.conf"
[[ ! -e $sync_dir/omarchy-aurora.db && ! -e $sync_dir/omarchy-aurora.db.sig ]] || fail "the cache is already gone when the pin is interrupted"
: >"$calls"
: >"$curl_log"
run_status
expect_repinned "a rerun after an interrupted repin"
pass "a repin interrupted between the cache removal and the config install is completed by a rerun"

# Run on its own, the updater takes the update lock and says who syncs.
{ options_conf; omarchy_conf; remaining_conf; } >"$pacman_conf"
{ options_conf; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } >"$test_tmp/expected"
reset_run
TEST_LOCK_HELD=0 run_status
expect_repinned "a standalone repin"
grep -Fxq run "$lock_log" || fail "an updater run outside omarchy update takes the update lock" "$(cat "$lock_log")"
grep -Fxq 'omarchy update will sync it.' "$test_tmp/out" || fail "a standalone repin says omarchy update will sync it" "$(cat "$test_tmp/out")"
pass "a standalone run takes the update lock and leaves the sync to omarchy update"

# The channel record decides whether the pin applies at all.
rc_record() {
  printf 'format=1\nchannel=rc\nkernel=linux-aurora\n' >"$channel_record"
  [[ -z ${1:-} ]] || printf 'hold=%s\n' "$1" >>"$channel_record"
}

{ options_conf; aurora_conf "$old_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
printf 'format=1\nchannel=stable\nkernel=linux-asahi\n' >"$channel_record"
rm -f "$marker"
reset_run
TEST_INSTALLED="linux-asahi linux-asahi-headers m1n1" run_status
(( status == 0 )) || fail "a stable record is a successful no-op" "status $status: $(cat "$test_tmp/err")"
[[ ! -s $test_tmp/out && ! -s $test_tmp/err && ! -s $curl_log && ! -s $lock_log ]] ||
  fail "a stable Mac is silent, offline and takes no update lock" "$(cat "$test_tmp/err" "$lock_log")"
expect_untouched "a stable Mac with an [omarchy-aurora] on a predecessor"
pass "a Mac recorded as stable on linux-asahi leaves even a predecessor [omarchy-aurora] alone"

printf 'linux-aurora\n' >"$marker"
{ options_conf; aurora_conf "$old_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
{ options_conf; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } >"$test_tmp/expected"
printf 'format=1\nchannel=stable\nkernel=linux-aurora\n' >"$channel_record"
reset_run
run_status
expect_repinned "a stable:linux-aurora record still pins [omarchy-aurora]"
pass "a Mac recorded as stable on linux-aurora is managed like rc"

expect_held() {
  local description=$1 reason=$2
  (( status == 0 )) || fail "$description does not stop the update" "status $status: $(cat "$test_tmp/err")"
  printf "\e[33mLeaving [omarchy-aurora] as it is: this Mac's channel is held (%s).\e[0m\n" "$reason" | cmp -s - "$test_tmp/err" ||
    fail "$description says, in one line, that the channel is held and why" "$(cat -v "$test_tmp/err")"
  [[ ! -s $test_tmp/out && ! -s $curl_log ]] || fail "$description downloads nothing"
  expect_untouched "$description"
}
printf 'linux-aurora\n' >"$marker"
{ options_conf; aurora_conf "$old_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
rc_record "qualifying aurora-packages-4439238 by hand"
reset_run
run_status
expect_held "a held Mac on a predecessor" "qualifying aurora-packages-4439238 by hand"
{ options_conf; omarchy_conf; remaining_conf; } >"$pacman_conf"
reset_run
run_status
expect_held "a held Mac without [omarchy-aurora]" "qualifying aurora-packages-4439238 by hand"
{ options_conf; aurora_conf "$old_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
reset_run
TEST_LOCK_HELD=0 run_status
expect_held "a held Mac run on its own" "qualifying aurora-packages-4439238 by hand"
grep -Fxq run "$lock_log" || fail "a standalone run on a held Mac still takes the update lock" "$(cat "$lock_log")"
pass "a held rc Mac keeps [omarchy-aurora] exactly as it is and says why, standalone too"

# A hold that lands after the early checks but before the machine lock is honoured.
rc_record
reset_run
TEST_HOLD_BEFORE_LOCK="held while the update waited" run_status
expect_held "a hold that lands while the update waits for its locks" "held while the update waited"
pass "the pin decision reads the record under the machine lock"

record_refused() {
  local description=$1 message=$2
  cp "$channel_record" "$test_tmp/record-before"
  reset_run
  run_status
  (( status == 2 )) || fail "$description stops the update" "status $status: $(cat "$test_tmp/err")"
  grep -Fq "$message" "$test_tmp/err" || fail "$description is explained" "$(cat "$test_tmp/err")"
  [[ ! -s $test_tmp/out && ! -s $curl_log ]] || fail "$description downloads nothing"
  cmp -s "$test_tmp/record-before" "$channel_record" || fail "$description leaves the record as it was"
  expect_untouched "$description"
}
printf 'format=1\nchannel=rc\nkernel=linux-aurora\nchannel=rc\n' >"$channel_record"
record_refused "a record with a repeated key" "$channel_record repeats channel"
printf 'format=1\nchannel=edge\nkernel=linux-aurora\n' >"$channel_record"
record_refused "a record naming an unknown channel" "$channel_record pairs channel edge with kernel linux-aurora"
printf 'format=1\nchannel=rc\nkernel=linux-aurora\nhold=\n' >"$channel_record"
TEST_LOCK_HELD=0 record_refused "a standalone run with an empty hold" "$channel_record line 4 is not key=value"
rc_record "a hold does not excuse a contradicted record"
rm -f "$marker"
TEST_INSTALLED="linux-asahi linux-asahi-headers m1n1" record_refused "a held rc record on an Asahi Mac" \
  "$channel_record names linux-aurora, but this Mac runs linux-asahi"
printf 'linux-aurora\n' >"$marker"
pass "an invalid or contradicted channel record stops the update before any pacman.conf change"

# The updater takes the machine lock itself, so a channel change cannot slip in.
{ options_conf; aurora_conf "$old_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
{ options_conf; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } >"$test_tmp/expected"
rc_record
reset_run
rm -f "$test_tmp/channel-lock-ready"
TEST_TAKE_CHANNEL_LOCK=1 TEST_CHANNEL_LOCK_TIMEOUT=0.3 run_status
holder=$(cat "$test_tmp/channel-lock-holder")
kill "$holder" 2>/dev/null || true
while kill -0 "$holder" 2>/dev/null; do sleep 0.05; done
(( status == 2 )) || fail "a repin that cannot take the channel lock stops" "status $status: $(cat "$test_tmp/err")"
grep -Fq "could not lock $channel_dir" "$test_tmp/err" || fail "a busy channel lock is explained" "$(cat "$test_tmp/err")"
[[ ! -s $curl_log ]] || fail "a busy channel lock downloads nothing"
expect_untouched "a busy channel lock"
reset_run
run_status
expect_repinned "the rerun once the channel lock is free"
pass "the updater holds the machine channel lock, and waits no longer than its timeout for it"

# A hold that arrives mid-repin waits for the updater's channel lock and then
# governs the next run.
channel_helper() {
  TEST_CALLS="$calls" \
    TEST_CHANNEL_CALLS="$channel_calls" \
    TEST_INSTALLED="${TEST_INSTALLED-linux-aurora linux-aurora-headers m1n1-aurora}" \
    OMARCHY_APPLE_SILICON_CHANNEL_ROOT="$root" \
    OMARCHY_APPLE_SILICON_CHANNEL_TESTING=1 \
    OMARCHY_APPLE_SILICON_CHANNEL_LOCK_TIMEOUT=30 \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-apple-silicon-channel" "$@"
}
{ options_conf; aurora_conf "$old_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
{ options_conf; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } >"$test_tmp/expected"
rc_record
reset_run
rm -f "$staged_descriptor"
gate="$test_tmp/curl-gate"
rm -f "$gate".*
( TEST_CURL_GATE="$gate" run_status; echo "$status" >"$gate.status" ) &
updater_pid=$!
for _ in $(seq 200); do
  [[ -e $gate.waiting ]] && break
  sleep 0.05
done
[[ -e $gate.waiting ]] || fail "the updater reached its download inside the channel lock"
channel_helper hold "arrived mid-repin" >"$test_tmp/hold.out" 2>"$test_tmp/hold.err" &
hold_pid=$!
sleep 1
kill -0 "$hold_pid" 2>/dev/null || fail "a hold started mid-repin waits for the updater" "$(cat "$test_tmp/hold.out" "$test_tmp/hold.err")"
! grep -q '^hold=' "$channel_record" || fail "a hold started mid-repin does not land during it"
: >"$gate.go"
wait "$updater_pid"
status=$(cat "$gate.status")
wait "$hold_pid" || fail "the waiting hold succeeds once the updater finishes" "$(cat "$test_tmp/hold.err")"
expect_repinned "the repin that was underway when the hold arrived"
grep -Fxq 'hold=arrived mid-repin' "$channel_record" || fail "the hold is committed after the repin" "$(cat "$channel_record")"
{ options_conf; aurora_conf "$old_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
reset_run
run_status
expect_held "the run after a hold that waited" "arrived mid-repin"
pass "the updater's critical section holds the channel lock: a concurrent hold waits, then governs the next run"

# End to end: omarchy-update-system-pkgs stops before pacman -Syu on a record it cannot trust.
{ options_conf; omarchy_conf; remaining_conf; } >"$pacman_conf"
rm -f "$marker"
printf 'format=1\nchannel=stable\nkernel=linux-asahi\n' >"$channel_record"
reset_run
OMARCHY_APPLE_BOOT_UNAVAILABLE=1 TEST_SCRIPT="$system_packages" TEST_INSTALLED="linux-asahi linux-asahi-headers m1n1" run_status
(( status == 0 )) || fail "a valid stable record lets the system upgrade run" "status $status: $(cat "$test_tmp/err")"
grep -q '^pacman:-Syu' "$calls" || fail "the system upgrade reaches pacman -Syu with a valid record" "$(cat "$calls")"
printf 'format=1\nchannel=stable\nkernel=linux-asahi\nkernel=linux-asahi\n' >"$channel_record"
reset_run
OMARCHY_APPLE_BOOT_UNAVAILABLE=1 TEST_SCRIPT="$system_packages" TEST_INSTALLED="linux-asahi linux-asahi-headers m1n1" run_status
(( status == 1 )) || fail "a malformed stable record fails the system upgrade" "status $status: $(cat "$test_tmp/err")"
grep -Fq "$channel_record repeats kernel" "$test_tmp/err" || fail "the malformed record is named" "$(cat "$test_tmp/err")"
! grep -q -- '-Syu' "$calls" || fail "a malformed stable record stops before pacman -Syu" "$(cat "$calls")"
expect_untouched "a malformed stable record under omarchy-update-system-pkgs"
[[ ! -e $root/run ]] || fail "no lock file is created"
pass "a malformed stable record stops omarchy-update-system-pkgs before pacman -Syu"

# Re-entry trusts no flag: the inherited descriptor must be open on the record's
# directory and hold its lock, and the update lock must be held too.
{ options_conf; aurora_conf "$old_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
printf 'linux-aurora\n' >"$marker"
rc_record
reentry_refused() {
  local description=$1 message=$2
  (( status == 2 )) || fail "$description stops the updater" "status $status: $(cat "$test_tmp/err")"
  grep -Fq "$message" "$test_tmp/err" || fail "$description is explained" "$(cat "$test_tmp/err")"
  [[ ! -s $test_tmp/out && ! -s $curl_log ]] || fail "$description downloads nothing"
  expect_untouched "$description"
}
reset_run
OMARCHY_APPLE_SILICON_CHANNEL_LOCKED=1 run_status
reentry_refused "a preset lock flag without a descriptor" "OMARCHY_APPLE_SILICON_CHANNEL_LOCK_FD is not a descriptor number"
reset_run
OMARCHY_APPLE_SILICON_CHANNEL_LOCKED=1 OMARCHY_APPLE_SILICON_CHANNEL_LOCK_FD=97 run_status
reentry_refused "a lock flag naming a closed descriptor" "descriptor 97 is not open"
mkdir -p "$test_tmp/elsewhere"
reset_run
{ OMARCHY_APPLE_SILICON_CHANNEL_LOCKED=1 OMARCHY_APPLE_SILICON_CHANNEL_LOCK_FD=97 run_status; } 97<"$test_tmp/elsewhere"
reentry_refused "a descriptor open on another directory" "descriptor 97 is not open on $channel_dir"
(
  exec 9<"$channel_dir"
  flock -x 9
  : >"$test_tmp/other-holder-ready"
  exec sleep 30
) &
other_holder=$!
until [[ -e $test_tmp/other-holder-ready ]]; do sleep 0.05; done
reset_run
{ OMARCHY_APPLE_SILICON_CHANNEL_LOCKED=1 OMARCHY_APPLE_SILICON_CHANNEL_LOCK_FD=97 run_status; } 97<"$channel_dir"
kill "$other_holder" 2>/dev/null || true
wait "$other_holder" 2>/dev/null || true
reentry_refused "a descriptor on the directory whose lock another process holds" "descriptor 97 does not hold the lock on $channel_dir"
reset_run
TEST_LOCK_HELD=0 TEST_SCRIPT="$ROOT/bin/omarchy-apple-silicon-channel" run_status locked bash "$updater"
reentry_refused "a real channel lock without the update lock" "the update lock is not held"
{ options_conf; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } >"$test_tmp/expected"
reset_run
TEST_SCRIPT="$ROOT/bin/omarchy-apple-silicon-channel" run_status locked bash "$updater"
expect_repinned "an updater that inherited the channel lock from locked"
pass "re-entry needs a descriptor that holds the channel lock on the record's directory, and the update lock"

# Offline mode: the section is already on the pin and a trusted staged descriptor
# matches that digest, so nothing is downloaded. Curl is stubbed to fail.
printf 'linux-aurora\n' >"$marker"
printf 'format=1\nchannel=rc\nkernel=linux-aurora\n' >"$channel_record"
{ options_conf; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
install -m 0644 "$assets/$new_tag/AURORA" "$staged_descriptor"
reset_run
OMARCHY_AURORA_OFFLINE=1 TEST_CURL_OFFLINE=1 run_status
(( status == 0 )) || fail "offline mode on the pin with a staged descriptor succeeds" "status $status: $(cat "$test_tmp/err")"
[[ ! -s $curl_log ]] || fail "offline mode on the pin downloads nothing" "$(cat "$curl_log")"
expect_untouched "offline mode on the pin with a staged descriptor"
pass "OMARCHY_AURORA_OFFLINE=1 accepts the staged pin descriptor and does not download"

rm -f "$staged_descriptor"
reset_run
OMARCHY_AURORA_OFFLINE=1 TEST_CURL_OFFLINE=1 run_status
(( status == 2 )) || fail "offline mode without a staged descriptor fails closed" "status $status: $(cat "$test_tmp/err")"
grep -Fq "offline mode requires a trusted staged descriptor matching $new_tag" "$test_tmp/err" ||
  fail "offline mode names the missing staged descriptor" "$(cat "$test_tmp/err")"
[[ ! -s $curl_log ]] || fail "offline mode without a staged descriptor does not curl" "$(cat "$curl_log")"
expect_untouched "offline mode without a staged descriptor"
pass "OMARCHY_AURORA_OFFLINE=1 refuses a download when the staged descriptor is missing"

{ options_conf; aurora_conf "$old_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
install -m 0644 "$assets/$new_tag/AURORA" "$staged_descriptor"
reset_run
OMARCHY_AURORA_OFFLINE=1 TEST_CURL_OFFLINE=1 run_status
(( status == 2 )) || fail "offline mode off the pin fails closed" "status $status: $(cat "$test_tmp/err")"
grep -Fq "offline mode requires [omarchy-aurora] on $new_tag" "$test_tmp/err" ||
  fail "offline mode names the pin it requires" "$(cat "$test_tmp/err")"
[[ ! -s $curl_log ]] || fail "offline mode off the pin does not curl" "$(cat "$curl_log")"
expect_untouched "offline mode off the pin"
pass "OMARCHY_AURORA_OFFLINE=1 refuses to move [omarchy-aurora] and does not download"

# Image builds keep the builder's [omarchy-aurora] even when that release is
# neither the runtime pin nor a predecessor, and still stage its descriptor.
write_release "$candidate_tag"
printf 'linux-aurora\n' >"$marker"
printf 'format=1\nchannel=rc\nkernel=linux-aurora\n' >"$channel_record"
{ options_conf; aurora_conf "$candidate_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
reset_run
rm -f "$staged_descriptor"
OMARCHY_MAC_IMAGE_BUILD=1 run_status
(( status == 0 )) || fail "image mode on a builder pin succeeds" "status $status: $(cat "$test_tmp/err")"
grep -Fq "image mode keeps the builder's [omarchy-aurora] on $candidate_tag" "$test_tmp/err" ||
  fail "image mode names the builder's pin" "$(cat "$test_tmp/err")"
grep -Fxq "$candidate_server/AURORA" "$curl_log" && grep -Fxq "$candidate_server/AURORA.sig" "$curl_log" ||
  fail "image mode verifies the builder pin's signed descriptor" "$(cat "$curl_log")"
expect_untouched "image mode on a lane release that is not the runtime pin"
cmp -s "$assets/$candidate_tag/AURORA" "$staged_descriptor" ||
  fail "image mode stages the builder pin's descriptor" "$(cat "$staged_descriptor" 2>&1)"
[[ $(stat -c '%a' "$staged_descriptor") == 644 ]] || fail "the image-mode staged descriptor is 0644"
pass "image mode stages the builder's [omarchy-aurora] descriptor without moving the section"
