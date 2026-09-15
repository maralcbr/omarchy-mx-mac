#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command sha256sum
require_command truncate

updater="$ROOT/bin/omarchy-update-aurora-repository"
system_packages="$ROOT/bin/omarchy-update-system-pkgs"
shipped_pin="$ROOT/default/aurora-qualified-release"
subkey_fingerprint=CAB18E175BFB9ACCE185234474DE0C737AC186E4
repo=maralcbr/omarchy-pkgs

grep -Fq '# omarchy:hidden=true' "$updater" || fail "Aurora repository updater is hidden from command listings"
grep -Fq '# omarchy:requires-sudo=true' "$updater" || fail "Aurora repository updater declares its sudo requirement"
grep -Fq "trusted_subkey=$subkey_fingerprint" "$updater" || fail "Aurora repository updater pins the signing subkey"
grep -Fq '$2 == "VALIDSIG" && $3 == key' "$updater" ||
  fail "Aurora repository updater requires the descriptor signature from the subkey itself"
grep -Exq 'tag=aurora-packages-[0-9a-f]{40}' "$shipped_pin" || fail "the runtime pins an aurora-packages release"
grep -Exq 'descriptor_sha256=[0-9a-f]{64}' "$shipped_pin" || fail "the runtime pins that release's descriptor digest"
(( $(grep -c '^tag=' "$shipped_pin") == 1 && $(grep -c '^descriptor_sha256=' "$shipped_pin") == 1 )) ||
  fail "the runtime pins exactly one Aurora release"
pass "the qualified Aurora release is pinned in the runtime"

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
TEST_AURORA_STATUS=3 run_system_packages
(( status == 1 )) || fail "a failed Aurora repin fails the system update without its own status" "status $status"
! grep -q '^pacman' "$test_tmp/order" || fail "a failed Aurora repin stops before pacman" "$(cat "$test_tmp/order")"
pass "omarchy-update-system-pkgs pins the Aurora repository before pacman and stops when it cannot"

stub_bin="$test_tmp/bin"
assets="$test_tmp/assets"
root="$test_tmp/root"
pacman_conf="$root/etc/pacman.conf"
marker="$root/usr/share/omarchy/apple-silicon-kernel"
sync_dir="$root/var/lib/pacman/sync"
pin_file="$test_tmp/aurora-qualified-release"
calls="$test_tmp/calls"
curl_log="$test_tmp/curl.log"
lock_log="$test_tmp/lock.log"
old_tag=aurora-packages-4123759c0ffee4123759c0ffee4123759c0ffee4
new_tag=aurora-packages-1c5e34c99dc2510bf06c673165a79aa92c8f1f4c
old_server="https://github.com/$repo/releases/download/$old_tag"
new_server="https://github.com/$repo/releases/download/$new_tag"
asahi_server="https://github.com/$repo/releases/download/asahi-packages-stable-83973903b7deb9b56ce75f02b432fba0561d6293"
comment='# Aurora kernel and bootloader, kept on the qualified release by omarchy update'
mkdir -p "$stub_bin" "$assets" "$root/etc/pacman.d" "$(dirname "$marker")" "$sync_dir"
: >"$test_tmp/omarchy-arm-repository.asc"
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
EOF
  printf 'signature\n' >"$assets/$tag/AURORA.sig"
}

