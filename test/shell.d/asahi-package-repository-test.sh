#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
pacman_conf="$test_tmp/pacman.conf"
key_file="$test_tmp/omarchy-release.gpg"
calls="$test_tmp/calls"
key_state="$test_tmp/key-added"
leaf="$ROOT/install/hardware/pacman.sh"
migration="$ROOT/migrations/1787560726.sh"
mkdir -p "$mock_bin"
: >"$key_file"

cat >"$mock_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
exit "${OMARCHY_TEST_APPLE:-0}"
SH
cat >"$mock_bin/gpg" <<'SH'
#!/bin/bash
printf '%s\n' 'pub:-:255:22:CFF35022CA5B5959:0:0::-:::scESC:::::ed25519:::0:'
printf '%s\n' 'fpr:::::::::5983B1CA32CB778F4D74D24ECFF35022CA5B5959:'
SH
cat >"$mock_bin/pacman-key" <<'SH'
#!/bin/bash
printf 'pacman-key:%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
if [[ $1 == "--finger" ]]; then
  [[ -f $OMARCHY_TEST_KEY_STATE ]]
elif [[ $1 == "--add" ]]; then
  : >"$OMARCHY_TEST_KEY_STATE"
fi
SH
cat >"$mock_bin/pacman" <<'SH'
#!/bin/bash
printf 'pacman:%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
SH
cat >"$mock_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
"$@"
SH
cat >"$mock_bin/lspci" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$mock_bin"/*

db_path="$test_tmp/pacman-db"
mkdir -p "$db_path/sync"
# A database left by a previously pinned tag. Repointing the repository must
# drop it, or pacman keeps it and rejects it against the new tag's signature.
printf 'stale-candidate-database' >"$db_path/sync/omarchy.db"
printf 'stale-signature' >"$db_path/sync/omarchy.db.sig"

cat >"$pacman_conf" <<CONF
[options]
Architecture = aarch64
DBPath = $db_path

[asahi-alarm]
Server = https://github.com/asahi-alarm/asahi-alarm/releases/download/\$arch

[omarchy]
SigLevel = Never
Server = https://pkgs.omarchy.org/edge/\$arch

[core]
Server = http://mirror.archlinuxarm.org/\$arch/\$repo
CONF

run_leaf() {
  OMARCHY_PATH="$ROOT" \
    OMARCHY_PACMAN_CONF="$pacman_conf" \
    OMARCHY_ASAHI_PACKAGE_KEY_FILE="$key_file" \
    OMARCHY_TEST_CALLS="$calls" \
    OMARCHY_TEST_KEY_STATE="$key_state" \
    OMARCHY_TEST_APPLE="${1:-0}" \
    PATH="$mock_bin:$PATH" \
    bash -euo pipefail -c 'source "$1"' _ "$leaf"
}

run_leaf 0
[[ $(grep -Fc '[omarchy]' "$pacman_conf") == 1 ]] || fail "Apple package setup writes one repository block"
grep -Fxq 'SigLevel = Required DatabaseOptional' "$pacman_conf" || fail "Apple package setup requires signed packages"
grep -Fxq 'Server = https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-packages-784daa3efaecfa81b5b4da888b524e6ec4574d24' "$pacman_conf" || fail "Apple package setup uses the immutable release"
grep -Fq 'asahi-alarm/asahi-alarm' "$pacman_conf" || fail "Apple package setup preserves the Asahi repository"
grep -Fq 'mirror.archlinuxarm.org' "$pacman_conf" || fail "Apple package setup preserves ALARM repositories"
! grep -Fq 'pkgs.omarchy.org' "$pacman_conf" || fail "Apple package setup removes the unavailable upstream ARM repository"
grep -Fxq "pacman-key:--add $key_file" "$calls" || fail "Apple package setup imports the pinned release key"
grep -Fxq 'pacman-key:--lsign-key 5983B1CA32CB778F4D74D24ECFF35022CA5B5959' "$calls" || fail "Apple package setup trusts the pinned release key"
grep -Fxq 'pacman:-Sy --noconfirm' "$calls" || fail "Apple package setup refreshes the new repository"
[[ ! -e $db_path/sync/omarchy.db && ! -e $db_path/sync/omarchy.db.sig ]] ||
  fail "Apple package setup keeps a database cached under the old pin"
