SNAPPER_CONFIG_PATH="${OMARCHY_SNAPPER_CONFIG_PATH:-/etc/snapper/configs/root}"
SNAPPER_CONF_PATH="${OMARCHY_SNAPPER_CONF_PATH:-/etc/conf.d/snapper}"
template="${OMARCHY_SNAPPER_TEMPLATE:-${OMARCHY_PATH:-/usr/share/omarchy}/default/snapper/root}"

echo "Configuring Omarchy Snapper snapshot retention"

# Snapper snapshots a btrfs root. A root on anything else (the VM acceptance
# guest boots a generic image) gets no config and no timer; installs on real
# Omarchy layouts are always btrfs.
root_fstype=$(findmnt -no FSTYPE / 2>/dev/null || true)
if [[ ${OMARCHY_SNAPPER_CONFIGURE_TEST:-0} != "1" && ${OMARCHY_MAC_IMAGE_BUILD:-} != 1 && $root_fstype != btrfs ]]; then
  echo "The root is ${root_fstype:-unknown}, not btrfs; skipping Snapper configuration"
  exit 0
fi

if [[ ! -f $SNAPPER_CONFIG_PATH ]]; then
  mkdir -p "$(dirname "$SNAPPER_CONFIG_PATH")"

  # An image build's / is the sealed root: create-config would nest a
  # /.snapshots subvolume the image copy flattens. The first-boot step
  # install/hardware/apple/snapshots-subvolume.sh creates it on the Mac.
  if [[ ${OMARCHY_SNAPPER_CONFIGURE_TEST:-0} == "1" || ${OMARCHY_MAC_IMAGE_BUILD:-} == 1 ]]; then
    : >"$SNAPPER_CONFIG_PATH"
  else
    snapper --no-dbus -c root create-config / >/dev/null 2>&1 || snapper -c root create-config / >/dev/null
  fi
fi

install -m 0644 "$template" "$SNAPPER_CONFIG_PATH"

mkdir -p "$(dirname "$SNAPPER_CONF_PATH")"
printf '%s\n' 'SNAPPER_CONFIGS="root"' >"$SNAPPER_CONF_PATH"
chmod 0644 "$SNAPPER_CONF_PATH"

systemctl disable --now snapper-timeline.timer >/dev/null 2>&1 || true
if command -v omarchy-hw-apple-silicon >/dev/null 2>&1 && omarchy-hw-apple-silicon; then
  # Apple Silicon boots GRUB: no Limine menu to sync.
  systemctl enable --now snapper-cleanup.timer >/dev/null 2>&1 || true
else
  systemctl enable --now snapper-cleanup.timer limine-snapper-sync.service >/dev/null 2>&1 || true
fi
