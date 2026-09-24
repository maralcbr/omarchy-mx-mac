echo "Install Tensaku so the screenshot Edit action opens an editor"

# Macs set up before tensaku was built for aarch64 had 1781286586.sh marked done
# at first boot, so the screenshot notification's Edit action had no editor to
# open. Install it where it is missing and the package repositories carry it.

omarchy-hw-apple-silicon || exit 0
omarchy-pkg-present tensaku && exit 0
omarchy-pkg-available tensaku || exit 0

omarchy-pkg-add tensaku || {
  echo "tensaku did not install; the Tensaku migration will retry later." >&2
  exit 1
}
