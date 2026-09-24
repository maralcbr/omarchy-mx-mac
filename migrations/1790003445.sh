echo "Quiet the GRUB boot on Apple Silicon like the x86 Limine entry"

# New images get these from mac-image-finalize; Macs installed before it
# still show a three-second GRUB menu and console text between the splash
# and the greeter. Same values as the finalizer, applied through the same
# key=value edits, then the Asahi update-grub regenerates grub.cfg (and the
# EFI GRUB it copies, as every kernel update already does).

omarchy-hw-apple-silicon || exit 0

grub_default="${OMARCHY_GRUB_DEFAULT:-/etc/default/grub}"
[[ -f $grub_default ]] || { echo "No $grub_default; nothing to quiet." >&2; exit 0; }

# The value GRUB would use: the last active assignment, quotes stripped.
get_assignment() {
  sed -n "s/^$1=//p" "$grub_default" | tail -n 1 | sed -E "s/^\"(.*)\"$/\1/; s/^'(.*)'$/\1/"
}

# One authoritative assignment: the first occurrence takes the value, every
# later one goes, a missing key is appended. awk, not sed: a value carries
# whatever the Mac put on its kernel line.
set_assignment() {
  local key=$1 value=$2 staged
  staged=$(mktemp)
  KEY=$key LINE="$key=\"$value\"" awk '
    index($0, ENVIRON["KEY"] "=") == 1 { if (!done) { print ENVIRON["LINE"]; done = 1 }; next }
    { print }
    END { if (!done) print ENVIRON["LINE"] }
  ' "$grub_default" >"$staged"
  sudo cp "$staged" "$grub_default"
  rm -f "$staged"
}

# The quiet words join the Mac's own line: cryptdevice=, resume= and the rest
# of what an encrypted Mac keeps in GRUB_CMDLINE_LINUX_DEFAULT stay. A word
# of the same key (loglevel=3) takes the quiet value in place.
quiet_words=(quiet splash loglevel=0 systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0)
current=$(get_assignment GRUB_CMDLINE_LINUX_DEFAULT)
read -ra words <<<"$current"
for quiet in "${quiet_words[@]}"; do
  found=0
  for i in "${!words[@]}"; do
    if [[ ${words[i]} == "$quiet" || ( $quiet == *=* && ${words[i]} == "${quiet%%=*}="* ) ]]; then
      if (( found )); then
        unset 'words[i]'
      else
        words[i]=$quiet
        found=1
      fi
    fi
  done
  (( found )) || words+=("$quiet")
  words=("${words[@]}")
done
wanted_cmdline="${words[*]}"

if [[ $(get_assignment GRUB_TIMEOUT) == 1 && $(get_assignment GRUB_TIMEOUT_STYLE) == hidden &&
  $wanted_cmdline == "$current" ]]; then
  exit 0
fi

set_assignment GRUB_TIMEOUT 1
set_assignment GRUB_TIMEOUT_STYLE hidden
set_assignment GRUB_CMDLINE_LINUX_DEFAULT "$wanted_cmdline"

if ! command -v "${OMARCHY_GRUB_PROBE:-grub-probe}" >/dev/null 2>&1 ||
  ! command -v "${OMARCHY_GRUB_MKCONFIG:-grub-mkconfig}" >/dev/null 2>&1; then
  : # A Limine Mac has no GRUB to regenerate; the defaults above are what it reads.
elif ! sudo "${OMARCHY_UPDATE_GRUB:-update-grub}"; then
  echo "update-grub failed; the quiet boot migration will retry later." >&2
  exit 1
fi
