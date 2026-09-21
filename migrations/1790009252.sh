echo "Install grub-btrfs for bootable snapshots on Apple Silicon"

# grub-btrfs joined the Apple Silicon default package set for fresh installs;
# Macs installed earlier get it here, then the GRUB snapshot menu is written
# for whatever snapper already holds.

omarchy-hw-apple-silicon || exit 0

omarchy-pkg-add grub-btrfs || {
  echo "grub-btrfs did not install; the snapshot menu migration will retry later." >&2
  exit 1
}

sudo omarchy-mac-snapshot-menu refresh || {
  echo "The GRUB snapshot menu could not be written; the migration will retry later." >&2
  exit 1
}