write_pin() {
  printf '# pinned for the test\ntag=%s\ndescriptor_sha256=%s\n' "$1" "$2" >"$pin_file"
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
  printf 'pub:-:255:22:%s:::::::cSC::::::::0:\nfpr:::::::::%s:\n' "${primary:24}" "$primary"
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
if [[ $1 == "-Q" ]]; then
  [[ " $TEST_INSTALLED " == *" $2 "* ]]
  exit
fi
printf 'pacman:%s OMARCHY_UPDATE_PACMAN=%s\n' "$*" "${OMARCHY_UPDATE_PACMAN:-}" >>"$TEST_CALLS"
[[ ${TEST_PACMAN_FAIL:-0} != 1 ]]
SH
chmod +x "$stub_bin"/*

run_status() {
  set +e
  TEST_ASSETS="$assets" \
    TEST_CURL_LOG="$curl_log" \
    TEST_CALLS="$calls" \
    TEST_LOCK_LOG="$lock_log" \
    TEST_KEY_STATE="$test_tmp/key-trusted" \
    TEST_INSTALLED="${TEST_INSTALLED-linux-aurora linux-aurora-headers m1n1-aurora}" \
    OMARCHY_AURORA_ROOT="$root" \
    OMARCHY_AURORA_RELEASE_PIN="$pin_file" \
    OMARCHY_AURORA_PACKAGE_KEY_FILE="$test_tmp/omarchy-arm-repository.asc" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$updater" "$@" >"$test_tmp/out" 2>"$test_tmp/err"
  status=$?
  set -e
}

reset_run() {
  : >"$curl_log"
  : >"$calls"
  : >"$lock_log"
  rm -f "$test_tmp/key-trusted"
  rm -rf "$root/var/lib/omarchy/backups"
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
}

write_release "$old_tag"
write_release "$new_tag"
new_digest=$(sha256sum "$assets/$new_tag/AURORA" | cut -d' ' -f1)
write_pin "$new_tag" "$new_digest"

# Machines that are not Aurora installs.
{ options_conf; omarchy_conf; remaining_conf; } >"$pacman_conf"
not_aurora() {
  local description=$1
  reset_run
  run_status
  (( status == 0 )) || fail "$description exits cleanly" "status $status: $(cat "$test_tmp/err")"
  [[ ! -s $test_tmp/out && ! -s $test_tmp/err ]] || fail "$description is silent" "$(cat "$test_tmp/out" "$test_tmp/err")"
  [[ ! -s $curl_log && ! -s $lock_log ]] || fail "$description downloads nothing and takes no lock"
  expect_untouched "$description"
}
rm -f "$marker"
TEST_INSTALLED="linux-asahi linux-asahi-headers m1n1" not_aurora "an Asahi install without the marker"
printf 'linux-asahi\n' >"$marker"
not_aurora "an Asahi marker, even with linux-aurora installed"
printf 'linux-aurora\n' >"$marker"
TEST_INSTALLED="linux-asahi" not_aurora "an Aurora marker without linux-aurora installed"
printf 'linux-aurora\n' >"$test_tmp/linked-marker"
rm -f "$marker"
ln -s "$test_tmp/linked-marker" "$marker"
not_aurora "a symlinked kernel marker"
rm -f "$marker"
TEST_INSTALLED="linux-aurora linux-asahi" not_aurora "linux-aurora and linux-asahi both installed without a marker"
{ options_conf; remaining_conf; } >"$pacman_conf"
TEST_APPLE_SILICON=0 not_aurora "an x86 machine"
pass "only Aurora installs are touched, and everything else is a silent no-op"

# A missing section is added right before [omarchy], with the legacy evidence.
{ options_conf; omarchy_conf; remaining_conf; } >"$pacman_conf"
{ options_conf; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } >"$test_tmp/expected"
reset_run
run_status
(( status == 0 )) || fail "a missing [omarchy-aurora] is added" "status $status: $(cat "$test_tmp/err")"
expect_conf "[omarchy-aurora] is inserted just before [omarchy] and nothing else changes"
grep -Fxq "Pinned the Aurora kernel repository to $new_tag (backup: $(ls -d "$root"/var/lib/omarchy/backups/aurora-repository-*))" "$test_tmp/out" ||
  fail "the repin names the release and the backup" "$(cat "$test_tmp/out")"
grep -Fxq "$new_server/AURORA" "$curl_log" && grep -Fxq "$new_server/AURORA.sig" "$curl_log" ||
  fail "the pinned release's descriptor and signature are downloaded" "$(cat "$curl_log")"
cmp -s "$test_tmp/before" "$root"/var/lib/omarchy/backups/aurora-repository-*/pacman.conf || fail "the previous pacman.conf is backed up"
[[ $(stat -c '%a' "$pacman_conf") == 644 ]] || fail "pacman.conf stays 0644"
[[ ! -e $pacman_conf.omarchy-aurora ]] || fail "the staged pacman.conf is renamed into place"
grep -Eq "^sudo:mv -f $pacman_conf.omarchy-aurora $pacman_conf\$" "$calls" || fail "pacman.conf is replaced by rename" "$(cat "$calls")"
grep -Fxq "pacman-key:--add $test_tmp/omarchy-arm-repository.asc" "$calls" || fail "a missing repository key is imported into pacman"
grep -Fxq 'pacman:-Sy --noconfirm OMARCHY_UPDATE_PACMAN=1' "$calls" || fail "the repinned repository is synced through the update guard"
[[ ! -e $sync_dir/omarchy-aurora.db && ! -e $sync_dir/omarchy-aurora.db.sig ]] || fail "the previous release's cached database is dropped"
pass "a missing [omarchy-aurora] is inserted before [omarchy] after the release is proven"

reset_run
run_status
(( status == 0 )) || fail "a current Aurora repository is a successful no-op" "status $status: $(cat "$test_tmp/err")"
[[ ! -s $test_tmp/out && ! -s $test_tmp/err && ! -s $curl_log ]] || fail "a current Aurora repository is silent and offline"
expect_untouched "a second run"
pass "a second run makes no write"

# An existing section on an old release is repointed in place, marker evidence.
printf 'linux-aurora\n' >"$marker"
{
  options_conf
  printf '# The signed Aurora kernel.\n[omarchy-aurora]\nServer = %s\nSigLevel = Optional TrustAll\nServer = https://example.test/extra\nUsage = Sync Search\n\n' "$old_server"
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
(( status == 0 )) || fail "an old Aurora pin is repointed" "status $status: $(cat "$test_tmp/err")"
expect_conf "the old pin gets exactly one Server on the qualified release and the required SigLevel"
pass "an old [omarchy-aurora] pin is repointed at the qualified release"

# A section behind [omarchy] moves in front of it, its comment with it.
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
(( status == 0 )) || fail "a misplaced Aurora section is moved" "status $status: $(cat "$test_tmp/err")"
expect_conf "the misplaced section moves to just before [omarchy]"
pass "an [omarchy-aurora] section after [omarchy] is moved in front of it"

# A file that ends without a newline keeps ending that way.
{ options_conf; omarchy_conf; remaining_conf; } | head -c -1 >"$pacman_conf"
{ options_conf; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } | head -c -1 >"$test_tmp/expected"
reset_run
run_status
(( status == 0 )) || fail "a file without a final newline is repinned" "status $status: $(cat "$test_tmp/err")"
expect_conf "a missing final newline is preserved"
pass "unrelated bytes, including a missing final newline, are preserved"

# Nothing is written unless the pinned release is proven.
{ options_conf; aurora_conf "$old_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
reset_run
write_pin "$new_tag" "$(printf '%064d' 0)"
run_status
(( status == 2 )) || fail "a descriptor digest mismatch fails closed" "status $status"
grep -Fq "AURORA in $new_tag does not match the qualified digest" "$test_tmp/err" || fail "the digest mismatch is explained" "$(cat "$test_tmp/err")"
expect_untouched "a digest mismatch"
write_pin "$new_tag" "$new_digest"

reset_run
TEST_GPG_FAIL=1 run_status
(( status == 2 )) || fail "a bad descriptor signature fails closed" "status $status"
grep -Fq 'signature verification failed for AURORA' "$test_tmp/err" || fail "the bad signature is explained" "$(cat "$test_tmp/err")"
expect_untouched "a bad signature"
reset_run
TEST_GPG_SIGNER=primary run_status
(( status == 2 )) || fail "a descriptor signed by the primary key fails closed" "status $status"
expect_untouched "a primary-key signature"

reset_run
TEST_CURL_OFFLINE=1 run_status
(( status == 3 )) || fail "a download failure fails with the transport status" "status $status"
expect_untouched "a download failure"

# Another release's descriptor under this tag, with a pin that matches it.
reset_run
mv "$assets/$new_tag/AURORA" "$test_tmp/new-descriptor"
cp "$assets/$old_tag/AURORA" "$assets/$new_tag/AURORA"
write_pin "$new_tag" "$(sha256sum "$assets/$old_tag/AURORA" | cut -d' ' -f1)"
run_status
(( status == 2 )) || fail "a descriptor for another release fails closed" "status $status"
grep -Fq "does not describe that Aurora release" "$test_tmp/err" || fail "the wrong release is explained" "$(cat "$test_tmp/err")"
expect_untouched "a descriptor for another release"
mv "$test_tmp/new-descriptor" "$assets/$new_tag/AURORA"
write_pin "$new_tag" "$new_digest"

reset_run
TEST_PACMAN_FAIL=1 run_status
(( status == 2 )) || fail "a release pacman cannot read fails closed" "status $status"
grep -Fq 'restored the previous repository' "$test_tmp/err" || fail "the restore is explained" "$(cat "$test_tmp/err")"
cmp -s "$test_tmp/before" "$pacman_conf" || fail "a failed sync restores the previous pacman.conf"
pass "a digest mismatch, bad signature, download failure or unreadable release leaves pacman.conf as it was"

# Configurations this cannot safely edit are refused before any download.
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
{ options_conf; printf '[omarchy-aurora]\nInclude = /etc/pacman.d/mirrorlist\n\n'; omarchy_conf; remaining_conf; } >"$pacman_conf"
refused "an [omarchy-aurora] that includes a server list" 'must name its release'
{ options_conf; omarchy_conf; remaining_conf; } >"$pacman_conf"
printf 'tag=%s\n' "$new_tag" >"$pin_file"
refused "a pin without a digest" 'pin is malformed'
write_pin "$new_tag" "$new_digest"
pass "duplicate sections, a missing [omarchy], Include and a malformed pin are refused without edits"

# A hold is kept, and named.
{ options_conf 'IgnorePkg = linux-aurora linux-aurora-headers'; omarchy_conf; remaining_conf; } >"$pacman_conf"
{ options_conf 'IgnorePkg = linux-aurora linux-aurora-headers'; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } >"$test_tmp/expected"
reset_run
run_status
(( status == 0 )) || fail "a held kernel still gets its repository" "status $status: $(cat "$test_tmp/err")"
expect_conf "the IgnorePkg hold is preserved while the section is added"
grep -Fq 'holds linux-aurora linux-aurora-headers, so omarchy update cannot install a newer Aurora kernel until that hold is removed' "$test_tmp/err" ||
  fail "the hold is named with what it blocks" "$(cat "$test_tmp/err")"
{ options_conf 'IgnoreGroup = m1n1-*'; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
reset_run
run_status
(( status == 0 )) || fail "a current repository with a glob hold is a no-op" "status $status"
grep -Fq 'holds m1n1-aurora' "$test_tmp/err" || fail "a glob hold on m1n1-aurora is named" "$(cat "$test_tmp/err")"
expect_untouched "a current repository with a hold"
pass "IgnorePkg and IgnoreGroup holds on the Aurora packages are preserved and warned about"

# Run on its own, the updater takes the update lock.
{ options_conf; aurora_conf "$new_server"; omarchy_conf; remaining_conf; } >"$pacman_conf"
reset_run
TEST_LOCK_HELD=0 run_status
(( status == 0 )) || fail "the updater runs under the update lock" "status $status: $(cat "$test_tmp/err")"
grep -Fxq run "$lock_log" || fail "an updater run outside omarchy update takes the update lock" "$(cat "$lock_log")"
pass "the updater runs under the Omarchy update lock"
