#!/bin/bash

# Retiring the omarchy-mac [omarchy-aarch64] repository (issue #238): the
# pacman.conf section, the packages that conflict with [omarchy], and the
# bundle packages that repository built newer than the signed bundle.

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command bsdtar
require_command vercmp

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

command="$ROOT/bin/omarchy-update-asahi-legacy-repository"
bundle="$ROOT/bin/omarchy-update-asahi-bundle"
migration=$(grep -l 'omarchy-update-asahi-legacy-repository' "$ROOT"/migrations/*.sh | grep -v '/1788486400.sh$' || true)
[[ $(wc -l <<<"$migration") == 1 && -f $migration ]] || fail "one migration retires the legacy repository" "$migration"
migration_name=$(basename "$migration")

mock_bin="$test_tmp/bin"
state="$test_tmp/pacman-state"
fs="$test_tmp/fs"
calls="$test_tmp/calls"
db_path="$test_tmp/pacman-db"
pacman_conf="$test_tmp/pacman.conf"
backups="$test_tmp/backups"
retired="$test_tmp/retired"
key_file="$test_tmp/omarchy-release.gpg"
mkdir -p "$mock_bin" "$state"/{installed,files,available,conflicts} "$fs" "$db_path/sync"
: >"$key_file"

cat >"$mock_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
exit "${TEST_APPLE:-0}"
SH
cat >"$mock_bin/gpg" <<'SH'
#!/bin/bash
printf '%s\n' 'pub:-:255:22:CFF35022CA5B5959:0:0::-:::scESC:::::ed25519:::0:'
printf '%s\n' 'fpr:::::::::5983B1CA32CB778F4D74D24ECFF35022CA5B5959:'
SH
cat >"$mock_bin/pacman-key" <<'SH'
#!/bin/bash
printf 'pacman-key %s\n' "$*" >>"$TEST_CALLS"
[[ $1 != "--finger" ]]
SH
cat >"$mock_bin/lspci" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$mock_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$TEST_CALLS"
[[ ${TEST_RM_FAIL:-0} != 1 || $1 != rm ]] || exit 1
"$@"
SH

# A small pacman over $TEST_STATE: installed/<pkg> holds a version,
# files/<pkg> the paths it owns, available/<pkg> the paths a repository
# package would install, conflicts/<pkg> the names it declares conflicts with.
# A sync transaction removes conflicting packages only when --ask 4 accepts
# it, and fails on a file another package owns unless --overwrite matches it,
# the way pacman does.
cat >"$mock_bin/pacman" <<'SH'
#!/bin/bash
printf 'pacman %s\n' "$*" >>"$TEST_CALLS"
s=$TEST_STATE
owner() {
  local file=$1 pkg found=1
  for pkg in "$s"/files/*; do
    [[ -e $pkg ]] || continue
    grep -Fxq -- "$file" "$pkg" && { basename "$pkg"; found=0; }
  done
  return "$found"
}
conflicts() { [[ -f $s/conflicts/$1 ]] && grep -Fxq -- "$2" "$s/conflicts/$1"; }
case "$1" in
  -Q) [[ -f $s/installed/$2 ]] && echo "$2 $(cat "$s/installed/$2")" ;;
  -Qq) [[ -f $s/installed/$2 ]] && echo "$2" ;;
  -Si) [[ -f $s/available/$2 ]] ;;
  -Qlq) cat "$s/files/$2" ;;
  -Qoq) owner "$2" ;;
  -Sy)
    # A partial sync: the new [omarchy] database arrives, another fails.
    (( ${TEST_SY_STATUS:-0} == 0 )) || printf 'new-server-database\n' >"$TEST_DB_PATH/sync/omarchy.db"
    exit "${TEST_SY_STATUS:-0}"
    ;;
  -Ql)
    [[ ${TEST_QL_FAIL:-0} != 1 ]] || exit 1
    for pkg in "$s"/files/*; do
      [[ -e $pkg ]] || continue
      while IFS= read -r file; do echo "$(basename "$pkg") $file"; done <"$pkg"
    done
    ;;
  -S)
    shift
    ask=0 patterns=() target=""
    while (($#)); do
      case "$1" in
        --ask) ask=$2; shift 2 ;;
        --overwrite) patterns+=("$2"); shift 2 ;;
        --noconfirm|--needed) shift ;;
        *) target=$1; shift ;;
      esac
    done
    [[ -f $s/available/$target ]] || { echo "error: target not found: $target" >&2; exit 1; }
    remove=()
    for pkg in "$s"/installed/*; do
      [[ -e $pkg ]] || continue
      pkg=$(basename "$pkg")
      [[ $pkg != "$target" ]] || continue
      if conflicts "$pkg" "$target" || conflicts "$target" "$pkg"; then
        (( ask == 4 )) || { echo "error: unresolvable package conflicts detected" >&2; exit 1; }
        remove+=("$pkg")
      fi
    done
    while IFS= read -r file; do
      holder=$(owner "$file" | head -1) || continue
      [[ -n $holder ]] || continue
      [[ $holder != "$target" ]] || continue
      [[ " ${remove[*]} " != *" $holder "* ]] || continue
      matched=0
      for pattern in "${patterns[@]}"; do
        # shellcheck disable=SC2053
        [[ $file == $pattern ]] && matched=1
      done
      (( matched )) || { echo "error: $file exists in filesystem (owned by $holder)" >&2; exit 1; }
    done <"$s/available/$target"
    for pkg in "${remove[@]}"; do
      while IFS= read -r file; do rm -f -- "$file"; done <"$s/files/$pkg"
      rm -f "$s/installed/$pkg" "$s/files/$pkg"
    done
    while IFS= read -r file; do
      mkdir -p "$(dirname "$file")"
      echo "$target" >"$file"
    done <"$s/available/$target"
    echo 1-1 >"$s/installed/$target"
    cp "$s/available/$target" "$s/files/$target"
    ;;
  -Rdd)
    [[ $2 == "--dbonly" ]] || { echo "unexpected removal" >&2; exit 1; }
    rm -f "$s/installed/$4" "$s/files/$4"
    ;;
  *) echo "unexpected pacman $*" >&2; exit 1 ;;
esac
SH
chmod +x "$mock_bin"/*

bootstrap_server="https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-packages-784daa3efaecfa81b5b4da888b524e6ec4574d24"
stable_server="https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-packages-stable-0123456789abcdef0123456789abcdef01234567"

run_command() {
  TEST_APPLE="${TEST_APPLE:-0}" \
    TEST_CALLS="$calls" \
    TEST_STATE="$state" \
    TEST_RM_FAIL="${TEST_RM_FAIL:-0}" \
    TEST_SY_STATUS="${TEST_SY_STATUS:-0}" \
    TEST_QL_FAIL="${TEST_QL_FAIL:-0}" \
    TEST_DB_PATH="$db_path" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_PACMAN_CONF="$pacman_conf" \
    OMARCHY_ASAHI_PACKAGE_KEY_FILE="$key_file" \
    OMARCHY_BACKUP_DIR="$backups" \
    OMARCHY_RETIRED_REPOSITORY_DIR="$retired" \
    PATH="$mock_bin:$PATH" \
    bash "$command" >"$test_tmp/out" 2>"$test_tmp/err"
}

repository_order() {
  awk '/^[[:space:]]*\[[^]]+\][[:space:]]*$/ { gsub(/[][[:space:]]/, ""); printf "%s ", $0 }' "$pacman_conf"
}

omarchy_server() {
  awk '/^\[omarchy\]$/ { inside = 1; next } /^\[/ { inside = 0 } inside && /^Server = / { sub(/^Server = /, ""); print }' "$pacman_conf"
}

alarm_repositories() {
  printf '[asahi-alarm]\nInclude = /etc/pacman.d/mirrorlist.asahi-alarm\n\n'
  printf '[core]\nInclude = /etc/pacman.d/mirrorlist\n\n'
  printf '[extra]\nInclude = /etc/pacman.d/mirrorlist\n\n'
  printf '[alarm]\nInclude = /etc/pacman.d/mirrorlist\n\n'
  printf '[aur]\nInclude = /etc/pacman.d/mirrorlist\n'
}

legacy_section() {
  printf '[omarchy-aarch64]\nSigLevel = Optional TrustAll\nServer = https://github.com/omarchy-mac/omarchy-pkgs-aarch64/releases/download/%s\n\n' "$1"
}

reset() {
  rm -rf "$backups" "$retired" "$fs" "$state"
  mkdir -p "$state"/{installed,files,available,conflicts} "$fs"
  : >"$calls"
  printf 'omarchy-aarch64 sync database\n' >"$db_path/sync/omarchy-aarch64.db"
}

# omarchy-mac's edge layout: upstream edge [omarchy] for explicit Hyprland
# targets only, then the community repository.
reset
{
  printf '[options]\nArchitecture = aarch64\nDBPath = %s\n\n' "$db_path"
  printf '# Mac-specific packages remain in the community ARM repository.\n'
  printf '[omarchy]\nUsage = Sync\nSigLevel = Required DatabaseOptional\nServer = https://pkgs.omarchy.org/edge/$arch\n\n'
  legacy_section edge
  alarm_repositories
} >"$pacman_conf"
original=$(cat "$pacman_conf")
TEST_APPLE=0 run_command || fail "the cleanup of a legacy section fails" "$(cat "$test_tmp/err")"
! grep -q 'omarchy-aarch64' "$pacman_conf" || fail "the legacy section is removed" "$(cat "$pacman_conf")"
[[ $(repository_order) == "options omarchy asahi-alarm core extra alarm aur " ]] ||
  fail "[omarchy] leads the repositories once the legacy section is gone" "$(repository_order)"
[[ $(omarchy_server) == "$bootstrap_server" ]] && ! grep -q '^Usage' "$pacman_conf" ||
  fail "the upstream edge [omarchy] becomes the signed Omarchy repository" "$(cat "$pacman_conf")"
[[ $(cat "$pacman_conf") != *$'\n\n\n'* ]] || fail "the removed section leaves no run of blank lines" "$(cat "$pacman_conf")"
backup=$(find "$backups" -name 'pacman.conf-omarchy-aarch64-*' -print)
[[ -n $backup && $(cat "$backup") == "$original" ]] || fail "pacman.conf is backed up before the section goes"
cmp -s "$retired/omarchy-aarch64.db" "$db_path/sync/omarchy-aarch64.db" ||
  fail "the retired repository's sync database is kept for the bundle"
grep -Fxq 'pacman -Sy --noconfirm' "$calls" || fail "the repositories are synced after the section goes"
grep -Fq 'Removed the retired [omarchy-aarch64] repository' "$test_tmp/out" || fail "the removal is reported" "$(cat "$test_tmp/out")"
pass "a legacy section after [omarchy] is removed with a backup and [omarchy] stays first"

config_hash=$(sha256sum "$pacman_conf")
: >"$calls"
TEST_APPLE=0 run_command || fail "a rerun fails" "$(cat "$test_tmp/err")"
[[ $(sha256sum "$pacman_conf") == "$config_hash" ]] && ! grep -Eq '^(sudo|pacman-key|pacman -S)' "$calls" ||
  fail "a rerun changes nothing" "$(cat "$calls")"
[[ $(find "$backups" -name 'pacman.conf-omarchy-aarch64-*' | wc -l) == 1 ]] || fail "a rerun backs up again"
pass "a rerun after the cleanup changes nothing"

# omarchy-mac's stable layout before 2026-09-05 listed the community
# repository first; a Mac that later gained [omarchy] below it had its signed
# packages shadowed.
reset
{
  printf '[options]\nArchitecture = aarch64\nDBPath = %s\n\n' "$db_path"
  legacy_section stable
  printf '[asahi-alarm]\nInclude = /etc/pacman.d/mirrorlist.asahi-alarm\n\n'
  printf '[omarchy]\nSigLevel = Required DatabaseOptional\nServer = %s\n\n' "$stable_server"
  printf '[core]\nInclude = /etc/pacman.d/mirrorlist\n\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n\n'
  printf '[alarm]\nInclude = /etc/pacman.d/mirrorlist\n\n[aur]\nInclude = /etc/pacman.d/mirrorlist\n'
} >"$pacman_conf"
TEST_APPLE=0 run_command || fail "the cleanup of a leading legacy section fails" "$(cat "$test_tmp/err")"
[[ $(repository_order) == "options omarchy asahi-alarm core extra alarm aur " ]] ||
  fail "[omarchy] takes the place of a legacy section that stood ahead of it" "$(cat "$pacman_conf")"
[[ $(omarchy_server) == "$stable_server" && $(grep -c '^\[omarchy\]$' "$pacman_conf") == 1 ]] ||
  fail "a recognised [omarchy] Server moves with its section" "$(cat "$pacman_conf")"
pass "a legacy section ahead of [omarchy] hands its place to [omarchy]"

reset
{
  printf '[options]\nArchitecture = aarch64\nDBPath = %s\n\n' "$db_path"
  legacy_section stable
  alarm_repositories
} >"$pacman_conf"
TEST_APPLE=0 run_command || fail "the cleanup of a Mac without [omarchy] fails" "$(cat "$test_tmp/err")"
[[ $(repository_order) == "options omarchy asahi-alarm core extra alarm aur " && $(omarchy_server) == "$bootstrap_server" ]] ||
  fail "a Mac with only the legacy repository gets [omarchy] first" "$(cat "$pacman_conf")"
pass "a Mac with only the legacy repository gets the signed [omarchy] first"

# Several [omarchy] sections are refused by install/hardware/pacman.sh before
# anything changes; the cleanup reports it and leaves pacman.conf alone.
reset
{
  printf '[options]\nDBPath = %s\n\n' "$db_path"
  printf '[omarchy]\nServer = %s\n\n' "$stable_server"
  legacy_section edge
  printf '[omarchy]\nServer = %s\n\n' "$stable_server"
  alarm_repositories
} >"$pacman_conf"
config_hash=$(sha256sum "$pacman_conf")
set +e
TEST_APPLE=0 run_command
status=$?
set -e
(( status == 1 )) || fail "a refused repository cleanup reports success"
[[ $(sha256sum "$pacman_conf") == "$config_hash" && ! -d $backups ]] || fail "a refused repository cleanup changes pacman.conf"
grep -Fq 'Could not remove [omarchy-aarch64]' "$test_tmp/err" || fail "a refused repository cleanup is not explained"
pass "a repository cleanup that cannot run leaves pacman.conf untouched and says so"

reset
{ printf '[options]\nDBPath = %s\n\n' "$db_path"; legacy_section stable; alarm_repositories; } >"$pacman_conf"
original=$(cat "$pacman_conf")
set +e
TEST_APPLE=0 TEST_SY_STATUS=1 run_command
status=$?
set -e
(( status == 1 )) && [[ $(cat "$pacman_conf") == "$original" ]] ||
  fail "a sync failure after the rewrite leaves the legacy section gone" "$(cat "$pacman_conf")"
grep -Fq 'restored' "$test_tmp/err" || fail "a restored pacman.conf is not reported"
[[ ! -e $db_path/sync/omarchy.db ]] || fail "a restored pacman.conf keeps the new Server's cached database"
TEST_APPLE=0 run_command || fail "the cleanup is not retried after a sync failure" "$(cat "$test_tmp/err")"
! grep -q 'omarchy-aarch64' "$pacman_conf" || fail "the retried cleanup keeps the legacy section"
pass "a sync failure restores the legacy section so the next run retries the cleanup"

# The two conflicting packages. obsidian-appimage declares its conflict with
# obsidian; the AUR hyprland-preview-share-picker-git declares none and shares
# the binary path with the [omarchy] package.
package() {
  local kind=$1 name=$2
  shift 2
  printf '%s\n' "$@" >"$state/$kind/$name"
}
install_package() {
  local name=$1 file
  shift
  echo 9-1 >"$state/installed/$name"
  package files "$name" "$@"
  for file in "$@"; do
    mkdir -p "$(dirname "$file")"
    echo "$name" >"$file"
  done
}
legacy_mac_packages() {
  install_package obsidian-appimage "$fs/usr/bin/obsidian" "$fs/opt/obsidian-appimage/Obsidian.AppImage"
  package conflicts obsidian-appimage obsidian
  install_package hyprland-preview-share-picker-git "$fs/usr/bin/hyprland-preview-share-picker" \
    "$fs/usr/share/licenses/hyprland-preview-share-picker-git/LICENSE"
  printf '%s\n' "$fs/usr/share/licenses/" "$fs/usr/share/licenses/hyprland-preview-share-picker-git/" \
    >>"$state/files/hyprland-preview-share-picker-git"
  package available obsidian "$fs/usr/bin/obsidian" "$fs/usr/lib/obsidian/app.asar"
  package available hyprland-preview-share-picker "$fs/usr/bin/hyprland-preview-share-picker" \
    "$fs/usr/share/licenses/hyprland-preview-share-picker/LICENSE"
}

reset
{ printf '[options]\nDBPath = %s\n\n' "$db_path"; printf '[omarchy]\nSigLevel = Required DatabaseOptional\nServer = %s\n\n' "$stable_server"; alarm_repositories; } >"$pacman_conf"
legacy_mac_packages
TEST_APPLE=0 run_command || fail "replacing the legacy packages fails" "$(cat "$test_tmp/err")"
[[ -f $state/installed/obsidian && ! -f $state/installed/obsidian-appimage ]] ||
  fail "obsidian-appimage is replaced by obsidian"
[[ ! -e $fs/opt/obsidian-appimage/Obsidian.AppImage && $(cat "$fs/usr/bin/obsidian") == obsidian ]] ||
  fail "obsidian-appimage's files are gone and obsidian owns its binary"
[[ -f $state/installed/hyprland-preview-share-picker && ! -f $state/installed/hyprland-preview-share-picker-git ]] ||
  fail "hyprland-preview-share-picker-git is replaced by hyprland-preview-share-picker"
[[ $(cat "$fs/usr/bin/hyprland-preview-share-picker" 2>/dev/null) == hyprland-preview-share-picker ]] ||
  fail "the shared picker binary survives the legacy package's removal"
[[ ! -e $fs/usr/share/licenses/hyprland-preview-share-picker-git ]] ||
  fail "a file or directory only the legacy picker owned is left behind"
[[ -d $fs/usr/share/licenses/hyprland-preview-share-picker ]] || fail "a directory the replacement uses is removed"
[[ $(grep -c '^pacman -S ' "$calls") == 2 ]] || fail "each replacement is one install transaction" "$(cat "$calls")"
grep -Fxq 'pacman -Rdd --dbonly --noconfirm hyprland-preview-share-picker-git' "$calls" ||
  fail "the -git picker leaves the package database without deleting the shared files"
! grep -q 'Rdd.*obsidian-appimage' "$calls" || fail "obsidian-appimage is removed outside its conflict transaction"
grep -q -- '--ask 4 --overwrite' "$calls" || fail "the install accepts the declared conflict and takes over shared files"
pass "both legacy conflict pairs are replaced by their [omarchy] packages"

: >"$calls"
config_hash=$(sha256sum "$pacman_conf")
TEST_APPLE=0 run_command || fail "a rerun after the replacements fails" "$(cat "$test_tmp/err")"
! grep -Eq '^pacman -(S|Rdd) ' "$calls" && [[ $(sha256sum "$pacman_conf") == "$config_hash" ]] ||
  fail "a rerun after the replacements changes something" "$(cat "$calls")"
pass "a rerun after the replacements does nothing"

reset
{ printf '[options]\nDBPath = %s\n\n' "$db_path"; alarm_repositories; } >"$pacman_conf"
install_package hyprland-preview-share-picker-git "$fs/usr/bin/hyprland-preview-share-picker"
TEST_APPLE=0 run_command || fail "an unavailable replacement fails the cleanup" "$(cat "$test_tmp/err")"
[[ -f $state/installed/hyprland-preview-share-picker-git ]] && ! grep -q '^pacman -S ' "$calls" ||
  fail "a legacy package without an available replacement is removed"
grep -Fq 'hyprland-preview-share-picker is not in the configured repositories; keeping hyprland-preview-share-picker-git' "$test_tmp/out" ||
  fail "an unavailable replacement is not reported"
pass "a legacy package is kept when its replacement is unavailable"

reset
{ printf '[options]\nDBPath = %s\n\n' "$db_path"; printf '[omarchy]\nServer = %s\n\n' "$stable_server"; alarm_repositories; } >"$pacman_conf"
install_package obsidian-appimage "$fs/usr/bin/obsidian"
package available obsidian "$fs/usr/bin/obsidian"
rm -f "$mock_bin/pacman.real"
cp "$mock_bin/pacman" "$mock_bin/pacman.real"
cat >"$mock_bin/pacman" <<'SH'
#!/bin/bash
[[ $1 != "-S" ]] || { printf 'pacman %s\n' "$*" >>"$TEST_CALLS"; exit 1; }
exec "${0%/*}/pacman.real" "$@"
SH
chmod +x "$mock_bin/pacman"
set +e
TEST_APPLE=0 run_command
status=$?
set -e
mv "$mock_bin/pacman.real" "$mock_bin/pacman"
(( status == 1 )) && [[ -f $state/installed/obsidian-appimage && -e $fs/usr/bin/obsidian ]] ||
  fail "a failed replacement leaves the legacy package in place and reports it"
grep -Fq 'Could not install obsidian; obsidian-appimage stays installed.' "$test_tmp/err" || fail "a failed replacement is not explained"
pass "a failed replacement keeps the legacy package and reports the failure"

# Removing a file only the legacy package owned fails: the package stays
# recorded, so the next run finds it and finishes.
reset
{ printf '[options]\nDBPath = %s\n\n' "$db_path"; alarm_repositories; } >"$pacman_conf"
legacy_mac_packages
set +e
TEST_APPLE=0 TEST_RM_FAIL=1 run_command
status=$?
set -e
(( status == 1 )) && [[ -f $state/installed/hyprland-preview-share-picker-git && -f $state/installed/hyprland-preview-share-picker ]] ||
  fail "a failed leftover removal drops the legacy package record"
grep -Fq 'hyprland-preview-share-picker-git could not be removed; the next run tries again' "$test_tmp/err" ||
  fail "a failed leftover removal is not explained"
TEST_APPLE=0 run_command || fail "the leftover removal is not retried" "$(cat "$test_tmp/err")"
[[ ! -f $state/installed/hyprland-preview-share-picker-git && ! -e $fs/usr/share/licenses/hyprland-preview-share-picker-git ]] &&
  [[ $(cat "$fs/usr/bin/hyprland-preview-share-picker") == hyprland-preview-share-picker ]] ||
  fail "the retried leftover removal does not finish"
pass "a failed leftover removal keeps the legacy package so the next run finishes it"

# pacman -Qo names only the first owner. A file the legacy picker shares with
# a package that sorts after it must survive.
reset
{ printf '[options]\nDBPath = %s\n\n' "$db_path"; alarm_repositories; } >"$pacman_conf"
legacy_mac_packages
install_package z-shared-license-owner "$fs/usr/share/licenses/hyprland-preview-share-picker-git/LICENSE"
TEST_APPLE=0 run_command || fail "a legacy file shared with another package fails the cleanup" "$(cat "$test_tmp/err")"
[[ -e $fs/usr/share/licenses/hyprland-preview-share-picker-git/LICENSE && ! -f $state/installed/hyprland-preview-share-picker-git ]] ||
  fail "a legacy file another package also owns is deleted"
pass "a legacy file another package also owns is kept"

reset
{ printf '[options]\nDBPath = %s\n\n' "$db_path"; alarm_repositories; } >"$pacman_conf"
legacy_mac_packages
set +e
TEST_APPLE=0 TEST_QL_FAIL=1 run_command
status=$?
set -e
(( status == 1 )) && [[ -f $state/installed/hyprland-preview-share-picker-git && -e $fs/usr/share/licenses/hyprland-preview-share-picker-git/LICENSE ]] ||
  fail "an ownership query that fails drops the legacy package record"
pass "an ownership query that fails keeps the legacy package for the next run"

# A Mac that never had the legacy repository, and a machine that is not a Mac.
reset
{ printf '[options]\nDBPath = %s\n\n' "$db_path"; printf '[omarchy]\nSigLevel = Required DatabaseOptional\nServer = %s\n\n' "$stable_server"; alarm_repositories; } >"$pacman_conf"
install_package obsidian "$fs/usr/bin/obsidian"
package available obsidian "$fs/usr/bin/obsidian"
config_hash=$(sha256sum "$pacman_conf")
TEST_APPLE=0 run_command || fail "a Mac without legacy state fails the cleanup" "$(cat "$test_tmp/err")"
[[ $(sha256sum "$pacman_conf") == "$config_hash" && ! -d $backups ]] && ! grep -q '^sudo ' "$calls" &&
  [[ ! -s $test_tmp/out ]] || fail "a Mac without legacy state is changed" "$(cat "$calls")"
pass "a Mac without the legacy repository or packages is left untouched"

reset
{ printf '[options]\n\n'; legacy_section edge; alarm_repositories; } >"$pacman_conf"
install_package obsidian-appimage "$fs/usr/bin/obsidian"
package available obsidian "$fs/usr/bin/obsidian"
config_hash=$(sha256sum "$pacman_conf")
TEST_APPLE=1 run_command || fail "the cleanup fails on a machine that is not a Mac"
[[ $(sha256sum "$pacman_conf") == "$config_hash" && ! -s $calls ]] || fail "the cleanup acts on a machine that is not a Mac"
pass "the cleanup does nothing on a machine that is not Apple Silicon"

# The migration runs the cleanup, is reviewed for Apple Silicon, and never
# stops later migrations; the default-package migration runs it first.
cat >"$test_tmp/cleanup-stub" <<'SH'
#!/bin/bash
echo cleanup >>"$TEST_CALLS"
exit "${TEST_CLEANUP_STATUS:-0}"
SH
mkdir -p "$test_tmp/migration-bin"
cp "$test_tmp/cleanup-stub" "$test_tmp/migration-bin/omarchy-update-asahi-legacy-repository"
cp "$mock_bin/omarchy-hw-apple-silicon" "$test_tmp/migration-bin/"
chmod +x "$test_tmp/migration-bin"/*
for status in 0 1; do
  : >"$calls"
  TEST_APPLE=0 TEST_CLEANUP_STATUS=$status TEST_CALLS="$calls" PATH="$test_tmp/migration-bin:$PATH" \
    bash -euo pipefail "$migration" >"$test_tmp/out" 2>"$test_tmp/err" ||
    fail "the migration stops later migrations when the cleanup returns $status"
  grep -Fxq cleanup "$calls" || fail "the migration does not run the cleanup"
done
grep -Fq 'the next omarchy update tries again' "$test_tmp/err" || fail "an unfinished migration cleanup is not explained"
: >"$calls"
TEST_APPLE=1 TEST_CALLS="$calls" PATH="$test_tmp/migration-bin:$PATH" bash -euo pipefail "$migration" >/dev/null
[[ ! -s $calls ]] || fail "the migration runs off Apple Silicon"
[[ $(stat -c '%a' "$migration") == 644 ]] && ! head -1 "$migration" | grep -q '^#!' || fail "the migration follows the migration file format"
grep -Eq "^    $migration_name\) printf 'run\\\\t" "$ROOT/bin/omarchy-migrate" ||
  fail "the migration is reviewed to run on Apple Silicon"
parity="$ROOT/migrations/1788486400.sh"
cleanup_line=$(grep -n 'omarchy-update-asahi-legacy-repository' "$parity" | cut -d: -f1)
add_line=$(grep -n '^omarchy-pkg-add' "$parity" | cut -d: -f1)
[[ -n $cleanup_line && -n $add_line ]] && (( cleanup_line < add_line )) ||
  fail "the default-package migration replaces the legacy packages before installing obsidian and the picker"
printf '#!/bin/bash\necho "pkg-add $*" >>"$TEST_CALLS"\n' >"$test_tmp/migration-bin/omarchy-pkg-add"
chmod +x "$test_tmp/migration-bin/omarchy-pkg-add"
for status in 0 1; do
  : >"$calls"
  TEST_APPLE=0 TEST_CLEANUP_STATUS=$status TEST_CALLS="$calls" PATH="$test_tmp/migration-bin:$PATH" \
    bash -euo pipefail "$parity" >"$test_tmp/out" 2>"$test_tmp/err" ||
    fail "the default-package migration stops when the cleanup returns $status" "$(cat "$test_tmp/err")"
  [[ $(head -1 "$calls") == cleanup && $(sed -n 2p "$calls") == "pkg-add "*obsidian* ]] ||
    fail "the default-package migration does not clean up and then install (cleanup $status)" "$(cat "$calls")"
done
grep -Fq 'installing the default packages anyway' "$test_tmp/err" || fail "an unfinished cleanup in the default-package migration is not explained"
: >"$calls"
TEST_APPLE=1 TEST_CALLS="$calls" PATH="$test_tmp/migration-bin:$PATH" bash -euo pipefail "$parity" >/dev/null
[[ $(cat "$calls") == "pkg-add "* ]] || fail "the default-package migration runs the cleanup off Apple Silicon" "$(cat "$calls")"
pass "both migrations run the cleanup on Apple Silicon and carry on when it cannot finish"

# The bundle: a package the retired repository built newer than the signed
# bundle is downgraded; any other newer package is still refused.
root="$test_tmp/root"
assets="$test_tmp/assets"
bundle_bin="$test_tmp/bundle-bin"
source_commit=0123456789abcdef0123456789abcdef01234567
mkdir -p "$root/proc/device-tree" "$root/boot/grub" "$root/etc/NetworkManager/conf.d" "$assets" "$bundle_bin" \
  "$root/var/lib/pacman/sync" "$root/var/lib/pacman/local"
printf 'apple,j316s\0apple,arm-platform\0' >"$root/proc/device-tree/compatible"
: >"$root/boot/vmlinuz-linux-asahi"
: >"$root/boot/grub/grub.cfg"
printf 'wifi.backend=iwd\n' >"$root/etc/NetworkManager/conf.d/wifi.conf"
alarm_repositories >"$root/etc/pacman.conf"
: >"$test_tmp/release.gpg"
: >"$test_tmp/package.asc"

for stub in omarchy-hw-apple-silicon omarchy-cmd-present; do
  printf '#!/bin/bash\nexit 0\n' >"$bundle_bin/$stub"
done
printf '#!/bin/bash\necho linux-asahi\n' >"$bundle_bin/omarchy-hw-apple-kernel"
printf '#!/bin/bash\necho aarch64\n' >"$bundle_bin/uname"
printf '#!/bin/bash\nexit 1\n' >"$bundle_bin/gum"
cat >"$bundle_bin/curl" <<'SH'
#!/bin/bash
output="" url=""
while (($#)); do
  case "$1" in
    --output) output=$2; shift 2 ;;
    http*) url=$1; shift ;;
    *) shift ;;
  esac
done
cp "$TEST_ASSETS/${url##*/}" "$output"
SH
cat >"$bundle_bin/gpg" <<'SH'
#!/bin/bash
if [[ " $* " == *" --show-keys "* ]]; then
  if [[ $* == *package.asc* ]]; then
    echo 'fpr:::::::::C81AC3E2A99556F9B21D5FEA3DD49BC9F8360BDC:'
  else
    echo 'fpr:::::::::5983B1CA32CB778F4D74D24ECFF35022CA5B5959:'
  fi
  exit 0
