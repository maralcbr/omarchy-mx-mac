echo "Give aarch64 machines the zram swap omarchy-settings configures"

# omarchy-settings configures swap on zram and tunes reclaim for it. x86_64 gets
# zram-generator from its installer; aarch64 platforms now list it in their
# default packages, so install it where the platform's defaults name it and
# start the swap it configures. Where the platform can't be told, it waits,
# changing nothing (75 leaves it pending without stopping later migrations).
defaults=$(omarchy-pkg-defaults) || exit 75
if grep -qx zram-generator <<<"$defaults"; then
  # A failed install (offline, say) waits for the next migrate, like an
  # undetermined platform.
  if omarchy-pkg-missing zram-generator; then
    omarchy-pkg-add zram-generator || exit 75
  fi
  # Start the swap the generator configures, unless it is up already. With no
  # device configured there is no swap unit, and a masked one is the
  # administrator's choice: nothing to start. A swap that won't start only
  # warns: the generator's unit starts with every boot, so a reboot retries it
  # (after a kernel upgrade, say), and stopping here would stop every update.
  if ! systemctl is-active --quiet dev-zram0.swap; then
    if ! sudo systemctl daemon-reload || ! state=$(systemctl show -P LoadState dev-zram0.swap); then
      echo "Warning: could not read the zram swap unit; it starts with the next boot if it can." >&2
    else
      case $state in
        loaded)
          sudo systemctl start dev-zram0.swap ||
            echo "Warning: the zram swap did not start; it starts with the next boot if it can." >&2
          ;;
        not-found | masked) ;;
        *) echo "Warning: the zram swap unit is $state; fix its configuration, then reboot to start it." >&2 ;;
      esac
    fi
  fi
fi

# Earlier Mac setups copied the drop-in into /etc under the same name. An
# identical copy would only hide the packaged one's updates; a copy that
# differs is the administrator's and stays.
vendor="${OMARCHY_ZRAM_DROPIN_USR:-/usr/lib/systemd/zram-generator.conf.d/90-omarchy.conf}"
copy="${OMARCHY_ZRAM_DROPIN_ETC:-/etc/systemd/zram-generator.conf.d/90-omarchy.conf}"

if [[ -f $vendor && -f $copy && ! -L $copy ]] && cmp -s -- "$vendor" "$copy"; then
  sudo rm -f -- "$copy"
  sudo rmdir --ignore-fail-on-non-empty -- "${copy%/*}"
fi
