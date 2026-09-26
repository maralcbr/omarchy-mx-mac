#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# omarchy-mac-migrate-bootstrap fetches the official omarchy-mac-boot, accepts
# it only when the pinned Omarchy key signed it, unpacks it and runs its engine.
# Here the repositories are file:// directories, the key is a throwaway one and
# the package's omarchy-mac-migrate records how it was run and exits with
# $FIXTURE/engine-status. The engine itself is covered by the boot package's
# mac-migrate tests.
require_command gpg
require_command gpgv
require_command bsdtar
require_command curl
require_command flock

tmp=$(mktemp -d)
trap 'gpgconf --homedir "$tmp/signer" --kill all 2>/dev/null; gpgconf --homedir "$tmp/other" --kill all 2>/dev/null; rm -rf "$tmp"' EXIT
bootstrap=$ROOT/bin/omarchy-mac-migrate-bootstrap

keygen() {
  mkdir -m 700 "$tmp/$1"
  gpg --batch --homedir "$tmp/$1" --pinentry-mode loopback --passphrase '' --quick-gen-key "$1" ed25519 sign 1d 2>/dev/null
  gpg --batch --homedir "$tmp/$1" --with-colons --list-secret-keys 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }'
}
signer=$(keygen signer)
keygen other >/dev/null
mkdir -p "$tmp/keys"
gpg --batch --homedir "$tmp/signer" --armor --export "$signer" >"$tmp/keys/$signer" 2>/dev/null

# package VERSION TARGET-CHANNEL|none: an omarchy-mac-boot archive in $tmp/built.
package() {
  local version=$1 channel=$2 stage=$tmp/stage
  rm -rf "$stage"
  mkdir -p "$stage/usr/bin" "$stage/usr/lib/omarchy-mac/boot" "$tmp/built"
  printf 'pkgname = omarchy-mac-boot\npkgver = %s\n' "$version" >"$stage/.PKGINFO"
  cat >"$stage/usr/bin/omarchy-mac-migrate" <<'SH'
#!/bin/bash
# Stands in for the engine, which takes --payload DIR first.
printf '%s\n' "$*" >>"$FIXTURE/engine.log"
exit "$(cat "$FIXTURE/engine-status")"
SH
  chmod 755 "$stage/usr/bin/omarchy-mac-migrate"
  echo "# the engine" >"$stage/usr/lib/omarchy-mac/boot/migrate-engine.sh"
  [[ $channel == "none" ]] || printf 'format=1\ntype=repository\nchannel=%s\n' "$channel" >"$stage/usr/lib/omarchy-mac/boot/migration-target"
  (cd "$stage" && bsdtar -czf "$tmp/built/$version-$channel.pkg.tar.gz" .PKGINFO usr)
  printf '%s\n' "$tmp/built/$version-$channel.pkg.tar.gz"
}

# publish CHANNEL VERSION ARCHIVE [SIGNER-HOME]: CHANNEL's [omarchy] lists it.
publish() {
  local channel=$1 version=$2 archive=$3 home=${4:-signer} dir=$tmp/pkgs/$1 file
  file=omarchy-mac-boot-$version-aarch64.pkg.tar.gz
  rm -rf "$dir"
  mkdir -p "$dir/db/omarchy-mac-boot-$version" "$dir/db/omarchy-4.0.4-1"
  cp "$archive" "$dir/$file"
  gpg --batch --homedir "$tmp/$home" --detach-sign --no-armor -o "$dir/$file.sig" "$dir/$file" 2>/dev/null
  printf '%%FILENAME%%\n%s\n\n%%NAME%%\nomarchy-mac-boot\n\n%%VERSION%%\n%s\n\n%%SHA256SUM%%\n%s\n' \
    "$file" "$version" "$(sha256sum "$dir/$file" | cut -d' ' -f1)" >"$dir/db/omarchy-mac-boot-$version/desc"
  printf '%%FILENAME%%\nomarchy-4.0.4-1-aarch64.pkg.tar.zst\n\n%%NAME%%\nomarchy\n\n%%VERSION%%\n4.0.4-1\n' >"$dir/db/omarchy-4.0.4-1/desc"
  (cd "$dir/db" && bsdtar -czf ../omarchy.db omarchy-4.0.4-1 "omarchy-mac-boot-$version")
}

new_root() {
  R=$tmp/root
  rm -rf "$R" "$tmp/pkgs"
  mkdir -p "$R/run/lock" "$R/var/lib" "$tmp/bin"
  echo apple-silicon >"$tmp/platform"
  echo 0 >"$tmp/engine-status"
  : >"$tmp/engine.log"
  printf '#!/bin/bash\ncat "$FIXTURE/platform"\n' >"$tmp/bin/omarchy-hw-platform"
  chmod 755 "$tmp/bin/omarchy-hw-platform"
}