fi
[[ " $* " != *" --import "* ]] || exit 0
echo '[GNUPG:] VALIDSIG 5983B1CA32CB778F4D74D24ECFF35022CA5B5959'
echo '[GNUPG:] VALIDSIG C81AC3E2A99556F9B21D5FEA3DD49BC9F8360BDC'
SH
cat >"$bundle_bin/pacman" <<'SH'
#!/bin/bash
case "$1" in
  -Q)
    [[ -n ${2:-} ]] || { cat "$TEST_INSTALLED"; exit 0; }
    version=$(awk -v p="$2" '$1 == p { print $2 }' "$TEST_INSTALLED")
    [[ -n $version ]] && echo "$2 $version"
    ;;
  -Qq) [[ $2 == linux-asahi ]] ;;
  -U)
    for archive in "$@"; do
      [[ $archive == *.pkg.tar* ]] || continue
      info=$(bsdtar -xOf "$archive" .PKGINFO)
      name=$(sed -n 's/^pkgname = //p' <<<"$info")
      version=$(sed -n 's/^pkgver = //p' <<<"$info")
      grep -v "^$name " "$TEST_INSTALLED" >"$TEST_INSTALLED.new" || true
      echo "$name $version" >>"$TEST_INSTALLED.new"
      mv "$TEST_INSTALLED.new" "$TEST_INSTALLED"
    done
    ;;
  *) exit 1 ;;
