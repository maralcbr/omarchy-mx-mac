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
pending=${OMARCHY_HID_APPLE_PENDING:-/var/lib/omarchy/migrations/1790305681-boot-image-pending}

if [[ -f $conf && $(<"$conf") == "options hid_apple fnmode=2" ]]; then
  # Record the rebuild obligation before changing the file. It survives a
  # failed rebuild, an interrupted run and a retry by another user.
  sudo install -Dm644 /dev/null "$pending"
  echo "options hid_apple fnmode=3" | sudo tee "$conf" >/dev/null
fi

[[ -f $pending ]] || exit 0

# hid_apple loads from the initramfs (92-omarchy-mac-hid.conf) and modconf
# copies /etc/modprobe.d into it, so the option reaches the boot only through
# a rebuilt image: the UKI on a Limine Mac, the initramfs GRUB boots
# otherwise.
if omarchy-mac-limine-active; then
  rebuild=(omarchy-mac-boot-update)
else
  rebuild=(mkinitcpio -P)
fi
echo "Rebuilding the boot image so the new keyboard mode survives a reboot"
if ! sudo "${rebuild[@]}"; then
  echo "Rebuilding the boot image failed; the keyboard mode migration will retry later." >&2
  exit 1
fi
sudo rm -f -- "$pending"

# The parameter is writable at runtime and read on every key press, so the
# top row changes now; if it cannot be written, the next boot applies it. An
# owner who edited the file while the rebuild was owed keeps their setting.
[[ -f $conf && $(<"$conf") == "options hid_apple fnmode=3" ]] || exit 0
if [[ -f $fnmode_param ]] && ! echo 3 | sudo tee "$fnmode_param" >/dev/null 2>&1; then
  echo "The running keyboard keeps its mode until the next reboot." >&2
fi
exit 0
