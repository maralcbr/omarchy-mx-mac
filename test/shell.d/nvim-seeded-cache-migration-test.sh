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
skel_lazy_dir="$test_dir/skel/lazy"

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

# The package's /etc/skel copy of a plugin: its origin URL and, from
# omarchy-nvim 2026.8.1-2 on, origin/HEAD.
skel_entry() {
  local name="$1"
  local url="$2"
  local branch="${3:-}"
  local dir="$skel_lazy_dir/$name/.git"

  mkdir -p "$dir/refs/remotes/origin"
  printf '[remote "origin"]\n\turl = %s\n' "$url" >"$dir/config"
  [[ -z $branch ]] || printf 'ref: refs/remotes/origin/%s\n' "$branch" >"$dir/refs/remotes/origin/HEAD"
}

reset_home() {
  rm -rf "$home" "$test_dir/skel"
  mkdir -p "$nvim_config/lua/plugins" "$lazy_dir"
  old_themes >"$themes"
  printf '{' >"$lockfile"

  seed_plugin branch.nvim main-origin
  skel_entry branch.nvim "file://$test_dir/main-origin" main
  # Seeded, but the installed skel copy predates origin/HEAD.
  seed_plugin pinned.nvim main-origin v2.0.0
  skel_entry pinned.nvim "file://$test_dir/main-origin"
  # A same-named fork of a seeded plugin, with a different default branch.
  seed_plugin remote-trunk.nvim trunk-origin v1.0.0
  skel_entry remote-trunk.nvim "https://github.com/upstream/remote-trunk.nvim.git" main
  seed_plugin offline.nvim main-origin v2.0.0
  git -C "$lazy_dir/offline.nvim" remote set-url origin "file://$test_dir/offline-origin"
  skel_entry offline.nvim "file://$test_dir/offline-origin" stable

  # Not seeded: unused, or naming its branch in its spec, so lazy may not care.
  seed_plugin stranded.nvim main-origin v2.0.0
  git -C "$lazy_dir/stranded.nvim" remote set-url origin "file://$test_dir/stranded-origin"
  seed_plugin local.nvim main-origin

  # A plugin lazy cloned itself still has origin/HEAD, wherever it points.
  git clone -q "file://$test_dir/main-origin" "$lazy_dir/healthy.nvim"
  git -C "$lazy_dir/healthy.nvim" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/elsewhere
}

