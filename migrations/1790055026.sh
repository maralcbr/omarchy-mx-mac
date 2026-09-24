echo "Limine boot on Apple Silicon"

# Macs installed from a Limine image activate Limine at first boot through
# install/hardware/apple/limine-boot.sh; Macs installed before it get the
# packages, the gate and the same leaf here. The U-Boot slot changes only
# once the Limine menu is verified to boot the kernel; until then GRUB boots.

omarchy-hw-apple-silicon || exit 0

leaf="$OMARCHY_PATH/install/hardware/apple/limine-boot.sh"
[[ -f $leaf ]] || exit 0
gate=${OMARCHY_LIMINE_GATE:-/var/lib/omarchy/limine.enabled}

# Limine goes on the system ESP, at /boot/efi or, on older installs, /boot. A
# Mac with it anywhere else keeps GRUB: settled here, never a failure that
# would stop every later migration.
if ! omarchy-mac-esp >/dev/null; then
  echo "The system ESP is not mounted at /boot/efi or /boot; this Mac keeps booting GRUB." >&2
  exit 0
fi

# uboot-asahi from [omarchy] (silent console) replaces Asahi's build of the
# same name; limine-mkinitcpio-hook 1.36.0-2 is the first that writes UKI
# entries on aarch64.
sudo pacman -S --needed --noconfirm limine limine-mkinitcpio-hook limine-snapper-sync uboot-asahi || {
  echo "The Limine packages did not install; the Limine migration will retry later." >&2
  exit 1
}
if ! pacman -Q limine-mkinitcpio-hook | awk '{ print $2 }' | grep -Eq '^1\.36\.0-([2-9]|[1-9][0-9]+)$|^1\.3[7-9]|^1\.[4-9]|^[2-9]'; then
  echo "limine-mkinitcpio-hook 1.36.0-2 or newer is not installed; the Limine migration will retry later." >&2
  exit 1
fi

sudo install -d -m 0755 "$(dirname "$gate")"
sudo touch "$gate"

bash -euo pipefail -c 'source "$1"' _ "$leaf" || {
  echo "The Limine migration did not finish; it will retry later." >&2
  exit 1
}
sudo omarchy-mac-limine-active || {
  echo "Limine was not activated; the Limine migration will retry later." >&2
  exit 1
}
# limine-mkinitcpio-hook before 1.36.0-4 took mkinitcpio's own kernel hook
# over, so a kernel updated in between never reached /boot. mkinitcpio's hook
# script installs it again, run from / as pacman runs it.
kernel=$(omarchy-hw-apple-kernel)
mkinitcpio_alpm=${OMARCHY_MKINITCPIO_ALPM:-/usr/share/libalpm/scripts/mkinitcpio}
while IFS= read -r image; do
  sudo cmp -s "$image" "/boot/vmlinuz-$kernel" && continue
  echo "Installing the $kernel kernel under /boot"
  (cd / && printf '%s\n' "${image#/}" | sudo "$mkinitcpio_alpm" install) || {
    echo "The $kernel kernel could not be installed under /boot; the Limine migration will retry later." >&2
    exit 1
  }
done < <(pacman -Qlq "$kernel" | grep -E '^/usr/lib/modules/[^/]+/vmlinuz$')

# The Limine files are what this verifies. A kernel the same update installed
# boots after the reboot; that is not a failed migration.
check=$(sudo env OMARCHY_BOOT_CHECK_ALLOW_PENDING_REBOOT=1 omarchy-apple-silicon-boot-check "$kernel") || {
  echo "The Limine boot files did not verify; the Limine migration will retry later." >&2
  exit 1
}
if [[ $check == *"reboot pending"* ]]; then
  echo "Limine boots this Mac from now on; reboot to start the new kernel."
fi