run_bootstrap() {
  env OMARCHY_MAC_MIGRATE_ROOT="$R" OMARCHY_MAC_BOOTSTRAP_SERVER="file://$tmp/pkgs/\$channel" OMARCHY_MAC_BOOTSTRAP_KEY="$signer" \
    OMARCHY_MAC_BOOTSTRAP_KEYSERVER="file://$tmp/keys" FIXTURE="$tmp" PATH="$tmp/bin:$PATH" "$bootstrap" "$@"
}

payload=/var/lib/omarchy-mac/bootstrap/payload

expect_deferred() { # description pattern [args...]
  local description=$1 pattern=$2 status=0 output
  shift 2
  output=$(run_bootstrap "$@" 2>&1) || status=$?
  (( status == 75 )) && grep -q -- "$pattern" <<<"$output" || fail "$description is deferred" "status $status: $output"
  [[ ! -s $tmp/engine.log ]] || fail "$description runs no engine" "$(cat "$tmp/engine.log")"
}

new_root
echo generic >"$tmp/platform"
output=$(run_bootstrap 2>&1) || fail "another platform: nothing to migrate" "$output"
[[ ! -e $R/var/lib/omarchy-mac && ! -s $tmp/engine.log ]] || fail "another platform: nothing runs or is written"
pass "anything but an Apple Silicon Mac has nothing to migrate"

new_root
expect_deferred "a repository it cannot read" "cannot read the stable \[omarchy\] repository"
mkdir -p "$tmp/pkgs/stable/db/omarchy-4.0.4-1"
: >"$tmp/pkgs/stable/db/omarchy-4.0.4-1/desc"
(cd "$tmp/pkgs/stable/db" && bsdtar -czf ../omarchy.db omarchy-4.0.4-1)
expect_deferred "a repository without omarchy-mac-boot" "has no omarchy-mac-boot yet"
publish stable 20260926-1 "$(package 20260926-1 none)"
expect_deferred "an omarchy-mac-boot without a target" "does not activate the migration yet"
pass "no repository, no package or a package that does not activate the migration defers, running nothing"

new_root
publish stable 20260926-1 "$(package 20260926-1 stable)" other
expect_deferred "a package another key signed" "is not signed by the Omarchy packaging key"
[[ ! -e $R$payload ]] || fail "a package another key signed is never unpacked"
new_root
publish stable 20260926-1 "$(package 20260926-1 stable)"
echo tampered >>"$tmp/pkgs/stable/omarchy-mac-boot-20260926-1-aarch64.pkg.tar.gz"
expect_deferred "a package that does not match the repository" "does not match the repository's checksum"
pass "only a package the pinned key signed, as the repository lists it, is unpacked"

new_root
publish stable 20260926-1 "$(package 20260926-1 stable)"
output=$(run_bootstrap 2>&1) || fail "a published, activated package runs its engine" "$output"
[[ $(cat "$tmp/engine.log") == "--payload $R$payload run --target $R$payload/usr/lib/omarchy-mac/boot/migration-target" ]] ||
  fail "the engine runs from the download with the packaged target" "$(cat "$tmp/engine.log")"
[[ $(stat -c %a "$R/var/lib/omarchy-mac/bootstrap") == 700 && ! -e $R/etc/omarchy-mac/migration-target ]] ||
  fail "the download is root's alone and the packaged channel needs no target of its own"
pass "a published package the pinned key signed runs its engine from the download, with its own target"

# The key comes from omarchy-keyring's file before the keyserver.
new_root
publish stable 20260926-1 "$(package 20260926-1 stable)"
mkdir -p "$R/usr/share/pacman/keyrings"
cp "$tmp/keys/$signer" "$R/usr/share/pacman/keyrings/omarchy.gpg"
mv "$tmp/keys" "$tmp/keys.away"
output=$(run_bootstrap 2>&1) || fail "the installed Omarchy keyring verifies the package" "$output"
mv "$tmp/keys.away" "$tmp/keys"
pass "the installed Omarchy keyring verifies the package without the keyserver"

for status in 75 1; do
  new_root
  publish stable 20260926-1 "$(package 20260926-1 stable)"
  echo "$status" >"$tmp/engine-status"
  result=0
  run_bootstrap >/dev/null 2>&1 || result=$?
  (( result == status )) || fail "the engine's status $status is the bootstrap's" "status $result"
done
pass "the engine's deferral and failure are the bootstrap's"

# A Mac that keeps its own channel: the package comes from that channel and
# /etc/omarchy-mac/migration-target keeps it for every later run.
new_root
publish rc 20260926-2 "$(package 20260926-2 stable)"
output=$(run_bootstrap --channel rc 2>&1) || fail "a Mac on rc migrates on rc" "$output"
[[ $(cat "$R/etc/omarchy-mac/migration-target") == $'format=1\ntype=repository\nchannel=rc' ]] ||
  fail "the channel the Mac keeps is its target's" "$(cat "$R/etc/omarchy-mac/migration-target")"