pass "Apple Silicon receives the signed immutable package repository"

# The cached database is dropped only when the repository is actually repointed;
# an unchanged pin leaves the cache alone.
printf 'fresh-database' >"$db_path/sync/omarchy.db"
run_leaf 0
[[ -e $db_path/sync/omarchy.db ]] ||
  fail "Apple package setup clears the database cache when nothing changed"
pass "the database cache is cleared only on a repointed repository"

config_hash=$(sha256sum "$pacman_conf")
sync_count=$(grep -Fc 'pacman:-Sy --noconfirm' "$calls")
run_leaf 0
[[ $(sha256sum "$pacman_conf") == "$config_hash" ]] || fail "Apple package setup is idempotent"
[[ $(grep -Fc 'pacman:-Sy --noconfirm' "$calls") == "$sync_count" ]] || fail "Apple package setup does not resync an unchanged repository"
pass "Apple package repository setup is idempotent"

non_apple_conf="$test_tmp/non-apple.conf"
cp "$pacman_conf" "$non_apple_conf"
non_apple_hash=$(sha256sum "$non_apple_conf")
OMARCHY_PACMAN_CONF="$non_apple_conf" OMARCHY_TEST_APPLE=1 PATH="$mock_bin:$PATH" \
  bash -euo pipefail -c 'source "$1"' _ "$leaf"
[[ $(sha256sum "$non_apple_conf") == "$non_apple_hash" ]] || fail "package setup leaves non-Apple systems unchanged"
pass "Apple package repository remains hardware-scoped"

cat >"$pacman_conf" <<'CONF'
[options]
Architecture = aarch64

[omarchy]
SigLevel = Never
Server = https://pkgs.omarchy.org/edge/$arch
CONF
rm -f "$key_state"
: >"$calls"
OMARCHY_PATH="$ROOT" \
  OMARCHY_PACMAN_CONF="$pacman_conf" \
  OMARCHY_ASAHI_PACKAGE_KEY_FILE="$key_file" \
  OMARCHY_TEST_CALLS="$calls" \
  OMARCHY_TEST_KEY_STATE="$key_state" \
  OMARCHY_TEST_APPLE=0 \
  PATH="$mock_bin:$PATH" \
  bash -euo pipefail "$migration" >/dev/null
grep -Fq 'sudo:env OMARCHY_PATH=' "$calls" || fail "Apple package migration delegates privileged setup through sudo"
grep -Fxq 'SigLevel = Required DatabaseOptional' "$pacman_conf" || fail "Apple package migration configures the signed repository"
grep -Fxq "pacman-key:--add $key_file" "$calls" || fail "Apple package migration imports the release key"
pass "existing Apple Silicon installs receive the signed package repository"

config_hash=$(sha256sum "$pacman_conf")
OMARCHY_PATH="$ROOT" OMARCHY_TEST_APPLE=1 PATH="$mock_bin:$PATH" \
  bash -euo pipefail "$migration" >/dev/null
[[ $(sha256sum "$pacman_conf") == "$config_hash" ]] || fail "Apple package migration leaves non-Apple systems unchanged"
pass "Apple package migration remains hardware-scoped"

# --- Install-time pin shapes -------------------------------------------------
# The migration and the fresh installer share this writer, so a Mac the package
# channel already moved forward must keep its pin instead of being repointed
# back at the bootstrap release.

