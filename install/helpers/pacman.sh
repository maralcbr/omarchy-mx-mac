# Pacman repository configuration for channel changes and install finalization.
# Sourcing this file only defines functions; it never changes the system.

omarchy_pacman_validate_channel() {
  case ${1:-} in
    stable | rc | edge) return 0 ;;
    *)
      echo "Error: Invalid channel '${1:-}'. Must be one of: stable, rc, edge" >&2
      return 1
      ;;
  esac
}

# The channels whose packages are qualified on a platform: a signed upgrade and
# a reboot have been tested there, not only a repository published. Omarchy
# publishes stable and rc for x86_64 alone. Apple Silicon gets edge once the
# Mac packages pass that qualification on it; until then a Mac keeps the
# repositories its image came with.
omarchy_pacman_qualified_channels() {
  case ${1:-} in
    generic) echo "stable rc edge" ;;
    qualcomm | generic-aarch64) echo "edge" ;;
    apple-silicon) echo "" ;;
    *) return 1 ;;
  esac
}

omarchy_pacman_channel_qualified() {
  local channel=$1 platform=$2 qualified

  omarchy_pacman_validate_channel "$channel" || return 1
  if ! qualified=$(omarchy_pacman_qualified_channels "$platform"); then
    echo "Error: Unknown platform '$platform'. No repository configuration changed." >&2
    return 1
  fi
  [[ " $qualified " != *" $channel "* ]] || return 0
  echo "Omarchy $channel packages are not qualified for $platform yet. No repository configuration changed." >&2
  echo "Channels for this machine: ${qualified:-none yet}" >&2
  return 1
}