[[ $(cat "$tmp/engine.log") == "--payload $R$payload run --target $R/etc/omarchy-mac/migration-target" ]] ||
  fail "the engine runs with the kept channel's target" "$(cat "$tmp/engine.log")"
[[ $(sed -n 's/^pkgver = //p' "$R$payload/.PKGINFO") == "20260926-2" ]] || fail "the package comes from the kept channel"
: >"$tmp/engine.log"
output=$(run_bootstrap 2>&1) || fail "a later run keeps the channel" "$output"
grep -q -- "--target $R/etc/omarchy-mac/migration-target" "$tmp/engine.log" || fail "a later run reads the kept channel" "$(cat "$tmp/engine.log")"
pass "a Mac's own channel is where the package comes from and what its target keeps"

new_root
publish stable 20260926-1 "$(package 20260926-1 stable)"
output=$(run_bootstrap --prime 2>&1) || fail "priming succeeds" "$output"
grep -q "ready to move this Mac onto the stable channel" <<<"$output" && [[ -x $R$payload/usr/bin/omarchy-mac-migrate && ! -s $tmp/engine.log ]] ||
  fail "priming unpacks the package and runs nothing" "$output"
rm "$tmp/pkgs/stable/omarchy-mac-boot-20260926-1-aarch64.pkg.tar.gz"
output=$(run_bootstrap 2>&1) || fail "the primed package runs without a new download" "$output"
[[ -s $tmp/engine.log ]] || fail "the primed package's engine runs"
publish stable 20260927-1 "$(package 20260927-1 stable)"
: >"$tmp/engine.log"
output=$(run_bootstrap 2>&1) || fail "a newer package replaces the primed one" "$output"
[[ $(sed -n 's/^pkgver = //p' "$R$payload/.PKGINFO") == "20260927-1" ]] || fail "the newer package is unpacked"
pass "priming unpacks the package without running it; a run reuses it while it is current and fetches a newer one"

# Past its preflight, a migration resumes with the engine it started with.
new_root
publish stable 20260926-1 "$(package 20260926-1 stable)"
run_bootstrap --prime >/dev/null
mkdir -p "$R/var/lib/omarchy-mac/migration"
printf '1 preflight begin x\n2 preflight done\n' >"$R/var/lib/omarchy-mac/migration/journal"
publish stable 20260927-1 "$(package 20260927-1 stable)"
output=$(run_bootstrap 2>&1) || fail "a migration in progress resumes" "$output"
[[ $(cat "$tmp/engine.log") == "--payload $R$payload run" && $(sed -n 's/^pkgver = //p' "$R$payload/.PKGINFO") == "20260926-1" ]] ||
  fail "a migration in progress resumes with the engine it started with, and without a new target" "$(cat "$tmp/engine.log")"
mkdir -p "$R/usr/bin"
printf '#!/bin/bash\necho "installed $*" >>"$FIXTURE/engine.log"\n' >"$R/usr/bin/omarchy-mac-migrate"
chmod 755 "$R/usr/bin/omarchy-mac-migrate"
: >"$tmp/engine.log"
run_bootstrap >/dev/null 2>&1 || fail "a migration in progress resumes before its transaction"
[[ $(cat "$tmp/engine.log") == "--payload $R$payload run" ]] || fail "before its transaction the download still runs it" "$(cat "$tmp/engine.log")"
printf '3 transaction begin\n4 transaction done\n' >>"$R/var/lib/omarchy-mac/migration/journal"
: >"$tmp/engine.log"
run_bootstrap >/dev/null 2>&1 || fail "a migration past its transaction resumes"
[[ $(cat "$tmp/engine.log") == "installed run" ]] || fail "past its transaction the installed package runs it" "$(cat "$tmp/engine.log")"
: >"$R/var/lib/omarchy-mac/migration/complete"
: >"$tmp/engine.log"
run_bootstrap >/dev/null 2>&1 || fail "a finished migration runs again as a no-op"
[[ ! -e $R/var/lib/omarchy-mac/bootstrap ]] || fail "a finished migration drops the download"
pass "a migration in progress resumes with the download it started from, and with the installed package once its transaction ran"

new_root
publish stable 20260926-1 "$(package 20260926-1 stable)"
mkdir -p "$R/etc/omarchy-mac"
printf 'format=1\ntype=candidate-set\nchannel=edge\nset=/x\nfingerprint=%s\n' "$signer" >"$R/etc/omarchy-mac/migration-target"
expect_deferred "an administrator's candidate-set target" "is not a repository target"
pass "an administrator's own candidate-set target is left to them"
