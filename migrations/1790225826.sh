echo "Remove the Apple Silicon speaker DSP overlay that can stop WirePlumber from starting"

# Migration 1788345489 installed a software-dsp.lua overlay, machine-wide under
# /usr/local and per user under ~/.local, to keep the asahi-audio convolver from
# pausing between streams. On a 13" MacBook Pro (J293) it leaves WirePlumber
# spinning at startup: the speaker filter chain never loads, there are no sinks
# and no sound (#173). WirePlumber's own node/software-dsp.lua takes over once
# the overlay is gone. The no-suspend drop-in stays; it keeps the amps powered.
#
# Only a copy byte-identical to one Omarchy shipped is removed. A copy the user
# edited is theirs, so it stays with a note.

omarchy-hw-apple-silicon || exit 0

sys_dsp="${OMARCHY_ASAHI_SPEAKER_DSP:-/usr/local/share/wireplumber/scripts/node/software-dsp.lua}"
user_dsp="$HOME/.local/share/wireplumber/scripts/node/software-dsp.lua"

# sha256 of every software-dsp.lua Omarchy shipped (PR #83 and its first draft).
shipped_sha256=(
  8efba1386a99fb257b1da1092cee6b8891b60d94f12de04b58bb5fbf79f79b0a
  173f85a91b7aaf60f7c4e64132e69827230793a79049aaa2843ec110141d152c
)

shipped_overlay() {
  local sum known

  sum=$(sha256sum <"$1" 2>/dev/null) || return 1
  sum=${sum%% *}
  for known in "${shipped_sha256[@]}"; do
    [[ $sum == "$known" ]] && return 0
  done
  return 1
}

# Removes the overlay's directories bottom-up, only while they are empty.
prune_empty_dirs() {
  local dir="$1" stop="$2" as_root="$3"

  while [[ $dir != "$stop" && $dir == "$stop"/* ]]; do
    if [[ $as_root == 1 ]]; then
      sudo rmdir "$dir" 2>/dev/null || break
    else
      rmdir "$dir" 2>/dev/null || break
    fi
    dir=$(dirname "$dir")
  done
}

removed=0

if [[ -f $sys_dsp && ! -L $sys_dsp ]]; then
  if shipped_overlay "$sys_dsp"; then
    sudo rm -f "$sys_dsp"
    prune_empty_dirs "$(dirname "$sys_dsp")" "${sys_dsp%/wireplumber/scripts/node/software-dsp.lua}" 1
    removed=1
  else
    echo "Leaving $sys_dsp in place: it differs from the overlay Omarchy shipped. Remove it if WirePlumber hangs."
  fi
fi

if [[ -f $user_dsp && ! -L $user_dsp ]]; then
  if shipped_overlay "$user_dsp"; then
    rm -f "$user_dsp"
    prune_empty_dirs "$(dirname "$user_dsp")" "$HOME/.local/share" 0
    removed=1
  else
    echo "Leaving $user_dsp in place: it differs from the overlay Omarchy shipped. Remove it if WirePlumber hangs."
  fi
fi

(( removed )) || exit 0

# WirePlumber only reads scripts at startup, so restart it to load the stock
# script now instead of at the next login. A WirePlumber stuck on the overlay
# ignores SIGTERM, so a restart that does not finish in time is followed by a
# SIGKILL and a second restart; every call is bounded so the update never waits
# on a hung service. Without a user session this does nothing, and a failed
# restart is not a failed migration: the overlay is gone and the next login
# starts WirePlumber without it.
wait_seconds="${OMARCHY_WIREPLUMBER_RESTART_TIMEOUT:-15}"

user_systemctl() {
  timeout "$wait_seconds" systemctl --user "$@" >/dev/null 2>&1
}

user_systemctl is-active --quiet wireplumber.service || exit 0

if ! user_systemctl try-restart wireplumber.service; then
  user_systemctl kill --signal=KILL wireplumber.service || true
  user_systemctl restart wireplumber.service || true
  user_systemctl is-active --quiet wireplumber.service ||
    echo "WirePlumber did not restart; log out and back in to restore audio."
fi

exit 0
