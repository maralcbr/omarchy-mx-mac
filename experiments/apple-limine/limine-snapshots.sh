#!/bin/bash
# Regenerate the ESP's limine.conf from the template with a Snapshots submenu
# built from snapper's list (newest five, same kernel copy, the snapshot's
# subvolume as root; the initrd overlay unit makes that root writable).
set -euo pipefail
esp=/boot/efi
here=$(dirname "$(readlink -f "$0")")
root_uuid=$(findmnt -no UUID /)
cmdline=$(sed -n 's/^GRUB_CMDLINE_LINUX=\"\(.*\)\"$/\1/p' /etc/default/grub | tail -n1)
cmdline_default=$(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"$/\1/p' /etc/default/grub | tail -n1)
base="root=UUID=$root_uuid rw zswap.enabled=0 rootfstype=btrfs $cmdline_default"
common_flags=$(printf '%s\n' $cmdline | grep -v '^rootflags=' | tr '\n' ' ')
{
  sed -e "s|@@CMDLINE@@|rootflags=subvol=@ $common_flags $base|" "$here/limine.conf"
  printf '\n/Snapshots\n'
  sudo snapper --csvout list --columns number,date,description 2>/dev/null | tail -n +2 |
    awk -F, '$1 != 0' | sort -t, -k1,1nr | head -n 5 |
    while IFS=, read -r number date description; do
      printf '//%s  %s  %s\n' "${date%:*}" "#$number" "$description"
      printf '    protocol: linux\n    path: boot():/omarchy/vmlinuz-linux-aurora\n    module_path: boot():/omarchy/initramfs-linux-aurora.img\n'
      printf '    cmdline: rootflags=subvol=@/.snapshots/%s/snapshot %s %s\n' "$number" "$common_flags" "$base"
    done
} | sudo tee "$esp/limine/limine.conf" >/dev/null
sudo grep -c "^//" "$esp/limine/limine.conf"