esac
SH
# Backups and state go to /var/lib/omarchy on a real Mac; only the package
# transaction runs here.
cat >"$bundle_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$TEST_BUNDLE_CALLS"
[[ $1 != env ]] || "$@"
SH
chmod +x "$bundle_bin"/*

bundle_packages=(omarchy-keyring omarchy-settings-dev omarchy-dev omarchy-nvim quickshell-git ttf-jetbrains-mono-nerd-basic)
declare -A bundle_versions=(
  [omarchy-keyring]=20260901-1 [omarchy-settings-dev]=4.0.4.r1-1 [omarchy-dev]=4.0.4.r1-1
  [omarchy-nvim]=2026.8.1-3 [quickshell-git]=0.2.1-1 [ttf-jetbrains-mono-nerd-basic]=3.4.0-1
)
manifest="$assets/asahi-quattro-bundle.manifest"
printf 'format=2\nbundle=asahi-quattro\nsource_commit=%s\npackage_count=6\n' "$source_commit" >"$manifest"
index=0
for name in "${bundle_packages[@]}"; do
  index=$((index + 1))
  arch=any
  [[ $name != omarchy-settings-dev && $name != omarchy-dev && $name != quickshell-git ]] || arch=aarch64
  pkgdir="$test_tmp/pkg-$name"
  mkdir -p "$pkgdir"
  {
    printf 'pkgname = %s\npkgver = %s\narch = %s\n' "$name" "${bundle_versions[$name]}" "$arch"
    [[ $arch == any || $name == quickshell-git ]] || printf 'provides = omarchy-quattro-bundle=%s\n' "$source_commit"
  } >"$pkgdir/.PKGINFO"
  filename="$name-${bundle_versions[$name]}-$arch.pkg.tar.gz"
  bsdtar -czf "$assets/$filename" -C "$pkgdir" .PKGINFO
  : >"$assets/$filename.sig"
  printf 'package=%s|%s|%s|%s|%s|%s\n' "$index" "$name" "${bundle_versions[$name]}" "$arch" "$filename" \
    "$(sha256sum "$assets/$filename" | cut -d' ' -f1)" >>"$manifest"
done
: >"$manifest.sig"
cat >"$assets/asahi-quattro-channel" <<EOF
format=1
channel=asahi-quattro
sequence=2
release_tag=asahi-quattro-test
source_commit=$source_commit
manifest=asahi-quattro-bundle.manifest
manifest_sha256=$(sha256sum "$manifest" | cut -d' ' -f1)
EOF
: >"$assets/asahi-quattro-channel.sig"

# The legacy omarchy-nvim, installed newer than the bundle.
legacy_version=2026.9.4-1
printf 'omarchy-keyring 20260901-1\nomarchy-nvim %s\nttf-jetbrains-mono-nerd-basic 3.4.0-1\n' "$legacy_version" >"$test_tmp/installed"
mkdir -p "$root/var/lib/pacman/local/omarchy-nvim-$legacy_version"
printf '%%NAME%%\nomarchy-nvim\n\n%%VERSION%%\n%s\n\n%%BUILDDATE%%\n1789000000\n\n%%PACKAGER%%\nUnknown Packager\n' "$legacy_version" \
  >"$root/var/lib/pacman/local/omarchy-nvim-$legacy_version/desc"
write_legacy_db() {
  local target=$1 build_date=$2 dbdir="$test_tmp/legacy-db"
  rm -rf "$dbdir"
  mkdir -p "$dbdir/omarchy-nvim-$legacy_version" "$(dirname "$target")"
  printf '%%FILENAME%%\nomarchy-nvim-%s-any.pkg.tar.zst\n\n%%NAME%%\nomarchy-nvim\n\n%%VERSION%%\n%s\n\n%%BUILDDATE%%\n%s\n' \
    "$legacy_version" "$legacy_version" "$build_date" >"$dbdir/omarchy-nvim-$legacy_version/desc"
  bsdtar -czf "$target" -C "$dbdir" "omarchy-nvim-$legacy_version"
}

run_bundle() {
  TEST_ASSETS="$assets" \
    TEST_INSTALLED="$test_tmp/installed" \
    TEST_BUNDLE_CALLS="$test_tmp/bundle-calls" \
    OMARCHY_ASAHI_ROOT="$root" \
    OMARCHY_ASAHI_BUNDLE_STATE="$test_tmp/bundle-state" \
    OMARCHY_ASAHI_CHANNEL_URL="https://example.test/asahi-quattro-channel" \
    OMARCHY_ASAHI_KEY_FILE="$test_tmp/release.gpg" \
    OMARCHY_ASAHI_PACKAGE_KEY_FILE="$test_tmp/package.asc" \
    PATH="$bundle_bin:$PATH" \
    bash "$bundle" "$@" >"$test_tmp/bundle.out" 2>"$test_tmp/bundle.err"
}

write_legacy_db "$root/var/lib/pacman/sync/omarchy-aarch64.db" 1789000000
run_bundle || fail "the bundle refuses a package the retired repository built" "$(cat "$test_tmp/bundle.err")"
grep -Fq "omarchy-nvim $legacy_version came from the retired [omarchy-aarch64] repository; replacing it with the signed 2026.8.1-3" "$test_tmp/bundle.out" ||
  fail "the legacy downgrade is not reported" "$(cat "$test_tmp/bundle.out")"
cp "$test_tmp/installed" "$test_tmp/installed.legacy"
: >"$test_tmp/bundle-calls"
run_bundle --yes || fail "the bundle does not install over a legacy package" "$(cat "$test_tmp/bundle.out" "$test_tmp/bundle.err" "$test_tmp/bundle-calls")"
grep -q '^sudo env OMARCHY_UPDATE_PACMAN=1 pacman -U --noconfirm -- .*/omarchy-nvim-2026.8.1-3-any.pkg.tar.gz' "$test_tmp/bundle-calls" ||
  fail "the signed bundle is not installed in one transaction" "$(cat "$test_tmp/bundle-calls")"
