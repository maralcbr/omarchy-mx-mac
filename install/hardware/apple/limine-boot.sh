# Limine in front of U-Boot on Apple Silicon: the x86 Omarchy boot experience.
#
# U-Boot (the Mac's UEFI) boots ESP:/EFI/BOOT/BOOTAA64.EFI. This leaf puts
# Limine there, keeps GRUB beside it as a recovery entry (and retargets the
# Asahi update-grub so kernel updates keep regenerating GRUB into that slot
# instead of over Limine), writes Omarchy's Limine configuration for an ESP
# mounted at /boot/efi, and lets the x86 tooling do the rest: limine-update
# builds the UKI with the aarch64 systemd-stub and writes the entries, and
# limine-snapper-sync adds the snapshot entries. Experiment branch: runs on
# lab Macs that opted in with /var/lib/omarchy/limine.enabled.
omarchy-hw-apple-silicon || return 0
[[ ${OMARCHY_MAC_IMAGE_BUILD:-} != 1 ]] || return 0

gate=${OMARCHY_LIMINE_GATE:-/var/lib/omarchy/limine.enabled}
[[ -e $gate ]] || return 0

esp=${OMARCHY_ESP:-/boot/efi}
limine_efi=${OMARCHY_LIMINE_EFI:-/usr/share/limine/BOOTAA64.EFI}
limine_conf_source=${OMARCHY_LIMINE_CONF_SOURCE:-${OMARCHY_PATH:-/usr/share/omarchy}/default/limine/limine.conf}
grub_default=${OMARCHY_GRUB_DEFAULT:-/etc/default/grub}
update_grub_default=${OMARCHY_UPDATE_GRUB_DEFAULT:-/etc/default/update-grub}
limine_default=${OMARCHY_LIMINE_DEFAULT:-/etc/default/limine}
backup_dir=${OMARCHY_GRUB_BACKUP_DIR:-/var/lib/omarchy/backups}
recovery=$esp/EFI/BOOT/grub-aa64.efi

if [[ ! -f $limine_efi ]]; then
  echo "limine is not installed; leaving GRUB in place" >&2
  return 0
fi
[[ -f $grub_default ]] || { echo "No $grub_default; cannot derive the kernel command line" >&2; return 0; }

grub_value() {
  sed -n "s/^$1=//p" "$grub_default" | tail -n 1 | sed -E "s/^\"(.*)\"$/\1/; s/^'(.*)'$/\1/"
}

# 1. GRUB keeps regenerating, into the recovery slot.
sudo mkdir -p "$backup_dir" "$esp/EFI/BOOT"
if ! grep -Fxq "TARGET=\"$recovery\"" "$update_grub_default" 2>/dev/null; then
  printf '# Written by Omarchy: Limine owns BOOTAA64.EFI; GRUB stays available as a recovery entry.\nTARGET="%s"\n' "$recovery" |
    sudo tee "$update_grub_default" >/dev/null
fi

# 2. Limine as the default EFI application, GRUB beside it.
if ! sudo cmp -s "$esp/EFI/BOOT/BOOTAA64.EFI" "$limine_efi"; then
  if [[ -f $esp/EFI/BOOT/BOOTAA64.EFI ]]; then
    [[ -f $backup_dir/grub-aa64.efi ]] || sudo cp "$esp/EFI/BOOT/BOOTAA64.EFI" "$backup_dir/grub-aa64.efi"
    sudo cp "$esp/EFI/BOOT/BOOTAA64.EFI" "$recovery"
  fi
  sudo install -m600 "$limine_efi" "$esp/EFI/BOOT/BOOTAA64.EFI"
fi
[[ -f $recovery ]] || { [[ -f $backup_dir/grub-aa64.efi ]] && sudo cp "$backup_dir/grub-aa64.efi" "$recovery"; }

# 3. The kernel command line GRUB used, whole, for the UKI and the entries.
root_uuid=$(findmnt -no UUID /)
cmdline="root=UUID=$root_uuid rw rootflags=subvol=@ $(grub_value GRUB_CMDLINE_LINUX) $(grub_value GRUB_CMDLINE_LINUX_DEFAULT)"
cmdline=$(printf '%s' "$cmdline" | tr -s ' ')
sudo tee "$limine_default" >/dev/null <<CONF
# Written by Omarchy (install/hardware/apple/limine-boot.sh).
ESP_PATH="$esp"
TARGET_OS_NAME="Omarchy"
ENABLE_UKI=yes
CUSTOM_UKI_NAME="omarchy"
FIND_BOOTLOADERS=no
BOOT_ORDER="linux-aurora, *, *fallback, Snapshots"
KERNEL_CMDLINE[default]="$cmdline"
CONF

# 4. Omarchy's Limine menu with a GRUB recovery entry; 3 s like x86.
if ! sudo grep -Fq 'interface_branding: Omarchy Bootloader' "$esp/limine.conf" 2>/dev/null; then
  sudo install -m600 "$limine_conf_source" "$esp/limine.conf"
fi
sudo sed -i -E 's/^#?timeout: .*/timeout: 3/' "$esp/limine.conf"
sudo grep -Eq '^timeout: ' "$esp/limine.conf" || printf 'timeout: 3\n' | sudo tee -a "$esp/limine.conf" >/dev/null
# Leftovers of the hand experiment would shadow the real configuration.
sudo rm -rf "$esp/limine" "$esp/omarchy"

# 5. UKI, entries, snapshots.
echo "Building the Omarchy UKI and Limine entries"
sudo limine-update
sudo limine-snapper-sync || echo "limine-snapper-sync did not finish; snapshot entries come with the next snapshot" >&2

# 6. GRUB stays reachable from the menu, after the Omarchy block: with the
# tool's expanded /+Omarchy group first, default_entry 2 is the kernel entry
# (as on x86); a recovery entry placed before it would make the default the
# group header, which Limine cannot boot unattended.
if ! sudo grep -Fq '/GRUB (recovery)' "$esp/limine.conf"; then
  printf '\n/GRUB (recovery)\n    protocol: efi_chainload\n    path: boot():/EFI/BOOT/grub-aa64.efi\n' | sudo tee -a "$esp/limine.conf" >/dev/null
fi
