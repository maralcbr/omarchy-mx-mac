echo "Omarchy GRUB theme and a splash-only boot on Apple Silicon"

# install/hardware/apple/grub-console.sh gained the themed menu, the efi_gop
# backend, the Plymouth serial-console switch and the 10_linux narration
# guard after its first migration ran; installed Macs run it again here.

omarchy-hw-apple-silicon || exit 0

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
leaf="$OMARCHY_PATH/install/hardware/apple/grub-console.sh"
[[ -f $leaf ]] || exit 0

OMARCHY_PATH="$OMARCHY_PATH" bash -euo pipefail -c 'source "$1"' _ "$leaf" || {
  echo "The GRUB theme migration did not finish; it will retry later." >&2
  exit 1
}
