# Snapper keeps its snapshots in a /.snapshots subvolume nested under @. The
# Mac image ships the snapper configuration but not that subvolume: the image
# copy flattens nested subvolumes into plain directories, and @factory is a
# snapshot of @ that would carry the same stub. This step runs on the Mac at
# first boot (deferred from the image build) and on a direct install.
omarchy-hw-apple-silicon || return 0
[[ ${OMARCHY_MAC_IMAGE_BUILD:-} != 1 ]] || return 0

snapshots_dir=${OMARCHY_SNAPSHOTS_DIR:-/.snapshots}
[[ $(findmnt -no FSTYPE "${OMARCHY_SNAPSHOTS_ROOT:-/}" 2>/dev/null) == btrfs ]] || return 0

if sudo btrfs subvolume show "$snapshots_dir" >/dev/null 2>&1; then
  return 0
fi

echo "Detected Apple Silicon Mac: creating the /.snapshots subvolume for snapper"

if [[ -d $snapshots_dir ]]; then
  # A plain directory is the flattened stub and must be empty; anything else
  # is not ours to remove.
  if ! sudo rmdir "$snapshots_dir"; then
    echo "$snapshots_dir is a plain directory with contents; leaving it for the owner to inspect" >&2
    return 1
  fi
fi
sudo btrfs subvolume create "$snapshots_dir" >/dev/null
sudo chmod 750 "$snapshots_dir"
