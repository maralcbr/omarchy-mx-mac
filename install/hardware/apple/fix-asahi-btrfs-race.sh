# systemd 255 moved kmod-static-nodes.service's ordering from
# systemd-tmpfiles-setup-dev.service to systemd-tmpfiles-setup-dev-early.service,
# which mkinitcpio's systemd hook does not ship. In the initramfs the two then
# race: when tmpfiles wins, /dev/btrfs-control is never created, udev cannot
# load btrfs on demand to check the root partition, and the boot times out into
# emergency mode. mkinitcpio copies unit drop-ins from /etc into the image, so
# restoring the old ordering here closes the race on the next rebuild.
omarchy-hw-apple-silicon || return 0

echo "Detected Apple Silicon Mac: creating static device nodes before /dev setup"

sudo mkdir -p /etc/systemd/system/kmod-static-nodes.service.d
sudo tee /etc/systemd/system/kmod-static-nodes.service.d/10-before-tmpfiles-setup-dev.conf >/dev/null <<'EOF'
[Unit]
Before=systemd-tmpfiles-setup-dev.service
EOF
