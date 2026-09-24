echo "Limine boot on Apple Silicon"

# Macs installed before Limine get it through omarchy-mac-limine-enable. It
# never fails the migration: a Mac that is not ready yet keeps GRUB, the
# migrations after this one run, and omarchy update retries the activation.

omarchy-hw-apple-silicon || exit 0
omarchy-mac-limine-enable || echo "The Limine activation stopped; omarchy update tries again." >&2
