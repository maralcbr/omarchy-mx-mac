#!/bin/bash
# Experiment: put Limine in front of U-Boot on this Mac's ESP, keeping GRUB as
# a chainload entry and a byte-identical backup. Run as the owner on the Mac.
#   deploy-m1.sh install   - stage Limine as /EFI/BOOT/BOOTAA64.EFI (GRUB kept as grub-aa64.efi)
#   deploy-m1.sh rollback  - restore GRUB as /EFI/BOOT/BOOTAA64.EFI
set -euo pipefail
esp=/boot/efi
here=$(dirname "$(readlink -f "$0")")
boot_uuid=$(findmnt -no UUID /boot)
root_uuid=$(findmnt -no UUID /)
cmdline=$(sed -n 's/^GRUB_CMDLINE_LINUX=\"\(.*\)\"$/\1/p' /etc/default/grub | tail -n1)
cmdline_default=$(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"$/\1/p' /etc/default/grub | tail -n1)
case ${1:-} in
  install)
    [[ -f /usr/share/limine/BOOTAA64.EFI ]] || { echo "install the limine package first" >&2; exit 1; }
    sudo mkdir -p /var/lib/omarchy/backups "$esp/limine" "$esp/omarchy"
    need=$(( $(stat -c %s /boot/vmlinuz-linux-aurora) + $(stat -c %s /boot/initramfs-linux-aurora.img) ))
    free=$(( $(stat -f -c '%a*%S' "$esp") ))
    (( free > need + 16*1024*1024 )) || { echo "ESP too small for the kernel copies ($free free, $need needed)" >&2; exit 1; }
    sudo cp /boot/vmlinuz-linux-aurora /boot/initramfs-linux-aurora.img "$esp/omarchy/"
    if ! sudo cmp -s "$esp/EFI/BOOT/BOOTAA64.EFI" /usr/share/limine/BOOTAA64.EFI; then
      sudo cp -n "$esp/EFI/BOOT/BOOTAA64.EFI" /var/lib/omarchy/backups/grub-aa64.efi 2>/dev/null || true
      sudo cp "$esp/EFI/BOOT/BOOTAA64.EFI" "$esp/EFI/BOOT/grub-aa64.efi"
    fi
    sed -e "s|@@BOOT_UUID@@|$boot_uuid|g" \
        -e "s|@@CMDLINE@@|root=UUID=$root_uuid rw rootflags=subvol=@ $cmdline $cmdline_default|" \
        "$here/limine.conf" | sudo tee "$esp/limine/limine.conf" >/dev/null
    sudo cp /usr/share/limine/BOOTAA64.EFI "$esp/EFI/BOOT/BOOTAA64.EFI"
    sync
    echo "Limine staged; GRUB kept as $esp/EFI/BOOT/grub-aa64.efi. Reboot to test."
    ;;
  rollback)
    src=$esp/EFI/BOOT/grub-aa64.efi
    [[ -f $src ]] || src=/var/lib/omarchy/backups/grub-aa64.efi
    sudo cp "$src" "$esp/EFI/BOOT/BOOTAA64.EFI"
    sync
    echo "GRUB restored as $esp/EFI/BOOT/BOOTAA64.EFI"
    ;;
  *) echo "usage: $0 install|rollback" >&2; exit 64 ;;
esac
