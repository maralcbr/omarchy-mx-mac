# GRUB on Apple Silicon: the x86 Limine look and a quiet boot.
#
# Out of the box GRUB draws a 16-pixel font on a native-resolution panel, an
# unattended boot of an encrypted Mac gives up on the root device after 90 s
# and drops into the initrd's emergency mode, Plymouth forces its text view
# because the device tree registers the serial console, and 10_linux narrates
# every boot with "Loading Linux ...". This leaf renders the theme fonts,
# installs the Omarchy GRUB theme (Tokyo Night, the x86 Limine colours), shows
# the menu for three seconds like x86, pins the efi_gop video backend the
# arm64 GRUB actually ships, makes the initrd wait for the root device, tells
# Plymouth to ignore serial consoles, and guards the 10_linux echoes behind
# "quiet". It runs at first boot for image installs (deferred) and through a
# migration on installed Macs; every step is idempotent.
omarchy-hw-apple-silicon || return 0
[[ ${OMARCHY_MAC_IMAGE_BUILD:-} != 1 ]] || return 0

grub_default=${OMARCHY_GRUB_DEFAULT:-/etc/default/grub}
grub_font=${OMARCHY_GRUB_FONT:-/boot/grub/fonts/omarchy.pf2}
theme_dir=${OMARCHY_GRUB_THEME_DIR:-/boot/grub/themes/omarchy}
theme_source=${OMARCHY_GRUB_THEME_SOURCE:-${OMARCHY_PATH:-/usr/share/omarchy}/default/grub/omarchy/theme.txt}
font_dir=${OMARCHY_GRUB_FONT_SOURCE_DIR:-/usr/share/fonts/liberation}
linux_script=${OMARCHY_GRUB_LINUX_SCRIPT:-/etc/grub.d/10_linux}
backup_dir=${OMARCHY_GRUB_BACKUP_DIR:-/var/lib/omarchy/backups}
device_wait='rootflags=x-systemd.device-timeout=0'
plymouth_serial='plymouth.ignore-serial-consoles'

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

# grub-mkfont names a face "<family> <style> <size>"; the theme refers to
# those names, so the sizes here and in theme.txt must agree.
grub_console_font() {
  local target=$1 size=$2 source=$3
  [[ -s $target ]] && return 0
  [[ -f $source ]] || { echo "No $source; leaving GRUB's default font for $target" >&2; return 1; }
  omarchy-cmd-missing grub-mkfont && { echo "No grub-mkfont; leaving GRUB's default font" >&2; return 1; }
  sudo mkdir -p "$(dirname "$target")"
  if ! sudo grub-mkfont -s "$size" -o "$target" "$source" >/dev/null; then
    echo "grub-mkfont could not render $target" >&2
    sudo rm -f "$target"
    return 1
  fi
  grub_console_changed=1
}

# Console font: readable at native resolution.
if grub_console_font "$grub_font" 28 "$font_dir/LiberationMono-Regular.ttf"; then
  grub_console_set GRUB_FONT "$grub_font"
fi

# The themed menu: fonts the theme names, then the theme itself.
theme_ready=1
grub_console_font "$theme_dir/sans-bold-36.pf2" 36 "$font_dir/LiberationSans-Bold.ttf" || theme_ready=0
grub_console_font "$theme_dir/mono-28.pf2" 28 "$font_dir/LiberationMono-Regular.ttf" || theme_ready=0
grub_console_font "$theme_dir/mono-24.pf2" 24 "$font_dir/LiberationMono-Regular.ttf" || theme_ready=0
grub_console_font "$theme_dir/mono-20.pf2" 20 "$font_dir/LiberationMono-Regular.ttf" || theme_ready=0
if (( theme_ready )) && [[ -f $theme_source ]]; then
  if ! cmp -s "$theme_source" "$theme_dir/theme.txt"; then
    sudo install -Dm644 "$theme_source" "$theme_dir/theme.txt"
    grub_console_changed=1
  fi
  grub_console_set GRUB_THEME "$theme_dir/theme.txt"
  grub_console_set GRUB_TIMEOUT 3
  grub_console_set GRUB_TIMEOUT_STYLE menu
fi

