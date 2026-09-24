#!/bin/bash
#
# Apple Silicon accounts created from Arch's bash skeleton get the Omarchy
# ~/.bashrc; any other ~/.bashrc is left alone.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1790226283.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/db/local/bash-5.3.20-1" "$tmp/db/local/bash-completion-2.16.0-1" "$tmp/home"
export PATH="$tmp/bin:$PATH" OMARCHY_PATH="$ROOT"
printf '#!/bin/bash\nexit "${APPLE:-0}"\n' >"$tmp/bin/omarchy-hw-apple-silicon"
printf '#!/bin/bash\n[[ $1 == DBPath ]] && echo "%s/db/"\n' "$tmp" >"$tmp/bin/pacman-conf"
chmod +x "$tmp/bin"/*

# Arch's bash dot.bashrc, before and after the 2023-02 grep alias.
arch_2011=$'#\n# ~/.bashrc\n#\n\n# If not running interactively, don\'t do anything\n[[ $- != *i* ]] && return\n\nalias ls=\'ls --color=auto\'\nPS1=\'[\\u@\\h \\W]\\$ \'\n'
arch_2023=$'#\n# ~/.bashrc\n#\n\n# If not running interactively, don\'t do anything\n[[ $- != *i* ]] && return\n\nalias ls=\'ls --color=auto\'\nalias grep=\'grep --color=auto\'\nPS1=\'[\\u@\\h \\W]\\$ \'\n'
[[ $(printf '%s' "$arch_2011" | sha256sum | cut -d ' ' -f 1) == 3e22bf86ae6708df7a6bceb88c67a00118275f9c0b5268f453dd388af7c43b53 ]] ||
  fail "the 2011 Arch skeleton fixture matches Arch's file"
[[ $(printf '%s' "$arch_2023" | sha256sum | cut -d ' ' -f 1) == 959bc596166c9758fdd68836581f6b8f1d6fdb947d580bf24dce607998a077b8 ]] ||
  fail "the 2023 Arch skeleton fixture matches Arch's file"

mtree_for() {
  printf '#mtree\n./etc/skel/.bashrc time=1.0 mode=644 size=%s md5digest=0 sha256digest=%s\n' \
    "${#1}" "$(printf '%s' "$1" | sha256sum | cut -d ' ' -f 1)" | gzip -c >"$2"
}
: | gzip -c >"$tmp/db/local/bash-5.3.20-1/mtree"

migrate() {
  HOME="$tmp/home" bash -euo pipefail "$migration" >"$tmp/out" 2>&1
}

reset_home() {
  rm -rf "$tmp/home"
  mkdir -p "$tmp/home"
  [[ -z $1 ]] || printf '%s' "$1" >"$tmp/home/.bashrc"
}

for stock in "$arch_2011" "$arch_2023"; do
  reset_home "$stock"
  migrate || fail "the migration runs" "$(<"$tmp/out")"
  cmp -s "$tmp/home/.bashrc" "$ROOT/default/bashrc" || fail "a stock Arch ~/.bashrc is replaced by Omarchy's"
  backups=("$tmp/home"/.bashrc.bak.*)
  (( ${#backups[@]} == 1 )) && [[ $(<"${backups[0]}") == "$(printf '%s' "$stock")" ]] ||
    fail "the stock ~/.bashrc is backed up first" "$(ls -a "$tmp/home")"
  grep -Fq "${backups[0]}" "$tmp/out" || fail "the backup path is reported" "$(<"$tmp/out")"
  [[ $(<"$tmp/home/.bash_profile") == '[[ -f ~/.bashrc ]] && . ~/.bashrc' ]] ||
    fail "a home without ~/.bash_profile gets one that sources ~/.bashrc"
done
pass "a stock Arch ~/.bashrc from either skeleton becomes Omarchy's, backed up"

migrate || fail "a second run passes"
[[ $(find "$tmp/home" -name '.bashrc.bak.*' | wc -l) == 1 ]] || fail "a second run makes no second backup"
cmp -s "$tmp/home/.bashrc" "$ROOT/default/bashrc" || fail "a second run keeps Omarchy's ~/.bashrc"
pass "the migration is idempotent"

# A skeleton this migration does not know, recorded by the installed bash package.
future=$'# ~/.bashrc from a future Arch bash\n[[ $- != *i* ]] && return\n'
mtree_for "$future" "$tmp/db/local/bash-5.3.20-1/mtree"
reset_home "$future"
printf '%s\n' '# user profile' >"$tmp/home/.bash_profile"
migrate || fail "the migration runs against the package's skeleton" "$(<"$tmp/out")"
cmp -s "$tmp/home/.bashrc" "$ROOT/default/bashrc" || fail "the installed bash package's skeleton is recognised"
[[ $(<"$tmp/home/.bash_profile") == '# user profile' ]] || fail "an existing ~/.bash_profile is left alone"
pass "the installed bash package's own skeleton is recognised"

for login_file in .bash_login .profile; do
  reset_home "$arch_2023"
  printf '%s\n' '# user login file' >"$tmp/home/$login_file"
  migrate || fail "the migration runs with a $login_file" "$(<"$tmp/out")"
  cmp -s "$tmp/home/.bashrc" "$ROOT/default/bashrc" || fail "a home with a $login_file still gets Omarchy's ~/.bashrc"
  [[ ! -e $tmp/home/.bash_profile ]] || fail "a ~/.bash_profile would shadow the user's $login_file"
done
pass "a ~/.bash_login or ~/.profile is not shadowed by a new ~/.bash_profile"

mtree_for "$future" "$tmp/db/local/bash-completion-2.16.0-1/mtree"
: | gzip -c >"$tmp/db/local/bash-5.3.20-1/mtree"
reset_home "$future"
migrate || fail "the migration runs"
[[ $(<"$tmp/home/.bashrc") == "$(printf '%s' "$future")" ]] || fail "only the bash package's skeleton counts, not bash-completion's"
pass "other bash-* packages do not vouch for a skeleton"

custom="${arch_2023}alias ll='ls -l'"$'\n'
reset_home "$custom"
migrate || fail "a customized ~/.bashrc passes"
[[ $(<"$tmp/home/.bashrc") == "$(printf '%s' "$custom")" ]] || fail "a customized ~/.bashrc is left alone"
[[ -z $(find "$tmp/home" -name '.bashrc.bak.*') && ! -e $tmp/home/.bash_profile ]] || fail "a customized home is untouched"
reset_home "$(<"$ROOT/default/bashrc")"
migrate || fail "an Omarchy ~/.bashrc passes"
[[ -z $(find "$tmp/home" -name '.bashrc.bak.*') ]] || fail "an Omarchy ~/.bashrc is not backed up again"
reset_home ""
migrate || fail "a home without ~/.bashrc passes"
[[ ! -e $tmp/home/.bashrc ]] || fail "a home without ~/.bashrc is left without one"
reset_home ""
printf '%s' "$arch_2023" >"$tmp/stock"
ln -s "$tmp/stock" "$tmp/home/.bashrc"
migrate || fail "a symlinked ~/.bashrc passes"
[[ -L $tmp/home/.bashrc && $(<"$tmp/stock") == "$(printf '%s' "$arch_2023")" ]] || fail "a symlinked ~/.bashrc is left alone"
pass "any other ~/.bashrc is the user's and stays"

reset_home "$arch_2023"
APPLE=1 migrate || fail "a non-Apple machine passes"
[[ $(<"$tmp/home/.bashrc") == "$(printf '%s' "$arch_2023")" ]] || fail "a non-Apple machine is untouched"
pass "the migration gates itself to Apple Silicon"

grep -Fq $'1790226283.sh) printf \'run\\treviewed' "$ROOT/bin/omarchy-migrate" ||
  fail "the Apple Silicon migration policy runs the bashrc migration"
pass "the Apple Silicon migration policy runs the bashrc migration"
