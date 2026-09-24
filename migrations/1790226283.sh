echo "Give Apple Silicon users the Omarchy ~/.bashrc in place of the stock Arch one"

# omarchy-settings-dev kept Arch's /etc/skel/.bashrc on Apple Silicon, so Mac
# accounts were created with the stock Arch bash skeleton and interactive
# shells missed the Omarchy environment, aliases and prompt. Replace ~/.bashrc
# only when it is byte-identical to an Arch bash skeleton, keeping a backup;
# any other ~/.bashrc is the user's and stays as it is.

omarchy-hw-apple-silicon || exit 0

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
bashrc="$HOME/.bashrc"
bash_profile="$HOME/.bash_profile"
omarchy_bashrc="$OMARCHY_PATH/default/bashrc"

[[ -f $omarchy_bashrc && -f $bashrc && ! -L $bashrc ]] || exit 0

# Arch's bash dot.bashrc: since 2023-02 (with the grep alias), and 2011-2023.
stock_hashes=(
  959bc596166c9758fdd68836581f6b8f1d6fdb947d580bf24dce607998a077b8
  3e22bf86ae6708df7a6bceb88c67a00118275f9c0b5268f453dd388af7c43b53
)
# The installed bash package records the hash of the skeleton it shipped.
dbpath=$(pacman-conf DBPath 2>/dev/null) || dbpath=""
[[ $dbpath == /* ]] || dbpath=/var/lib/pacman/
for mtree in "${dbpath%/}"/local/bash-[0-9]*/mtree; do
  [[ -r $mtree ]] || continue
  hash=$(gzip -dc "$mtree" 2>/dev/null |
    awk '$1 == "./etc/skel/.bashrc" { for (i = 2; i <= NF; i++) if ($i ~ /^sha256digest=/) { sub(/^sha256digest=/, "", $i); print $i } }')
  [[ $hash =~ ^[0-9a-f]{64}$ ]] && stock_hashes+=("$hash")
done

current=$(sha256sum "$bashrc" | cut -d ' ' -f 1)
[[ " ${stock_hashes[*]} " == *" $current "* ]] || exit 0

backup=$(mktemp "$bashrc.bak.XXXXXX")
cp -p "$bashrc" "$backup"
cp "$omarchy_bashrc" "$bashrc.omarchy-new"
mv "$bashrc.omarchy-new" "$bashrc"

# Login shells read the first of ~/.bash_profile, ~/.bash_login and ~/.profile;
# Arch's skeleton ships a ~/.bash_profile that sources ~/.bashrc. A home with
# none of them gets that line; one with any of them keeps what it has.
if [[ ! -e $bash_profile && ! -L $bash_profile && ! -e $HOME/.bash_login && ! -L $HOME/.bash_login &&
  ! -e $HOME/.profile && ! -L $HOME/.profile ]]; then
  echo '[[ -f ~/.bashrc ]] && . ~/.bashrc' >"$bash_profile"
fi

printf 'Replaced the stock Arch ~/.bashrc with the Omarchy one.\nBackup saved to:\n  %s\n' "$backup"
