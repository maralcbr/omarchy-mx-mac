#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command git
require_command jq

migration="$ROOT/migrations/1789701737.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME='Seeded Cache Test' GIT_AUTHOR_EMAIL='seeded-cache@example.invalid'
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

home="$test_dir/home"
nvim_config="$home/.config/nvim"
lazy_dir="$home/.local/share/nvim/lazy"
themes="$nvim_config/lua/plugins/all-themes.lua"
lockfile="$nvim_config/lazy-lock.json"

# Upstream plugins with two tagged releases and an unreleased tip.
for origin in main-origin trunk-origin; do
  git init -q -b "${origin%-origin}" "$test_dir/$origin"
  for release in 1 2 3; do
    printf 'return %s\n' "$release" >"$test_dir/$origin/plugin.lua"
    git -C "$test_dir/$origin" add plugin.lua
    git -C "$test_dir/$origin" commit -qm "Change $release"
    (( release == 3 )) || git -C "$test_dir/$origin" tag "v$release.0.0"
  done
done

# Reproduce what omarchy-nvim 2026.8.1-1 seeded: shallow plugin repos with no
# remote refs or tags, the release-pinned ones on a detached HEAD.
seed_plugin() {
  local name="$1"
  local origin="$2"
  local tag="${3:-}"
  local dir="$lazy_dir/$name"

  git clone -q "file://$test_dir/$origin" "$dir"
  [[ -z $tag ]] || git -C "$dir" checkout -q --detach "$tag"
  git -C "$dir" symbolic-ref -d refs/remotes/origin/HEAD
  git -C "$dir" for-each-ref --format='%(refname)' refs/remotes refs/tags |
    while IFS= read -r ref; do git -C "$dir" update-ref -d "$ref"; done
  git -C "$dir" rev-parse HEAD >"$dir/.git/shallow"
}

old_themes() {
  cat <<'EOF'
return {
	{
		"folke/tokyonight.nvim",
		lazy = true,
		priority = 1000,
	},
	{
		"gthelding/monokai-pro.nvim",
		lazy = true,
		priority = 1000,
	},
	-- gthelding/monokai-pro.nvim without quotes is a comment, not a spec
}
EOF
}

reset_home() {
  rm -rf "$home"
  mkdir -p "$nvim_config/lua/plugins" "$lazy_dir"
  old_themes >"$themes"
  printf '{' >"$lockfile"

  seed_plugin branch.nvim main-origin
  seed_plugin pinned.nvim main-origin v2.0.0
  seed_plugin remote-trunk.nvim trunk-origin v1.0.0
  seed_plugin offline.nvim main-origin v2.0.0
  git -C "$lazy_dir/offline.nvim" remote set-url origin "file://$test_dir/unreachable"

  # A plugin lazy cloned itself still has origin/HEAD, wherever it points.
  git clone -q "file://$test_dir/main-origin" "$lazy_dir/healthy.nvim"
  git -C "$lazy_dir/healthy.nvim" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/elsewhere
}

run_migration() {
  HOME="$home" bash -euo pipefail "$migration" >"$test_dir/out" 2>&1 ||
    fail "migration succeeds" "$(cat "$test_dir/out")"
}

origin_head() {
  cat "$lazy_dir/$1/.git/refs/remotes/origin/HEAD"
}

