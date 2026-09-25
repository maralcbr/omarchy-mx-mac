# Ensure that F-keys on Apple-like keyboards (such as Lofree Flow84) are always F-keys.
#
# Apple Silicon is the exception: the built-in keyboard is an Apple keyboard,
# and macOS puts mute, volume, brightness and media on the top row with F1-F12
# behind Fn. fnmode=3 (auto) does that for Apple keyboards and keeps F-keys
# first on the non-Apple boards hid_apple recognises (Keychron and friends).
# docs/apple-silicon-keyboard.md; migration 1790305681 moves Macs off fnmode=2.
conf="${OMARCHY_HID_APPLE_CONF:-/etc/modprobe.d/hid_apple.conf}"
fnmode=2
omarchy-hw-apple-silicon && fnmode=3

if [[ ! -f $conf ]]; then
  sudo mkdir -p "$(dirname "$conf")"
  echo "options hid_apple fnmode=$fnmode" | sudo tee "$conf" >/dev/null
fi