# Without a named backend GRUB also tries efi_uga, which the arm64 build
# does not ship, and prints "efi_uga.mod not found" at every boot.
grub_console_set GRUB_VIDEO_BACKEND efi_gop

cmdline=$(grub_console_get GRUB_CMDLINE_LINUX)
if [[ " $cmdline " != *" $device_wait "* ]]; then
  grub_console_set GRUB_CMDLINE_LINUX "${cmdline:+$cmdline }$device_wait"
else
  grub_console_set GRUB_CMDLINE_LINUX "$cmdline"
fi

# The device tree registers the serial console, and Plymouth forces its text
# view whenever a serial console is active; the splash needs it ignored.
cmdline_default=$(grub_console_get GRUB_CMDLINE_LINUX_DEFAULT)
if [[ " $cmdline_default " != *" $plymouth_serial "* ]]; then
  grub_console_set GRUB_CMDLINE_LINUX_DEFAULT "${cmdline_default:+$cmdline_default }$plymouth_serial"
else
  grub_console_set GRUB_CMDLINE_LINUX_DEFAULT "$cmdline_default"
fi

# 10_linux echoes "Loading Linux ..." unconditionally; guard both echoes
# behind a quiet kernel line. The file is a pacman backup file, so an
# upgrade leaves it and drops a .pacnew; the original is kept outside grub.d,
# where an executable copy would be run as a second generator.
if [[ -f $linux_script ]] && ! grep -Fq 'Omarchy: no narration' "$linux_script"; then
  echo_line=$'\techo\t\'$(echo "$message" | grub_quote)\''
  if [[ $(grep -Fc "$echo_line" "$linux_script") == 2 ]] &&
    grep -Fq 'message="$(gettext_printf "Loading Linux %s ..." ${version})"' "$linux_script" &&
    grep -Fq 'message="$(gettext_printf "Loading initial ramdisk ...")"' "$linux_script"; then
    sudo mkdir -p "$backup_dir"
    [[ -e $backup_dir/10_linux.pre-omarchy ]] || sudo cp "$linux_script" "$backup_dir/10_linux.pre-omarchy"
    staged=$(mktemp)
    ECHO_LINE=$echo_line awk '
      $0 == ENVIRON["ECHO_LINE"] { print "\t${message:+echo\t'"'"'$(echo \"$message\" | grub_quote)'"'"'}"; next }
      { print }
      /^  message="\$\(gettext_printf "Loading Linux %s \.\.\." \$\{version\}\)"$/ ||
      /^    message="\$\(gettext_printf "Loading initial ramdisk \.\.\."\)"$/ {
        print "    case \" $GRUB_CMDLINE_LINUX_DEFAULT \" in *\" quiet \"*) message=\"\" ;; esac  # Omarchy: no narration on a quiet boot"
      }
    ' "$linux_script" >"$staged"
    # Only a complete transformation is installed: both echoes guarded and
    # both guards in place, or the script keeps narrating and says so.
    if [[ $(grep -Fc 'Omarchy: no narration' "$staged") == 2 && $(grep -Fc $'\t${message:+echo\t' "$staged") == 2 ]] &&
      ! grep -Fq "$echo_line" "$staged" && sh -n "$staged"; then
      sudo cp "$staged" "$linux_script"
      grub_console_changed=1
    else
      echo "$linux_script could not be guarded completely; leaving its echoes" >&2
    fi
    rm -f "$staged"
  else
    echo "$linux_script does not look like the GRUB 2.12 script; leaving its echoes" >&2
  fi
fi

# The command line above is what a Limine Mac derives its UKI from, so those
# edits matter on every Mac; only the GRUB regeneration needs GRUB installed.
if (( grub_console_changed )) &&
  command -v "${OMARCHY_GRUB_PROBE:-grub-probe}" >/dev/null 2>&1 &&
  command -v "${OMARCHY_GRUB_MKCONFIG:-grub-mkconfig}" >/dev/null 2>&1; then
  sudo mkdir -p "$(dirname "$pending")"
  sudo touch "$pending"
  echo "Regenerating GRUB for the Omarchy theme and the quiet boot"
  sudo "${OMARCHY_UPDATE_GRUB:-update-grub}" >/dev/null
  sudo rm -f "$pending"
fi