run_migration() {
  HOME="$home" OMARCHY_NVIM_SKEL_LAZY_DIR="$skel_lazy_dir" bash -euo pipefail "$migration" >"$test_dir/out" 2>&1 ||
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
offline_head=$(git -C "$lazy_dir/offline.nvim" rev-parse HEAD)
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
  fail "a fork takes its own remote's default branch, not the skel copy's" "$(origin_head remote-trunk.nvim)"
[[ $(git -C "$lazy_dir/remote-trunk.nvim" rev-parse refs/remotes/origin/trunk) == "$trunk_head" ]] ||
  fail "a release-pinned plugin gets origin/trunk at its checked-out commit"
! git -C "$lazy_dir/pinned.nvim" symbolic-ref -q HEAD >/dev/null ||
  fail "a release-pinned plugin stays on its release"
[[ $(git -C "$lazy_dir/pinned.nvim" rev-parse --is-shallow-repository) == true ]] ||
  fail "a repaired plugin stays shallow"
[[ -z $(git -C "$lazy_dir/pinned.nvim" tag) ]] || fail "the repair fetches no tags"
pass "a release-pinned plugin whose skel copy has no origin/HEAD gets it from its remote"

[[ $(origin_head offline.nvim) == 'ref: refs/remotes/origin/stable' ]] ||
  fail "an unreachable plugin takes its branch from the package's skel copy" "$(origin_head offline.nvim)"
[[ $(git -C "$lazy_dir/offline.nvim" rev-parse refs/remotes/origin/stable) == "$offline_head" ]] ||
  fail "an unreachable plugin gets origin/stable at its checked-out commit"
pass "an unreachable plugin takes its branch from the package's skel copy, offline"

[[ ! -e $lazy_dir/stranded.nvim/.git/refs/remotes/origin/HEAD ]] || fail "an unreachable unseeded plugin is left alone"
grep -Fq 'Skipped stranded.nvim: could not determine its default branch' "$test_dir/out" ||
  fail "an unreachable unseeded plugin is skipped with a note" "$(cat "$test_dir/out")"
pass "an unreachable unseeded plugin is skipped with a note, not a failed migration"

[[ ! -e $lazy_dir/local.nvim/.git/refs/remotes/origin/HEAD ]] || fail "an unseeded plugin on its branch is left alone"
pass "an unseeded plugin on its branch is left alone"

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

# ------------------------------------------------------------- retry offline

# Through the runner: a seeded plugin nothing can name stays broken, so the
# migration must stay pending until a later run, back online, repairs it.
runner_root="$test_dir/omarchy"
marker="$home/.local/state/omarchy/migrations/1789701737.sh"
mkdir -p "$runner_root/bin" "$runner_root/migrations"
printf '#!/bin/bash\nexit 0\n' >"$runner_root/bin/omarchy-hw-apple-silicon"
chmod +x "$runner_root/bin/omarchy-hw-apple-silicon"
cp "$migration" "$runner_root/migrations/"

run_runner() {
  HOME="$home" OMARCHY_PATH="$runner_root" OMARCHY_NVIM_SKEL_LAZY_DIR="$skel_lazy_dir" \
    "$ROOT/bin/omarchy-migrate" "$@" >"$test_dir/runner.out" 2>&1
}

reset_home
rm "$skel_lazy_dir/offline.nvim/.git/refs/remotes/origin/HEAD"
run_runner && fail "a seeded plugin with no known branch fails the migration" "$(cat "$test_dir/runner.out")"
[[ ! -e $marker ]] || fail "a failed repair leaves the migration pending"
grep -Fq 'Could not determine the default branch of offline.nvim (offline?); this migration will retry.' "$test_dir/runner.out" ||
  fail "a failed repair says it will retry" "$(cat "$test_dir/runner.out")"
[[ ! -e $lazy_dir/offline.nvim/.git/refs/remotes/origin/HEAD ]] || fail "a plugin with no known branch is left alone"
[[ $(origin_head pinned.nvim) == 'ref: refs/remotes/origin/main' ]] ||
  fail "one failed plugin does not hold back the others" "$(origin_head pinned.nvim)"
grep -Fq '"loctvl842/monokai-pro.nvim"' "$themes" && [[ ! -e $lockfile ]] ||
  fail "one failed plugin does not hold back the theme and lockfile repairs"
run_runner --pending || fail "a failed repair is listed as pending"
[[ $(<"$test_dir/runner.out") == 1789701737.sh ]] ||
  fail "the pending list names the migration" "$(cat "$test_dir/runner.out")"
pass "an unresolved seeded plugin fails the migration and leaves it pending, after the other repairs"

git clone -q --bare "$test_dir/main-origin" "$test_dir/offline-origin"
run_runner || fail "the retry succeeds once the remote is reachable" "$(cat "$test_dir/runner.out")"
[[ -e $marker ]] || fail "a successful retry settles the migration"
[[ $(origin_head offline.nvim) == 'ref: refs/remotes/origin/main' ]] ||
  fail "the retry repairs the plugin from its remote" "$(origin_head offline.nvim)"
status=0
run_runner --pending || status=$?
(( status == 1 )) || fail "nothing is pending after the retry" "status $status: $(cat "$test_dir/runner.out")"
rm -rf "$test_dir/offline-origin"
pass "the retry repairs the plugin once online and settles the migration"

# ---------------------------------------------------------------- idempotence

reset_home
run_migration

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
