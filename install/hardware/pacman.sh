# Hardware-specific pacman repository extensions that must survive the final
# pacman.conf restore.
if omarchy-hw-apple-silicon; then
  release_key="${OMARCHY_ASAHI_PACKAGE_KEY_FILE:-$OMARCHY_PATH/default/omarchy-release.gpg}"
  release_fingerprint=5983B1CA32CB778F4D74D24ECFF35022CA5B5959
  release_tag=asahi-packages-784daa3efaecfa81b5b4da888b524e6ec4574d24
  release_server="https://github.com/maralcbr/omarchy-pkgs/releases/download/$release_tag"
  pacman_conf="${OMARCHY_PACMAN_CONF:-/etc/pacman.conf}"

  actual_fingerprint=$(gpg --batch --show-keys --with-colons "$release_key" |
    awk -F: '$1 == "pub" { primary=1; next } primary && $1 == "fpr" { print $10; exit }')
  [[ $actual_fingerprint == "$release_fingerprint" ]] || return 1

  if ! pacman-key --finger "$release_fingerprint" >/dev/null 2>&1; then
    pacman-key --add "$release_key"
  fi
  pacman-key --lsign-key "$release_fingerprint"

  if ! awk -v server="$release_server" '
    /^\[omarchy\][[:space:]]*$/ { inside = 1; blocks++; next }
    inside && /^\[[^]]+\][[:space:]]*$/ { inside = 0 }
    inside && NF { entries++ }
    inside && $0 == "SigLevel = Required DatabaseOptional" { signature = 1 }
    inside && $0 == "Server = " server { url = 1 }
    END { exit !(blocks == 1 && entries == 2 && signature && url) }
  ' "$pacman_conf"; then
    tmp="${pacman_conf}.omarchy.$$"
    awk '
      /^\[omarchy\][[:space:]]*$/ { skip = 1; next }
      skip && /^\[[^]]+\][[:space:]]*$/ { skip = 0 }
      !skip { print }
    ' "$pacman_conf" >"$tmp"
    # omarchy:heredoc-expands paths=none -- $release_server is assembled from fixed literals in this root-owned script
    cat >>"$tmp" <<EOF

[omarchy]
SigLevel = Required DatabaseOptional
Server = $release_server
EOF
    chmod --reference="$pacman_conf" "$tmp"
    chown --reference="$pacman_conf" "$tmp"
    mv "$tmp" "$pacman_conf"
    pacman -Sy --noconfirm
  fi
fi

if lspci -nn | grep "106b:180[12]" >/dev/null; then
  if ! grep -q '^\[arch-mact2\]' /etc/pacman.conf; then
    cat >> /etc/pacman.conf <<'EOF'

[arch-mact2]
Server = https://github.com/NoaHimesaka1873/arch-mact2-mirror/releases/download/release
SigLevel = Never
EOF
  fi
fi
