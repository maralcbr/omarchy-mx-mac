echo "Repair the Neovim plugin cache and lockfile seeded by omarchy-nvim 2026.8.1-1"

nvim_config="$HOME/.config/nvim"
lazy_dir="$HOME/.local/share/nvim/lazy"
skel_lazy_dir="${OMARCHY_NVIM_SKEL_LAZY_DIR:-/etc/skel/.local/share/nvim/lazy}"

[[ -d $nvim_config && -d $lazy_dir ]] || exit 0

# -C keeps git from discovering a repository around the caller's directory.
origin_url() {
  git -C "$1" config --file "$1/.git/config" --get remote.origin.url 2>/dev/null
}

# A plugin the package seeded clones the same repository as its /etc/skel copy.
seeded_plugin() {
  local plugin="$1"
  local url

  url=$(origin_url "$plugin") && [[ -n $url && $url == "$(origin_url "$skel_lazy_dir/${plugin##*/}")" ]]
}

# omarchy-nvim 2026.8.1-2, installed before migrations run, seeds each plugin
# with origin/HEAD. Read the file: git refuses a repository owned by root.
skel_default_branch() {
  local head="$skel_lazy_dir/$1/.git/refs/remotes/origin/HEAD"

  [[ -f $head ]] && sed -n 's|^ref: refs/remotes/origin/||p' "$head"
}

remote_default_branch() {
  local plugin="$1"

  GIT_TERMINAL_PROMPT=0 timeout 30 git -C "$plugin" ls-remote --symref origin HEAD 2>/dev/null |
    awk '$1 == "ref:" && $3 == "HEAD" { sub("^refs/heads/", "", $2); print $2 }'
}

# The seed deleted origin/HEAD, which is where lazy.nvim looks up the branch of
# a plugin on a detached HEAD (every release-pinned one, such as lazy.nvim and
# blink.cmp). Without it, every lockfile write asserts after truncating
# lazy-lock.json. Recreate it the way omarchy-nvim 2026.8.1-2 builds it.
restore_origin_head() {
  local plugin="$1"
  local branch=""
  local head

  branch=$(git -C "$plugin" symbolic-ref --quiet --short HEAD) || branch=""
  if [[ -z $branch ]] && (( seeded )); then
    branch=$(skel_default_branch "${plugin##*/}") || branch=""
  fi
  [[ -n $branch ]] || branch=$(remote_default_branch "$plugin") || return 1
  [[ -n $branch ]] || return 1
  head=$(git -C "$plugin" rev-parse --verify --quiet HEAD) || return 1

  git -C "$plugin" show-ref --verify --quiet "refs/remotes/origin/$branch" ||
    git -C "$plugin" update-ref "refs/remotes/origin/$branch" "$head" || return 1
  git -C "$plugin" symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$branch"
}

# Only a seeded plugin is known to need the repair. Anything else without
# origin/HEAD may be unused or name its branch in its spec, so it is repaired
# when its remote answers and never holds the migration back.
unresolved=0
for git_dir in "$lazy_dir"/*/.git; do
  [[ -d $git_dir && ! -e $git_dir/refs/remotes/origin/HEAD ]] || continue
  plugin=${git_dir%/.git}
  seeded=0
  seeded_plugin "$plugin" && seeded=1

  if (( ! seeded )) && git -C "$plugin" symbolic-ref --quiet HEAD >/dev/null; then
    continue
  fi

  restore_origin_head "$plugin" && continue

  if (( seeded )); then
    echo "Could not determine the default branch of ${plugin##*/} (offline?); this migration will retry." >&2
    unresolved=1
  else
    echo "Skipped ${plugin##*/}: could not determine its default branch (offline?). Once online, run:"
    echo "  git -C \"$plugin\" fetch origin && git -C \"$plugin\" remote set-head origin --auto"
  fi
done

# gthelding/monokai-pro.nvim is gone, so lazy retried the clone on every launch.
themes="$nvim_config/lua/plugins/all-themes.lua"
if [[ -f $themes ]] && grep -qF '"gthelding/monokai-pro.nvim"' "$themes"; then
  sed -i --follow-symlinks 's|"gthelding/monokai-pro\.nvim"|"loctvl842/monokai-pro.nvim"|g' "$themes"
fi

# The failed write left an empty or half-written lockfile. lazy regenerates it.
lockfile="$nvim_config/lazy-lock.json"
if [[ -f $lockfile ]] && ! jq -e true "$lockfile" >/dev/null 2>&1; then
  backup="$lockfile.backup.$(date +%Y%m%d-%H%M%S)"
  echo "Moving the broken $lockfile to $backup"
  mv "$lockfile" "$backup"
fi

# Leave the migration pending so the next run retries what is still broken.
(( ! unresolved ))
