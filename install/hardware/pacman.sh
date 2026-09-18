# Hardware-specific pacman repository extensions that must survive the final
# pacman.conf restore.
if omarchy-hw-apple-silicon; then
  release_key="${OMARCHY_ASAHI_PACKAGE_KEY_FILE:-$OMARCHY_PATH/default/omarchy-release.gpg}"
  release_fingerprint=5983B1CA32CB778F4D74D24ECFF35022CA5B5959
  # The set written when nothing better is known: no [omarchy] section, or a
  # Server that is neither a recognised set nor the one the fresh installer
  # kept. A fresh install does not get here, because
  # bin/omarchy-install-asahi-fresh writes the promoted set before its first
  # package transaction. The signed package channel moves a Mac pinned to this
  # legacy release-key signed snapshot to the promoted set on its first update,
  # so this release must never be withdrawn; see
  # docs/apple-silicon-deployment.md.
  bootstrap_release_tag=asahi-packages-784daa3efaecfa81b5b4da888b524e6ec4574d24
  package_repo=maralcbr/omarchy-pkgs
  bootstrap_server="https://github.com/$package_repo/releases/download/$bootstrap_release_tag"
  pacman_conf="${OMARCHY_PACMAN_CONF:-/etc/pacman.conf}"

  actual_fingerprint=$(gpg --batch --show-keys --with-colons "$release_key" |
    awk -F: '$1 == "pub" { primary=1; next } primary && $1 == "fpr" { print $10; exit }')
  [[ $actual_fingerprint == "$release_fingerprint" ]] || return 1

  omarchy_blocks=$(grep -Ec '^[[:space:]]*\[omarchy\][[:space:]]*$' "$pacman_conf" || true)
  if (( omarchy_blocks > 1 )); then
    echo "Several [omarchy] sections in $pacman_conf; resolve them before reconfiguring the repository" >&2
    return 1
  fi

  # Whatever else the section needs repaired, a Server the package channel
  # recognises is kept: the channel moves it forward from there, and rewriting
  # it would pin a Mac that has already moved back to the bootstrap set.
  current_servers=$(awk '
    /^[[:space:]]*\[omarchy\][[:space:]]*$/ { inside = 1; next }
    inside && /^[[:space:]]*\[[^]]+\][[:space:]]*$/ { inside = 0 }
    inside && /^[[:space:]]*Server[[:space:]]*=/ {
      sub(/^[[:space:]]*Server[[:space:]]*=[[:space:]]*/, "")
      sub(/[[:space:]]+$/, "")
      print
    }
  ' "$pacman_conf")
  current_server=""
  if [[ -n $current_servers ]]; then
    distinct_servers=$(sort -u <<<"$current_servers")
    if (( $(wc -l <<<"$distinct_servers") > 1 )); then
      echo "Several [omarchy] Servers in $pacman_conf; resolve them before reconfiguring the repository" >&2
      while IFS= read -r duplicate_server; do
        printf '  %s\n' "$duplicate_server" >&2
      done <<<"$distinct_servers"
      return 1
    fi
    current_server=$distinct_servers
  fi

  # Only once the configuration is known to be repairable: a refusal above must leave
  # the keyring untouched.
  if ! pacman-key --finger "$release_fingerprint" >/dev/null 2>&1; then
    pacman-key --add "$release_key"
  fi
  pacman-key --lsign-key "$release_fingerprint"

  stable_prefix="https://github.com/$package_repo/releases/download/asahi-packages-stable-"
  legacy_prefix="https://github.com/$package_repo/releases/download/asahi-packages-"
  release_server=$bootstrap_server
  if [[ $current_server == "$stable_prefix"* && ${current_server#"$stable_prefix"} =~ ^[0-9a-f]{40}$ ]]; then
    release_server=$current_server
  elif [[ $current_server == "$legacy_prefix"* && ${current_server#"$legacy_prefix"} =~ ^[0-9a-f]{40}$ ]]; then
    release_server=$current_server
  elif [[ -n ${OMARCHY_ASAHI_KEEP_SERVER:-} && $current_server == "$OMARCHY_ASAHI_KEEP_SERVER" ]]; then
    # The fresh installer verified the package channel and kept this Server
    # before its first package transaction: a candidate or mirror the operator
    # pinned, or the promoted set it chose.
    release_server=$current_server
  fi

  if ! awk -v server="$release_server" '
    /^[[:space:]]*\[omarchy\][[:space:]]*$/ { inside = 1; blocks++; next }
    inside && /^[[:space:]]*\[[^]]+\][[:space:]]*$/ { inside = 0 }
    inside && /^[[:space:]]*[^#[:space:]]/ { entries++ }
    inside && $0 == "SigLevel = Required DatabaseOptional" { signature = 1 }
    inside && $0 == "Server = " server { url = 1 }
    END { exit !(blocks == 1 && entries == 2 && signature && url) }
  ' "$pacman_conf"; then
    tmp="${pacman_conf}.omarchy.$$"
    # The section is rewritten where it stands, keeping its comments. A missing
    # one goes before the first repository, never after [aur]: below [extra]
    # it would hand Hyprland back to Arch Linux ARM.
    awk -v server="$release_server" -v insert="$(( omarchy_blocks == 0 ))" '
      function section() { return $0 ~ /^[[:space:]]*\[[^]]+\][[:space:]]*$/ }
      function emit() {
        print "[omarchy]"
        print "SigLevel = Required DatabaseOptional"
        print "Server = " server
      }
      section() { inside = 0 }
      /^[[:space:]]*\[omarchy\][[:space:]]*$/ { inside = 1; emit(); next }
      insert && !placed && section() && !/^[[:space:]]*\[options\][[:space:]]*$/ { emit(); print ""; placed = 1 }
      inside && /^[[:space:]]*[^#[:space:]]/ { next }
      { print }
      END { if (insert && !placed) { print ""; emit() } }
    ' "$pacman_conf" >"$tmp"
    chmod --reference="$pacman_conf" "$tmp"
    chown --reference="$pacman_conf" "$tmp"
    mv "$tmp" "$pacman_conf"
    if [[ $current_server != "$release_server" ]]; then
      # A GitHub release serves every tag's database under the same name
      # (omarchy.db), and their upload times are not ordered by tag, so when the
      # repository is repointed to a tag whose asset is older than the cached one
      # pacman keeps the stale database while fetching the new tag's signature and
      # rejects the pair as an invalid signature. Drop the cached database so it
      # and its signature are always fetched together for the tag now pinned.
      db_path=$(awk -F= '/^[[:space:]]*DBPath[[:space:]]*=/ { gsub(/[[:space:]]/, "", $2); print $2 }' "$pacman_conf")
      rm -f "${db_path:-/var/lib/pacman}/sync/omarchy.db" "${db_path:-/var/lib/pacman}/sync/omarchy.db.sig"
    fi
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
