echo "Enable snapper update snapshots on Apple Silicon"

# Apple Silicon installs never got snapper: the package was excluded and
# install/config/snapper.sh was skipped, so omarchy-update silently took no
# snapshot. Install it, apply the shared retention policy, and make sure the
# /.snapshots subvolume exists (a Mac image ships the config but not the
# subvolume; snapper's create-config makes it on machines without a config).

omarchy-hw-apple-silicon || exit 0

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

omarchy-pkg-add snapper || {
  echo "snapper did not install; the snapshot migration will retry later." >&2
  exit 1
}

sudo bash -euo pipefail "$OMARCHY_PATH/install/config/snapper.sh"

# The leaf is a sourced installer step: run it in a shell with the installer's
# helpers absent, as omarchy-mac-run-deferred-steps does at first boot.
bash -euo pipefail -c 'source "$1"' _ "$OMARCHY_PATH/install/hardware/apple/snapshots-subvolume.sh"