bootstrap_tag=asahi-packages-784daa3efaecfa81b5b4da888b524e6ec4574d24
bootstrap_server="https://github.com/maralcbr/omarchy-pkgs/releases/download/$bootstrap_tag"
stable_server="https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-packages-stable-437d2aed1c3b5f7a9e0d2c4b6a8e1f3d5c7b9a0e"
legacy_server="https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-packages-cf3de447a1b2c3d4e5f60718293a4b5c6d7e8f90"

grep -Fxq "  bootstrap_release_tag=$bootstrap_tag" "$leaf" || fail "the bootstrap package release is a single named constant"
[[ $bootstrap_tag =~ ^asahi-packages-[0-9a-f]{40}$ ]] || fail "the bootstrap package release names an immutable commit"
pass "the install-time pin names one immutable bootstrap release"

write_conf() {
  {
    printf '[options]\nArchitecture = aarch64\nDBPath = %s\n\n' "$db_path"
    printf '[asahi-alarm]\nServer = https://github.com/asahi-alarm/asahi-alarm/releases/download/$arch\n\n'
    printf '%s\n' "$1"
    printf '\n[core]\nServer = http://mirror.archlinuxarm.org/$arch/$repo\n'
  } >"$pacman_conf"
}

omarchy_server() {
  awk '
    /^[[:space:]]*\[omarchy\][[:space:]]*$/ { inside = 1; next }
    inside && /^[[:space:]]*\[[^]]+\][[:space:]]*$/ { inside = 0 }
    inside && /^[[:space:]]*Server[[:space:]]*=/ { sub(/^[[:space:]]*Server[[:space:]]*=[[:space:]]*/, ""); print }
  ' "$pacman_conf"
}

seed_cache() {
  mkdir -p "$db_path/sync"
  printf 'cached-database' >"$db_path/sync/omarchy.db"
  printf 'cached-signature' >"$db_path/sync/omarchy.db.sig"
}

write_conf "$(printf '[omarchy]\nSigLevel = Required DatabaseOptional\nServer = %s' "$stable_server")"
rm -f "$key_state"
: >"$calls"
seed_cache
run_leaf 0
[[ $(omarchy_server) == "$stable_server" ]] || fail "a promoted stable snapshot survives the install-time writer"
[[ -e $db_path/sync/omarchy.db ]] || fail "an unchanged stable pin keeps its cached database"
grep -Fxq 'pacman-key:--lsign-key 5983B1CA32CB778F4D74D24ECFF35022CA5B5959' "$calls" || fail "a preserved stable pin still trusts the release key"
pass "a recognised stable snapshot is preserved"

write_conf "$(printf '[omarchy]\nSigLevel = Required DatabaseOptional\nServer = %s' "$legacy_server")"
: >"$calls"
run_leaf 0
[[ $(omarchy_server) == "$legacy_server" ]] || fail "a recognised legacy pin survives the install-time writer"
pass "a recognised legacy snapshot is preserved"

write_conf "$(printf '[omarchy]\nSigLevel = Never\nServer = %s\nServer = %s' "$stable_server" "$stable_server")"
: >"$calls"
seed_cache
run_leaf 0
[[ $(omarchy_server | wc -l) == 1 ]] || fail "byte-identical Servers are collapsed into one"
[[ $(omarchy_server) == "$stable_server" ]] || fail "collapsing identical Servers keeps the recognised pin"
grep -Fxq 'SigLevel = Required DatabaseOptional' "$pacman_conf" || fail "collapsing identical Servers repairs the signature policy"
[[ -e $db_path/sync/omarchy.db ]] || fail "repairing the section without moving the Server keeps the cached database"
pass "byte-identical duplicate Servers are deduplicated without repointing"

write_conf "$(printf '[omarchy]\nSigLevel = Required DatabaseOptional\nServer = %s\nServer = %s' "$stable_server" "$legacy_server")"
config_hash=$(sha256sum "$pacman_conf")
: >"$calls"
if run_leaf 0 2>"$test_tmp/conflict.err"; then
  fail "conflicting [omarchy] Servers are refused"
