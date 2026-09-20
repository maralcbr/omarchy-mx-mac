#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command sha256sum

hook="$ROOT/default/libalpm/hooks/01-omarchy-aurora-verify.hook"
verifier="$ROOT/bin/omarchy-update-aurora-verify"

[[ -f $hook ]] || fail "the Aurora verification hook ships in the runtime"
for line in '[Trigger]' 'Operation = Install' 'Operation = Upgrade' 'Type = Package' 'Target = linux-aurora' \
  'Target = linux-aurora-headers' 'Target = m1n1-aurora' '[Action]' 'When = PreTransaction' \
  'Exec = /usr/bin/omarchy-update-aurora-verify' 'AbortOnFail'; do
  grep -Fxq "$line" "$hook" || fail "the hook has '$line'" "$(cat "$hook")"
done
(( $(grep -c '^Target = ' "$hook") == 3 )) || fail "the hook targets only the Aurora kernel and bootloader packages"
# Hooks run in file-name order; one that aborts after the reload pause would leave it paused.
[[ ${hook##*/} < 10-omarchy-hyprland-reload-pause.hook ]] || fail "the hook runs before any hook with side effects"
grep -Fq '# omarchy:hidden=true' "$verifier" || fail "the verifier is hidden from command listings"
pass "the hook aborts Aurora package transactions before they start and runs ahead of Omarchy's other hooks"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

root="$test_tmp/root"
state_dir="$root/var/lib/omarchy"
descriptor="$state_dir/aurora-target.descriptor"
pacman_conf="$root/etc/pacman.conf"
sync_dir="$root/var/lib/pacman/sync"
repo=https://github.com/maralcbr/omarchy-pkgs/releases/download
pin_tag=aurora-packages-1c5e34c99dc2510bf06c673165a79aa92c8f1f4c
stable_tag=aurora-stable-packages-77cb8f2477cb8f2477cb8f2477cb8f2477cb8f24
edge_tag=aurora-edge-12
mkdir -p "$state_dir" "$root/etc" "$sync_dir"
chmod 0755 "$state_dir"

write_descriptor() {
  local tag=$1 database=$2
  {
    printf 'format=1\nchannel=aurora\nrelease_tag=%s\n' "$tag"
    printf 'package=1|linux-aurora|6.17.0-1|aarch64|f|%064d|f.sig|%064d\n' 1 2
    printf 'asset=omarchy-aurora.db|%s\nasset=omarchy-aurora.db.sig|%064d\n' "$database" 3
  } >"$descriptor"
  chmod 0644 "$descriptor"
}

write_conf() {
  {
    printf '[options]\nArchitecture = aarch64\n%s\n\n' "${2:-}"
    [[ -z $1 ]] || printf '[omarchy-aurora]\nSigLevel = Required DatabaseOptional\n%s\n\n' "$1"
    printf '[omarchy]\nServer = https://example.test/omarchy\n'
  } >"$pacman_conf"
}

run_verify() {
  set +e
  OMARCHY_AURORA_ROOT="$root" OMARCHY_APPLE_SILICON_CHANNEL_TESTING=1 bash "$verifier" >"$test_tmp/out" 2>"$test_tmp/err"
  status=$?
  set -e
}

printf 'the synced database' >"$sync_dir/omarchy-aurora.db"
good=$(sha256sum "$sync_dir/omarchy-aurora.db" | cut -d' ' -f1)

write_conf "Server = $repo/$pin_tag"
write_descriptor "$pin_tag" "$good"
run_verify
(( status == 0 )) && [[ ! -s $test_tmp/out && ! -s $test_tmp/err ]] ||
  fail "the staged release's database passes quietly" "status $status: $(cat "$test_tmp/out" "$test_tmp/err")"
write_conf "Server = $repo/$edge_tag/"
write_descriptor "$edge_tag" "$good"
run_verify
(( status == 0 )) || fail "an edge release's database passes" "status $status: $(cat "$test_tmp/err")"
write_conf "Server = $repo/$stable_tag"
write_descriptor "$stable_tag" "$good"
run_verify
(( status == 0 )) || fail "a stable release's database passes" "status $status: $(cat "$test_tmp/err")"
write_conf "Server = $repo/$pin_tag" 'DBPath = /srv/pacman/'
mkdir -p "$root/srv/pacman/sync"
cp "$sync_dir/omarchy-aurora.db" "$root/srv/pacman/sync/"
write_descriptor "$pin_tag" "$good"
run_verify
(( status == 0 )) || fail "a database under a configured DBPath passes" "status $status: $(cat "$test_tmp/err")"
printf 'another database' >"$root/srv/pacman/sync/omarchy-aurora.db"
run_verify
(( status == 1 )) || fail "the DBPath database is the one checked" "status $status"
pass "a synced database the staged descriptor names passes, for rc, stable and edge releases and any DBPath"

aborted() {
  local description=$1 message=$2
  run_verify
  (( status == 1 )) || fail "$description aborts the transaction" "status $status: $(cat "$test_tmp/out")"
  grep -Fq "$message" "$test_tmp/err" || fail "$description is explained" "$(cat "$test_tmp/err")"
  grep -Fq "run omarchy update" "$test_tmp/err" || fail "$description says how to recover" "$(cat "$test_tmp/err")"
}
write_conf "Server = $repo/$pin_tag"
write_descriptor "$pin_tag" "$good"
printf 'a database from another release' >"$sync_dir/omarchy-aurora.db"
aborted "a synced database the descriptor does not name" "the synced omarchy-aurora database is not the one $pin_tag's signed descriptor names"
printf 'the synced database' >"$sync_dir/omarchy-aurora.db"
write_conf "Server = $repo/$stable_tag"
write_descriptor "$stable_tag" "$good"
printf 'a database from another stable release' >"$sync_dir/omarchy-aurora.db"
aborted "a stable synced database the descriptor does not name" "the synced omarchy-aurora database is not the one $stable_tag's signed descriptor names"
printf 'the synced database' >"$sync_dir/omarchy-aurora.db"
rm "$sync_dir/omarchy-aurora.db"
aborted "a missing synced database" "omarchy-aurora.db is missing"
printf 'the synced database' >"$sync_dir/omarchy-aurora.db"
chmod 0664 "$descriptor"
aborted "a staged descriptor others can write" "is not a file only root can change"
chmod 0644 "$descriptor"
chmod 0775 "$state_dir"
aborted "a state directory others can write" "is not a file only root can change"
chmod 0755 "$state_dir"
mv "$descriptor" "$test_tmp/real-descriptor"
ln -s "$test_tmp/real-descriptor" "$descriptor"
aborted "a symlinked staged descriptor" "is not a file only root can change"
rm "$descriptor"
write_descriptor "$pin_tag" "$good"
printf 'release_tag=%s\n' "$pin_tag" >>"$descriptor"
aborted "a descriptor naming two releases" "is malformed"
write_descriptor "$pin_tag" "not-a-digest"
aborted "a descriptor without a database digest" "is malformed"
pass "a mismatched or missing database and an untrustworthy or malformed staged descriptor abort before anything installs"

passed_with_notice() {
  local description=$1 message=$2
  run_verify
  (( status == 0 )) || fail "$description lets the transaction through" "status $status: $(cat "$test_tmp/err")"
  (( $(wc -l <"$test_tmp/out") == 1 )) && grep -Fq "$message" "$test_tmp/out" ||
    fail "$description says so in one line" "$(cat "$test_tmp/out" "$test_tmp/err")"
}
printf 'a database omarchy update never checked' >"$sync_dir/omarchy-aurora.db"
write_descriptor "$pin_tag" "$good"
write_conf "Server = $repo/aurora-packages-4439238d23d28c8d3766a6dd040a9e5f9fd587e0"
passed_with_notice "a release pinned by hand" "is on aurora-packages-4439238d23d28c8d3766a6dd040a9e5f9fd587e0, not $pin_tag"
write_conf "Server = https://example.test/aurora"
passed_with_notice "a server outside the releases" "not on a single release omarchy update manages"
write_conf "Include = /etc/pacman.d/aurora"
passed_with_notice "an included server list" "not on a single release omarchy update manages"
write_conf "Server = $repo/$pin_tag"$'\n'"Server = $repo/$edge_tag"
passed_with_notice "two releases" "not on a single release omarchy update manages"
write_conf ""
passed_with_notice "no [omarchy-aurora] (pacman -U)" "not on a single release omarchy update manages"
write_conf "Server = $repo/$pin_tag"
rm "$descriptor"
passed_with_notice "nothing staged yet" "omarchy update has not staged a release yet"
pass "a hand-pinned or unmanaged section, or nothing staged, is the owner's choice: one notice, and pacman goes on"