# The Omarchy channel this machine's configuration names: its [omarchy]
# repository's one server on pkgs.omarchy.org. Fails, printing nothing, when
# there is no such repository or its servers name no single channel.
omarchy_pacman_configured_channel() {
  local servers
  servers=$(pacman-conf --repo omarchy Server 2>/dev/null) || return 1
  [[ $servers =~ ^https://pkgs\.omarchy\.org/(stable|rc|edge)/[^/[:space:]]+$ ]] || return 1
  echo "${BASH_REMATCH[1]}"
}

# Install finalization on a channel not qualified for Snapdragon or another
# aarch64 machine leaves it no Omarchy repository (see
# omarchy_pacman_write_template), so Omarchy itself never updates there. Says
# so, and how to fix it, when <config> names no Omarchy repository on one of
# those platforms; prints nothing otherwise, x86_64 and Apple Silicon included,
# or when it can't tell. The platform is looked up only once the repository is
# found missing.
omarchy_pacman_missing_repository_notice() {
  local config=$1 platform=${2:-} repos

  repos=$(pacman-conf --config "$config" --repo-list 2>/dev/null) || return 0
  ! grep -qx omarchy <<<"$repos" || return 0
  [[ -n $platform ]] || platform=$(omarchy-hw-platform 2>/dev/null) || return 0
  [[ $platform == "qualcomm" || $platform == "generic-aarch64" ]] || return 0
  echo "This machine has no Omarchy repository, so its Omarchy packages get no updates. Switch to edge with: omarchy-channel-set edge"
}

# An aarch64 machine's repositories are its own: Arch Linux ARM and a
# platform's repositories, inline servers or a mirrorlist, each with its
# signature policy. A channel change keeps all of it and rewrites only the
# Omarchy repository's server, printing the result, and refuses a configuration
# it can't read that way. Where there is no Omarchy repository (install
# finalization leaves none on a channel it can't use), one is added at the end,
# except on Apple Silicon, whose own repository must not come before it.
omarchy_pacman_swap_channel() {
  local channel=$1 platform=$2 source=$3 config status=0

  omarchy_pacman_validate_channel "$channel" || return 1
  # The dot keeps the file's trailing newlines through the substitution. A file
  # that isn't there or can't be read fails (4, or gawk's 2), never taken for
  # one with no Omarchy repository (3).
  config=$(
    [[ -f $source ]] && exec <"$source" || exit 4
    awk -v channel="$channel" '
    /^[[:space:]]*\[/ {
      omarchy = ($0 ~ /^[[:space:]]*\[omarchy\][[:space:]]*$/)
      sections += omarchy
    }
    omarchy && /^[[:space:]]*(Server|Include)[[:space:]]*=/ {
      if ($0 ~ /^[[:space:]]*Server[[:space:]]*=[[:space:]]*https:\/\/pkgs\.omarchy\.org\/(stable|rc|edge)\/(\$arch|aarch64)[[:space:]]*$/) {
        sub(/\/(stable|rc|edge)\//, "/" channel "/")
        found++
      } else {
        unknown = 1
      }
    }
    { print }
    END {
      if (sections == 0) exit 3
      if (sections != 1 || found != 1 || unknown) exit 1
    }
  '
    status=$?
    printf .
    exit "$status"
  ) || status=$?
  config=${config%.}

  if (( status != 0 && status != 1 && status != 3 )); then
    echo "Error: Cannot read $source; configuration unchanged." >&2
    return 1
  fi
  if (( status == 3 )) && [[ $platform == "apple-silicon" ]]; then
    echo "Error: $source has no Omarchy repository, and on Apple Silicon one can't be added after the Mac's own; configuration unchanged." >&2
    return 1
  fi
  if (( status == 3 )); then
    config+=$'\n[omarchy]\nServer = https://pkgs.omarchy.org/'"$channel"$'/$arch\n'
    # An included file may define repositories too: the result must name
    # Omarchy's once.
    if [[ $(pacman-conf --config <(printf '%s' "$config") --repo-list 2>/dev/null | grep -cx omarchy) == 1 ]]; then
      status=0
    fi
  fi
  if (( status != 0 )); then
    echo "Error: Cannot identify the Omarchy channel in $source; configuration unchanged." >&2
    return 1
  fi
  printf '%s' "$config"
}

# Before a channel change touches /etc, check that the channel's Omarchy
# repository publishes what this machine runs: the runtime pair, and on Apple
# Silicon the Mac's own packages. It reads the repository's package list as
# the user and changes nothing.
omarchy_pacman_preflight() {
  local channel=$1 platform=$2 listing package
  local -a packages=(omarchy omarchy-settings)
  local -
  set -o pipefail

  [[ $channel != "edge" ]] || packages=(omarchy-dev omarchy-settings-dev)
  [[ $platform != "apple-silicon" ]] || packages+=(omarchy-mac omarchy-mac-boot)

  if ! listing=$(curl -fsSL --retry 2 "https://pkgs.omarchy.org/$channel/aarch64/omarchy.db" | bsdtar -tf -); then
    echo "Error: Cannot read Omarchy $channel's package list. No repository configuration changed." >&2
    return 1
  fi
  for package in "${packages[@]}"; do
    if ! grep -qx -- "$package-[^-/]*-[^-/]*/desc" <<<"$listing"; then
      echo "Error: Omarchy $channel does not publish $package for this machine. No repository configuration changed." >&2
      return 1
    fi
  done
}

# Install finalization replaces the offline repositories with the platform's
# online ones, so a template decides the whole file here. x86_64 gets the
# channel's template. Other aarch64 platforms get Arch Linux ARM, plus Omarchy
# when the channel is qualified for them. Apple Silicon gets omarchy-mac's
# template, which carries the Mac's own repository; for a channel not
# qualified there it keeps the configuration its image came with.
omarchy_pacman_write_template() {
  local channel=$1 platform=$2 config=$3 mirrorlist=$4
  local defaults="$OMARCHY_PATH/default/pacman" templates=/usr/share/omarchy-mac/pacman

  omarchy_pacman_validate_channel "$channel" || return 1
  # Root takes no path from its environment; tests stage the templates.
  (( EUID == 0 )) || templates=${OMARCHY_MAC_PACMAN_TEMPLATES:-$templates}

  case $platform in
    generic)
      cp -f "$defaults/pacman-$channel.conf" "$config" || return 1
      cp -f "$defaults/mirrorlist-$channel" "$mirrorlist" || return 1
      ;;
    qualcomm | generic-aarch64)
      cp -f "$defaults/pacman-aarch64.conf" "$config" || return 1
      cp -f "$defaults/mirrorlist-aarch64" "$mirrorlist" || return 1
      if omarchy_pacman_channel_qualified "$channel" "$platform" 2>/dev/null; then
        printf '\n[omarchy]\nServer = https://pkgs.omarchy.org/%s/$arch\n' "$channel" >>"$config" || return 1
      else
        echo "Omarchy $channel is not qualified for $platform yet, so this machine gets no Omarchy repository; omarchy-channel-set edge adds one."
      fi
      ;;
    apple-silicon)
      if ! omarchy_pacman_channel_qualified "$channel" "$platform" 2>/dev/null; then
        echo "Omarchy $channel is not qualified for Apple Silicon yet; keeping this Mac's repositories."
        return 0
      fi
      if [[ ! -f $templates/pacman-$channel.conf ]]; then
        echo "Error: $templates/pacman-$channel.conf is missing; omarchy-mac provides it." >&2
        return 1
      fi
      cp -f "$templates/pacman-$channel.conf" "$config" || return 1
      cp -f "$defaults/mirrorlist-aarch64" "$mirrorlist" || return 1
      ;;
    *)
      echo "Error: Unknown platform '$platform'" >&2
      return 1
      ;;
  esac
}