fi
grep -Fq 'Several [omarchy] Servers' "$test_tmp/conflict.err" || fail "a conflicting Server list is named in the refusal"
[[ $(sha256sum "$pacman_conf") == "$config_hash" ]] || fail "conflicting Servers are refused without mutating pacman.conf"
! grep -Fq 'pacman:-Sy --noconfirm' "$calls" || fail "conflicting Servers are refused before any repository sync"
! grep -q '^pacman-key:' "$calls" ||
  fail "a refused repository changes the keyring"
pass "conflicting [omarchy] Servers are refused without mutation"

write_conf "$(printf '[omarchy]\nSigLevel = Required DatabaseOptional\nServer = %s\n\n[omarchy]\nSigLevel = Never\nServer = %s' "$stable_server" "$legacy_server")"
config_hash=$(sha256sum "$pacman_conf")
: >"$calls"
if run_leaf 0 2>"$test_tmp/duplicate.err"; then
  fail "duplicate [omarchy] sections are refused"
fi
grep -Fq 'Several [omarchy] sections' "$test_tmp/duplicate.err" || fail "duplicate sections are named in the refusal"
[[ $(sha256sum "$pacman_conf") == "$config_hash" ]] || fail "duplicate sections are refused without mutating pacman.conf"
pass "duplicate [omarchy] sections are refused without mutation"

write_conf "$(printf '[omarchy]\nSigLevel = Never\nServer = https://pkgs.omarchy.org/edge/$arch')"
: >"$calls"
seed_cache
run_leaf 0
[[ $(omarchy_server) == "$bootstrap_server" ]] || fail "an unrecognised Server is replaced with the bootstrap release"
[[ ! -e $db_path/sync/omarchy.db ]] || fail "repointing the repository drops the cached database"
pass "an unrecognised Server is replaced with the bootstrap release"

write_conf "$(printf '[core-testing]\nServer = http://example.invalid/$repo')"
: >"$calls"
run_leaf 0
[[ $(omarchy_server) == "$bootstrap_server" ]] || fail "a missing section is written with the bootstrap release"
grep -Fxq "pacman-key:--lsign-key 5983B1CA32CB778F4D74D24ECFF35022CA5B5959" "$calls" || fail "writing the section trusts the release key"
pass "a missing [omarchy] section is written with the bootstrap release"

write_conf "$(printf '[omarchy]\nSigLevel = Never\nServer = %s' "$stable_server")"
: >"$calls"
seed_cache
run_leaf 0
grep -Fxq 'SigLevel = Required DatabaseOptional' "$pacman_conf" || fail "a wrong SigLevel is repaired"
[[ $(omarchy_server) == "$stable_server" ]] || fail "repairing the SigLevel leaves the recognised Server alone"
[[ -e $db_path/sync/omarchy.db ]] || fail "repairing the SigLevel alone keeps the cached database"
pass "a wrong SigLevel is repaired without repointing the repository"

# The migration reruns this writer on every Mac, including ones the package
# channel already moved onto a promoted stable snapshot.
write_conf "$(printf '[omarchy]\nSigLevel = Required DatabaseOptional\nServer = %s' "$stable_server")"
config_hash=$(sha256sum "$pacman_conf")
: >"$calls"
OMARCHY_PATH="$ROOT" \
  OMARCHY_PACMAN_CONF="$pacman_conf" \
  OMARCHY_ASAHI_PACKAGE_KEY_FILE="$key_file" \
  OMARCHY_TEST_CALLS="$calls" \
  OMARCHY_TEST_KEY_STATE="$key_state" \
  OMARCHY_TEST_APPLE=0 \
  PATH="$mock_bin:$PATH" \
  bash -euo pipefail "$migration" >/dev/null
[[ $(sha256sum "$pacman_conf") == "$config_hash" ]] || fail "the migration leaves a channel-selected set alone"
! grep -Fq 'pacman:-Sy --noconfirm' "$calls" || fail "the migration does not resync a channel-selected set"
pass "the migration is idempotent for a Mac already on a channel-selected set"
