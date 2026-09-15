echo "Create static device nodes first so an Apple Silicon btrfs root survives boot"

# install/hardware/apple/fix-asahi-btrfs-race.sh runs on new installs only, so
# machines already installed keep dropping into emergency mode on unlucky boots
# until this runs it.
OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
btrfs_race_script="$OMARCHY_PATH/install/hardware/apple/fix-asahi-btrfs-race.sh"
dropin="${OMARCHY_ASAHI_STATIC_NODES_DROPIN:-/etc/systemd/system/kmod-static-nodes.service.d/10-before-tmpfiles-setup-dev.conf}"
ready="${OMARCHY_ASAHI_BTRFS_READY:-/var/lib/omarchy/asahi-btrfs-initramfs-ready}"

[[ -f $btrfs_race_script ]] || exit 0

# The machine-wide marker makes this idempotent across users while still
# distinguishing a written drop-in from a successful initramfs rebuild.
[[ -f $ready ]] && exit 0

# The leaf carries both the hardware gate and the drop-in content; sourcing it
# keeps that to one copy. Anything that is not an Apple Silicon Mac writes
# nothing and falls out below.
[[ -f $dropin ]] || source "$btrfs_race_script"
[[ -f $dropin ]] || exit 0

# The race is inside the initramfs, which only picks the drop-in up when rebuilt.
echo "Rebuilding the initramfs to carry the static device node ordering"
if ! sudo mkinitcpio -P; then
  echo "mkinitcpio failed; the static device node migration will retry later." >&2
  exit 1
fi

omarchy-state set reboot-required
sudo install -Dm644 /dev/null "$ready"
