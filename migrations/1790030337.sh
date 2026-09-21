echo "Readable GRUB font and unbounded root wait on Apple Silicon"

# install/hardware/apple/grub-console.sh runs at first boot for new image
# installs; Macs installed before it get the same through this migration.

omarchy-hw-apple-silicon || exit 0

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
leaf="$OMARCHY_PATH/install/hardware/apple/grub-console.sh"
[[ -f $leaf ]] || exit 0

bash -euo pipefail -c 'source "$1"' _ "$leaf" || {
  echo "The GRUB console migration did not finish; it will retry later." >&2
  exit 1
}
