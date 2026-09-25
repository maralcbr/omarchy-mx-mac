echo "Put media keys first on the Apple Silicon keyboard, as in macOS"

# install/hardware/fix-fkeys.sh wrote "options hid_apple fnmode=2" on every
# machine, Macs included, so a Mac's top row sent F1-F12 and mute, volume and
# brightness needed Fn (#235). Apple Silicon now gets fnmode=3 (auto): media
# keys first on Apple keyboards, F-keys first on the non-Apple boards
# hid_apple recognises. Only the exact line the leaf wrote is replaced; any
# other hid_apple.conf is the owner's choice and stays.
# See docs/apple-silicon-keyboard.md.

omarchy-hw-apple-silicon || exit 0

conf=${OMARCHY_HID_APPLE_CONF:-/etc/modprobe.d/hid_apple.conf}
fnmode_param=${OMARCHY_HID_APPLE_FNMODE:-/sys/module/hid_apple/parameters/fnmode}
stock="options hid_apple fnmode=2"

[[ -f $conf && $(<"$conf") == "$stock" ]] || exit 0

echo "options hid_apple fnmode=3" | sudo tee "$conf" >/dev/null

# hid_apple loads from the initramfs (92-omarchy-mac-hid.conf) and modconf
# copies /etc/modprobe.d into it, so the option reaches the boot only through
# a rebuilt image: the UKI on a Limine Mac, the initramfs GRUB boots
# otherwise. A failed rebuild puts the old line back, so the next run tries
# again instead of finding a file that already looks migrated.
if omarchy-mac-limine-active; then
  rebuild=(omarchy-mac-boot-update)
else
  rebuild=(mkinitcpio -P)
fi
echo "Rebuilding the boot image so the new keyboard mode survives a reboot"
if ! sudo "${rebuild[@]}"; then
  echo "$stock" | sudo tee "$conf" >/dev/null
  echo "Rebuilding the boot image failed; the keyboard mode migration will retry later." >&2
  exit 1
fi

# The parameter is writable at runtime and read on every key press: the top
# row changes now, without a reboot.
if [[ -f $fnmode_param ]]; then
  echo 3 | sudo tee "$fnmode_param" >/dev/null || true
fi