snapshot() {
  (
    cd "$home"
    find . -path '*/.git/logs' -prune -o -print | LC_ALL=C sort
    for dir in .local/share/nvim/lazy/*/; do
      [[ -d $dir ]] || continue
      git -C "$dir" for-each-ref --format='%(refname) %(objectname) %(symref)'
    done
    cat "$themes"
  )
}

# ---------------------------------------------------------------- full repair

reset_home
branch_head=$(git -C "$lazy_dir/branch.nvim" rev-parse HEAD)
pinned_head=$(git -C "$lazy_dir/pinned.nvim" rev-parse HEAD)
trunk_head=$(git -C "$lazy_dir/remote-trunk.nvim" rev-parse HEAD)
run_migration

[[ $(origin_head branch.nvim) == 'ref: refs/remotes/origin/main' ]] ||
  fail "a plugin on its branch gets origin/HEAD" "$(origin_head branch.nvim)"
[[ $(git -C "$lazy_dir/branch.nvim" rev-parse refs/remotes/origin/main) == "$branch_head" ]] ||
  fail "a plugin on its branch gets origin/main at its checked-out commit"
pass "a plugin on its branch gets origin/HEAD from its local branch"

[[ $(origin_head pinned.nvim) == 'ref: refs/remotes/origin/main' ]] ||
  fail "a release-pinned plugin gets origin/HEAD from its remote" "$(origin_head pinned.nvim)"
[[ $(git -C "$lazy_dir/pinned.nvim" rev-parse refs/remotes/origin/main) == "$pinned_head" ]] ||
  fail "a release-pinned plugin gets origin/main at its checked-out commit"
[[ $(origin_head remote-trunk.nvim) == 'ref: refs/remotes/origin/trunk' ]] ||
  fail "a release-pinned plugin takes the remote's default branch name" "$(origin_head remote-trunk.nvim)"
[[ $(git -C "$lazy_dir/remote-trunk.nvim" rev-parse refs/remotes/origin/trunk) == "$trunk_head" ]] ||
  fail "a release-pinned plugin gets origin/trunk at its checked-out commit"
! git -C "$lazy_dir/pinned.nvim" symbolic-ref -q HEAD >/dev/null ||
  fail "a release-pinned plugin stays on its release"
[[ $(git -C "$lazy_dir/pinned.nvim" rev-parse --is-shallow-repository) == true ]] ||
  fail "a repaired plugin stays shallow"
[[ -z $(git -C "$lazy_dir/pinned.nvim" tag) ]] || fail "the repair fetches no tags"
pass "a release-pinned plugin gets origin/HEAD from its remote"

[[ ! -e $lazy_dir/offline.nvim/.git/refs/remotes/origin/HEAD ]] ||
  fail "an unreachable plugin is left alone"
grep -Fq 'Skipped offline.nvim: could not determine its default branch' "$test_dir/out" ||
  fail "an unreachable plugin is skipped with a note" "$(cat "$test_dir/out")"
pass "an unreachable plugin is skipped with a note, not a failed migration"

[[ $(origin_head healthy.nvim) == 'ref: refs/remotes/origin/elsewhere' ]] ||
  fail "a plugin that has origin/HEAD is left alone" "$(origin_head healthy.nvim)"
pass "a plugin that has origin/HEAD is left alone"

diff -u <(old_themes | sed 's|"gthelding/monokai-pro.nvim"|"loctvl842/monokai-pro.nvim"|') "$themes" >/dev/null ||
  fail "only the quoted monokai-pro spec changes" "$(diff -u <(old_themes) "$themes")"
grep -Fq -- '-- gthelding/monokai-pro.nvim without quotes' "$themes" ||
  fail "an unquoted mention of the old repository is not rewritten"
pass "monokai-pro is repointed at loctvl842/monokai-pro.nvim and nothing else changes"

[[ ! -e $lockfile ]] || fail "a half-written lockfile is moved aside"
backups=("$lockfile".backup.*)
(( ${#backups[@]} == 1 )) && [[ -f ${backups[0]} ]] ||
  fail "a half-written lockfile lands in one timestamped backup" "$(ls -a "$nvim_config")"
[[ $(<"${backups[0]}") == '{' ]] || fail "the lockfile backup keeps the old content"
[[ ${backups[0]} =~ \.backup\.[0-9]{8}-[0-9]{6}$ ]] || fail "the lockfile backup is timestamped" "${backups[0]}"
pass "a half-written lockfile is moved aside to a timestamped backup"

# ---------------------------------------------------------------- idempotence

before=$(snapshot)
run_migration
[[ $(snapshot) == "$before" ]] || fail "the migration is idempotent" "$(diff <(printf '%s\n' "$before") <(snapshot))"
grep -Fq 'Moving the broken' "$test_dir/out" && fail "a second run moves no lockfile"
pass "the migration is idempotent"

# ------------------------------------------------------------------- lockfile

reset_home
: >"$lockfile"
run_migration
[[ ! -e $lockfile && -n $(compgen -G "$lockfile.backup.*") ]] || fail "an empty lockfile is moved aside"
pass "an empty lockfile is moved aside"

reset_home
printf '{\n  "branch.nvim": { "branch": "main", "commit": "%s" }\n}\n' "$branch_head" >"$lockfile"
cp "$lockfile" "$test_dir/valid-lock"
run_migration
cmp -s "$lockfile" "$test_dir/valid-lock" || fail "a valid lockfile is left alone"
[[ -z $(compgen -G "$lockfile.backup.*") ]] || fail "a valid lockfile gets no backup"
pass "a valid lockfile is left alone"

# ---------------------------------------------------------- dotfile symlinks

reset_home
mkdir -p "$home/dotfiles"
mv "$themes" "$home/dotfiles/all-themes.lua"
ln -s "$home/dotfiles/all-themes.lua" "$themes"
run_migration
[[ -L $themes && $(readlink "$themes") == "$home/dotfiles/all-themes.lua" ]] ||
  fail "a symlinked theme list stays a symlink"
grep -Fq '"loctvl842/monokai-pro.nvim"' "$home/dotfiles/all-themes.lua" ||
  fail "a symlinked theme list is repaired through the link"
pass "a symlinked theme list is repaired through the link"

# ------------------------------------------------------------ nothing to fix

reset_home
rm -rf "$nvim_config"
before=$(cd "$home" && find . | LC_ALL=C sort)
run_migration
[[ $(cd "$home" && find . | LC_ALL=C sort) == "$before" ]] || fail "no Neovim config means no changes"
[[ ! -e $lazy_dir/pinned.nvim/.git/refs/remotes/origin/HEAD ]] || fail "no Neovim config leaves the plugins alone"
pass "the migration does nothing without a Neovim config"

reset_home
rm -rf "$home/.local/share/nvim"
before=$(snapshot)
run_migration
[[ $(snapshot) == "$before" && $(<"$lockfile") == '{' ]] || fail "no lazy data dir means no changes"
pass "the migration does nothing without the lazy data dir"
