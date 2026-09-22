echo "Quiet the GRUB boot on Apple Silicon like the x86 Limine entry"

# New images get these from mac-image-finalize; Macs installed before it
# still show a three-second GRUB menu and console text between the splash
# and the greeter. Same values as the finalizer, applied through the same
# key=value edits, then the Asahi update-grub regenerates grub.cfg (and the
# EFI GRUB it copies, as every kernel update already does).

omarchy-hw-apple-silicon || exit 0

grub_default="${OMARCHY_GRUB_DEFAULT:-/etc/default/grub}"
[[ -f $grub_default ]] || { echo "No $grub_default; nothing to quiet." >&2; exit 0; }

set_assignment() {
  local key=$1 value=$2
  if grep -Eq "^$key=" "$grub_default"; then
    sudo sed -i -E "s|^$key=.*|$key=\"$value\"|" "$grub_default"
  else
    printf '%s="%s"\n' "$key" "$value" | sudo tee -a "$grub_default" >/dev/null
  fi
}

wanted_cmdline='quiet splash loglevel=0 systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0'
if grep -Fxq 'GRUB_TIMEOUT="1"' "$grub_default" && grep -Fxq 'GRUB_TIMEOUT_STYLE="hidden"' "$grub_default" &&
  grep -Fxq "GRUB_CMDLINE_LINUX_DEFAULT=\"$wanted_cmdline\"" "$grub_default"; then
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
