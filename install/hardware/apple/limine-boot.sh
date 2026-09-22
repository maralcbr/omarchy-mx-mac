# Limine in front of U-Boot on Apple Silicon: the x86 Omarchy boot experience.
#
# U-Boot (the Mac's UEFI) boots ESP:/EFI/BOOT/BOOTAA64.EFI. This leaf puts
# Limine there and keeps GRUB beside it as a recovery entry: the Asahi
# update-grub is retargeted so kernel updates keep regenerating GRUB into
# grub-aa64.efi instead of over Limine. Limine's configuration is Omarchy's
# (an ESP at /boot/efi, the kernel command line derived from GRUB's defaults
# by omarchy-mac-limine-cmdline before every rebuild), and the x86 tooling
# does the rest: limine-update builds the UKI with the aarch64 systemd-stub
# and writes the entries, limine-snapper-sync the snapshot entries. Only a
# menu that already boots the kernel replaces GRUB in the U-Boot slot; a
# pacman hook keeps the ESP's Limine current, since the limine package's own
# hook deploys nothing on aarch64. Opt-in: Macs carrying
# /var/lib/omarchy/limine.enabled. Every step is idempotent.
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
boot_hooks_dir=${OMARCHY_LIMINE_BOOT_HOOKS_DIR:-/etc/boot/hooks/pre.d}
pacman_hooks_dir=${OMARCHY_PACMAN_HOOKS_DIR:-/etc/pacman.d/hooks}
unit_src=${OMARCHY_PROVISIONING_UNIT_SRC:-${OMARCHY_PATH:-/usr/share/omarchy}/install/provisioning}
systemd_dir=${OMARCHY_SYSTEMD_DIR:-/etc/systemd/system}
recovery=$esp/EFI/BOOT/grub-aa64.efi
kernel=$(omarchy-hw-apple-kernel)

if [[ ! -f $limine_efi ]]; then
  echo "limine is not installed; leaving GRUB in place" >&2
  return 0
fi
[[ -f $grub_default ]] || { echo "No $grub_default; cannot derive the kernel command line" >&2; return 0; }
findmnt -no TARGET "$esp" >/dev/null 2>&1 || { echo "The ESP is not mounted at $esp; leaving GRUB in place" >&2; return 0; }

# A failed activation puts everything back: GRUB's update target (and a
# regeneration into the U-Boot slot when it was retargeted here) and the
# Limine defaults this run created, so the Mac does not count as a Limine
# Mac while GRUB still boots it.
limine_boot_fail() {
  echo "limine-boot: $*; GRUB stays the boot loader" >&2
  if (( update_grub_default_changed )); then
    if [[ -n $update_grub_default_before ]]; then
      printf '%s\n' "$update_grub_default_before" | sudo tee "$update_grub_default" >/dev/null
    else
      sudo rm -f "$update_grub_default"
    fi
    sudo "${OMARCHY_UPDATE_GRUB:-update-grub}" >/dev/null 2>&1 || echo "limine-boot: update-grub failed while restoring GRUB's target" >&2
  fi
  (( limine_default_created )) && sudo rm -f "$limine_default"
  return 1
}
limine_default_created=0
update_grub_default_changed=0
update_grub_default_before=""

# 1. GRUB keeps regenerating, into the recovery slot; produced now by GRUB
# itself, never copied from whatever sits in the U-Boot slot.
sudo mkdir -p "$backup_dir" "$esp/EFI/BOOT"
if ! grep -Fxq "TARGET=\"$recovery\"" "$update_grub_default" 2>/dev/null; then
  [[ ! -f $update_grub_default ]] || update_grub_default_before=$(<"$update_grub_default")
  update_grub_default_changed=1
  printf '# Written by Omarchy: Limine owns BOOTAA64.EFI; GRUB stays available as a recovery entry.\nTARGET="%s"\n' "$recovery" |
    sudo tee "$update_grub_default" >/dev/null
fi
sudo "${OMARCHY_UPDATE_GRUB:-update-grub}" >/dev/null || { limine_boot_fail "update-grub could not write the GRUB recovery image"; return 0; }
sudo test -f "$recovery" || { limine_boot_fail "update-grub wrote no $recovery"; return 0; }
sudo cp "$recovery" "$backup_dir/grub-aa64.efi"

