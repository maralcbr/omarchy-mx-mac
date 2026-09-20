# Configure pacman after package installation completes. Apple Silicon keeps
# the Arch Linux ARM and Asahi repositories that own its kernel and firmware.
# Image builds already carry the pinned signed [omarchy] and [omarchy-aurora]
# sections the chroot was built with: do not replace them with the x86 set,
# and do not invent a fake /proc tree for omarchy-hw-apple-silicon.
if [[ ${OMARCHY_MAC_IMAGE_BUILD:-} != 1 ]] && ! omarchy-hw-apple-silicon; then
  cp -f "$OMARCHY_PATH/default/pacman/pacman-${OMARCHY_MIRROR:-stable}.conf" /etc/pacman.conf
  cp -f "$OMARCHY_PATH/default/pacman/mirrorlist-${OMARCHY_MIRROR:-stable}" /etc/pacman.d/mirrorlist
fi

# Wait for CUPS to own the file, the way omarchy-settings does, so pacman does
# not turn the override into a .pacnew during ISO package installation.
if [[ -f $OMARCHY_PATH/etc-overrides/cups-cups-files.conf && -f /etc/cups/cups-files.conf ]]; then
  install -m 0640 -o root -g cups "$OMARCHY_PATH/etc-overrides/cups-cups-files.conf" /etc/cups/cups-files.conf
  rm -f /etc/cups/cups-files.conf.pacnew
fi

source "$OMARCHY_INSTALL/hardware/pacman.sh"
