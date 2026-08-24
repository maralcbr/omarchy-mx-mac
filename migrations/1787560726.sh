echo "Configure the signed Omarchy package repository on Apple Silicon"

omarchy-hw-apple-silicon || exit 0

sudo env OMARCHY_PATH="$OMARCHY_PATH" \
  bash -euo pipefail -c 'source "$1"' _ "$OMARCHY_PATH/install/hardware/pacman.sh"