# 2. Limine's configuration: the static keys here, the kernel command line
# from GRUB's defaults, re-derived before every UKI rebuild.
[[ -f $limine_default ]] || limine_default_created=1
sudo tee "$limine_default" >/dev/null <<CONF
# Written by Omarchy (install/hardware/apple/limine-boot.sh). KERNEL_CMDLINE
# is derived from /etc/default/grub by omarchy-mac-limine-cmdline; edit GRUB's
# defaults, not this line.
ESP_PATH="$esp"
TARGET_OS_NAME="Omarchy"
ENABLE_UKI=yes
CUSTOM_UKI_NAME="omarchy"
FIND_BOOTLOADERS=no
BOOT_ORDER="$kernel, *, *fallback, Snapshots"
KERNEL_CMDLINE[default]=""
CONF
sudo install -d "$boot_hooks_dir"
sudo ln -sfn "$(command -v omarchy-mac-limine-cmdline)" "$boot_hooks_dir/20-omarchy-mac-cmdline"
sudo omarchy-mac-limine-cmdline || { limine_boot_fail "could not derive the kernel command line"; return 0; }
sudo grep -q '^KERNEL_CMDLINE\[default\]="root=UUID=' "$limine_default" || { limine_boot_fail "no root= in the derived command line"; return 0; }

# 3. Omarchy's Limine menu: the template once, then 3 s like x86.
if ! sudo grep -Fq 'interface_branding: Omarchy Bootloader' "$esp/limine.conf" 2>/dev/null; then
  sudo install -m600 "$limine_conf_source" "$esp/limine.conf"
fi
sudo sed -i -E 's/^#?[[:space:]]*timeout:.*/timeout: 3/' "$esp/limine.conf"
sudo grep -Eq '^timeout: ' "$esp/limine.conf" || printf 'timeout: 3\n' | sudo tee -a "$esp/limine.conf" >/dev/null

# 4. UKI and entries, before anything replaces GRUB: only a menu that boots
# the kernel unattended earns the U-Boot slot.
echo "Building the Omarchy UKI and Limine entries"
sudo limine-update || { limine_boot_fail "limine-update failed"; return 0; }
sudo test -f "$esp/EFI/Linux/omarchy_$kernel.efi" || { limine_boot_fail "limine-update built no $esp/EFI/Linux/omarchy_$kernel.efi"; return 0; }
sudo grep -Fq "//$kernel" "$esp/limine.conf" || { limine_boot_fail "limine.conf has no $kernel entry"; return 0; }

# 5. GRUB stays reachable from the menu, after the Omarchy block: with the
# tool's expanded /+Omarchy group first, default_entry 2 is the kernel entry
# (as on x86); a recovery entry placed before it would make the default the
# group header, which Limine cannot boot unattended. Re-placed every run.
limine_menu=$(mktemp)
sudo awk '
  /^\/GRUB \(recovery\)$/ { skip = 1; next }
  skip && /^[[:space:]]/ { next }
  skip && /^[[:space:]]*$/ { next }
  { skip = 0; print }
' "$esp/limine.conf" >"$limine_menu"
printf '\n/GRUB (recovery)\n    protocol: efi_chainload\n    path: boot():/EFI/BOOT/grub-aa64.efi\n' >>"$limine_menu"
sudo install -m600 "$limine_menu" "$esp/limine.conf"
rm -f "$limine_menu"

# 6. Limine as the default EFI application, kept current by a pacman hook.
# From here on the Mac boots Limine: no rollback past this point.
sudo omarchy-mac-limine-deploy || { limine_boot_fail "could not put Limine on the ESP"; return 0; }
update_grub_default_changed=0
limine_default_created=0
sudo install -d "$pacman_hooks_dir"
sudo tee "$pacman_hooks_dir/81-omarchy-mac-limine-deploy.hook" >/dev/null <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Path
Target = usr/share/limine/BOOTAA64.EFI

[Action]
Description = Deploying Limine to the ESP (Apple Silicon)
When = PostTransaction
Exec = /usr/bin/omarchy-mac-limine-deploy
HOOK

# 7. Snapshot entries as on x86, and the /boot resync after a Limine restore.
sudo limine-snapper-sync || echo "limine-snapper-sync did not finish; snapshot entries come with the next snapshot" >&2
sudo systemctl enable --now limine-snapper-sync.service >/dev/null 2>&1 || true
sudo install -d "$systemd_dir" && sudo install -m644 "$unit_src/omarchy-mac-boot-sync.service" "$systemd_dir/omarchy-mac-boot-sync.service"
sudo systemctl enable omarchy-mac-boot-sync.service >/dev/null 2>&1 || true

# Leftovers of the hand experiment would shadow the real configuration.
sudo rm -rf "$esp/limine" "$esp/omarchy"
