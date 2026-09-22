echo "Limine boot on Apple Silicon"

# Macs installed from a Limine image activate Limine at first boot through
# install/hardware/apple/limine-boot.sh; Macs installed before it get the
# packages, the gate and the same leaf here. The U-Boot slot changes only
# once the Limine menu is verified to boot the kernel; until then GRUB boots.

omarchy-hw-apple-silicon || exit 0

leaf="$OMARCHY_PATH/install/hardware/apple/limine-boot.sh"
[[ -f $leaf ]] || exit 0

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

sudo install -d -m 0755 /var/lib/omarchy
sudo touch /var/lib/omarchy/limine.enabled

bash -euo pipefail -c 'source "$1"' _ "$leaf" || {
  echo "The Limine migration did not finish; it will retry later." >&2
  exit 1
}
sudo omarchy-mac-limine-active || {
  echo "Limine was not activated; the Limine migration will retry later." >&2
  exit 1
}
