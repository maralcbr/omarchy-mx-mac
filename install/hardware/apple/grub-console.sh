# GRUB on Apple Silicon draws its menu with the 16-pixel unicode font on a
# native-resolution panel, which is unreadable, and an unattended boot of an
# encrypted Mac gives up on the root device after systemd's 90 s default and
# drops into the initrd's emergency mode instead of waiting at the passphrase
# prompt. This leaf renders a larger console font for GRUB and makes the
# initrd wait for the root device for as long as it takes; it runs at first
# boot for image installs (deferred) and through a migration on installed Macs.
omarchy-hw-apple-silicon || return 0
[[ ${OMARCHY_MAC_IMAGE_BUILD:-} != 1 ]] || return 0

grub_default=${OMARCHY_GRUB_DEFAULT:-/etc/default/grub}
grub_font=${OMARCHY_GRUB_FONT:-/boot/grub/fonts/omarchy.pf2}
font_source=${OMARCHY_GRUB_FONT_SOURCE:-/usr/share/fonts/liberation/LiberationMono-Regular.ttf}
font_size=${OMARCHY_GRUB_FONT_SIZE:-28}
device_wait='rootflags=x-systemd.device-timeout=0'

[[ -f $grub_default ]] || return 0

# A regeneration that failed (the ESP read-only, say) is owed until it
# succeeds, even when the defaults already read as configured.
pending=${OMARCHY_GRUB_CONSOLE_PENDING:-/var/lib/omarchy/grub-console.pending}
grub_console_changed=0
[[ ! -e $pending ]] || grub_console_changed=1

# The value GRUB would use: the last active assignment, quotes stripped.
grub_console_get() {
  sed -n "s/^$1=//p" "$grub_default" | tail -n 1 | sed -E "s/^\"(.*)\"$/\1/; s/^'(.*)'$/\1/"
}

# One authoritative assignment: the first occurrence (active or commented)
# takes the value, every later one goes, a missing key is appended.
grub_console_set() {
  local key=$1 value=$2 staged
  if [[ $(grub_console_get "$key") == "$value" && $(grep -Ec "^$key=" "$grub_default") == 1 ]]; then
    return 0
  fi
  staged=$(mktemp)
  awk -v key="$key" -v line="$key=\"$value\"" '
    $0 ~ "^#?" key "=" { if (!done) { print line; done = 1 }; next }
    { print }
    END { if (!done) print line }
  ' "$grub_default" >"$staged"
  sudo cp "$staged" "$grub_default"
  rm -f "$staged"
  grub_console_changed=1
}

if [[ ! -s $grub_font ]]; then
  if [[ -f $font_source ]] && ! omarchy-cmd-missing grub-mkfont; then
    echo "Detected Apple Silicon Mac: rendering a ${font_size}px GRUB font"
    sudo mkdir -p "$(dirname "$grub_font")"
    sudo grub-mkfont -s "$font_size" -o "$grub_font" "$font_source" >/dev/null
    grub_console_changed=1
  else
    echo "No font source or grub-mkfont; leaving GRUB's default font" >&2
  fi
fi
[[ -s $grub_font ]] && grub_console_set GRUB_FONT "$grub_font"

# Without a named backend GRUB also tries efi_uga, which the arm64 build
# does not ship, and prints "efi_uga.mod not found" at every boot.
grub_console_set GRUB_VIDEO_BACKEND efi_gop

cmdline=$(grub_console_get GRUB_CMDLINE_LINUX)
if [[ " $cmdline " != *" $device_wait "* ]]; then
  grub_console_set GRUB_CMDLINE_LINUX "${cmdline:+$cmdline }$device_wait"
else
  grub_console_set GRUB_CMDLINE_LINUX "$cmdline"
fi

if (( grub_console_changed )); then
  sudo mkdir -p "$(dirname "$pending")"
  sudo touch "$pending"
  echo "Regenerating GRUB for the console font and the unbounded root wait"
  sudo "${OMARCHY_UPDATE_GRUB:-update-grub}" >/dev/null
  sudo rm -f "$pending"
fi