grep -Fxq 'omarchy-nvim 2026.8.1-3' "$test_tmp/installed" ||
  fail "the legacy omarchy-nvim is not replaced by the signed version" "$(cat "$test_tmp/installed")"
grep -Fq 'Installed Apple Silicon Quattro bundle asahi-quattro-test' "$test_tmp/bundle.out" ||
  fail "the bundle install does not finish" "$(cat "$test_tmp/bundle.out")"
mv "$test_tmp/installed.legacy" "$test_tmp/installed"
pass "a bundle package the configured legacy repository built newer is downgraded"

rm -f "$root/var/lib/pacman/sync/omarchy-aarch64.db"
write_legacy_db "$root/var/lib/omarchy/retired-repositories/omarchy-aarch64.db" 1789000000
run_bundle || fail "the bundle refuses a legacy package once the section is gone" "$(cat "$test_tmp/bundle.err")"
grep -Fq 'came from the retired [omarchy-aarch64] repository' "$test_tmp/bundle.out" ||
  fail "the kept sync database does not prove the legacy package"
pass "the sync database kept by the cleanup still proves a legacy package"

# Same name and version, another build: not the retired repository's package.
write_legacy_db "$root/var/lib/omarchy/retired-repositories/omarchy-aarch64.db" 1789000001
set +e
run_bundle
status=$?
set -e
(( status == 2 )) && grep -Fq 'omarchy-nvim would be downgraded' "$test_tmp/bundle.err" ||
  fail "a newer package with a different build is downgraded" "$(cat "$test_tmp/bundle.out" "$test_tmp/bundle.err")"
rm -f "$root/var/lib/omarchy/retired-repositories/omarchy-aarch64.db"
set +e
run_bundle
status=$?
set -e
(( status == 2 )) && grep -Fq 'omarchy-nvim would be downgraded' "$test_tmp/bundle.err" ||
  fail "a newer package without a legacy database entry is downgraded"
pass "an unrelated newer bundle package is still refused"
