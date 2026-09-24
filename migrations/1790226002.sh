echo "Repair the GRUB kernel line of Apple Silicon Macs on the busybox initramfs"

# Macs installed before Omarchy's images can boot mkinitcpio's busybox init,
# an encrypted one unlocking its root through the encrypt hook and a
# cryptdevice= on the kernel line. Two earlier migrations broke that boot:
# 1790003445 replaced GRUB_CMDLINE_LINUX_DEFAULT, and the cryptdevice= many
# such Macs kept there, with the quiet line; the GRUB console leaf
# (1790030337) added rootflags=x-systemd.device-timeout=0, a second
# rootflags= the busybox init takes over 10_linux's rootflags=subvol=@. Both
# are fixed at the source; this puts back what they took from Macs that
# already ran them. It acts only on a busybox initramfs, drops only the exact
# word the leaf wrote, and restores cryptdevice= only for a root it can trace
# to a LUKS partition with no unlock argument left anywhere in the defaults.
# A Limine Mac boots its UKI, a systemd initramfs merges rootflags= and reads
# rd.luks.*: both are left alone.

omarchy-hw-apple-silicon || exit 0

grub_default=${OMARCHY_GRUB_DEFAULT:-/etc/default/grub}
grub_cfg=${OMARCHY_GRUB_CFG:-/boot/grub/grub.cfg}
backup_dir=${OMARCHY_GRUB_BACKUP_DIR:-/var/lib/omarchy/backups}
proc_cmdline=${OMARCHY_PROC_CMDLINE:-/proc/cmdline}
# Set before the first edit, cleared once grub.cfg verifies: a run that
# could not finish (nor roll back) regenerates and verifies next time even
# when the defaults already read as repaired.
pending=${OMARCHY_GRUB_REPAIR_PENDING:-/var/lib/omarchy/grub-cmdline-repair.pending}
device_wait='rootflags=x-systemd.device-timeout=0'

[[ -f $grub_default ]] || exit 0
if omarchy-mac-limine-active; then
  exit 0
fi
command -v "${OMARCHY_GRUB_PROBE:-grub-probe}" >/dev/null 2>&1 &&
  command -v "${OMARCHY_GRUB_MKCONFIG:-grub-mkconfig}" >/dev/null 2>&1 || exit 0

# The HOOKS mkinitcpio builds with (preset, mkinitcpio.conf, drop-ins); a
# configuration that cannot be read proves nothing, unless a repair is left
# pending: that one waits for a readable configuration to finish.
if ! hooks=$(omarchy-hw-apple-initramfs-hooks 2>/dev/null); then
  if [[ -e $pending ]]; then
    echo "The mkinitcpio configuration cannot be read; the pending GRUB repair migration will retry later." >&2
    exit 1
  fi
  exit 0
fi
[[ " $hooks " != *" systemd "* ]] || exit 0

# The value GRUB would use: the last active assignment, quotes stripped.
get_assignment() {
  sed -n "s/^$1=//p" "$grub_default" | tail -n 1 | sed -E "s/^\"(.*)\"$/\1/; s/^'(.*)'$/\1/"
}

# Replace the defaults file in one rename: a failure leaves the old one whole.
install_defaults() {
  sudo install -m 644 "$1" "$grub_default.omarchy-new" || { sudo rm -f "$grub_default.omarchy-new"; return 1; }
  sudo mv -f "$grub_default.omarchy-new" "$grub_default"
}

# One authoritative assignment: the first occurrence takes the value, every
# later one goes.
set_assignment() {
  local key=$1 value=$2
  KEY=$key LINE="$key=\"$value\"" awk '
    index($0, ENVIRON["KEY"] "=") == 1 { if (!done) { print ENVIRON["LINE"]; done = 1 }; next }
    { print }
    END { if (!done) print ENVIRON["LINE"] }
  ' "$grub_default" >"$work/staged"
  install_defaults "$work/staged"
}

root_source=$(findmnt -no SOURCE / 2>/dev/null || true)
root_source=${root_source%%[*}
cmdline=$(get_assignment GRUB_CMDLINE_LINUX)
cmdline_default=$(get_assignment GRUB_CMDLINE_LINUX_DEFAULT)
read -ra words <<<"$cmdline"
kept=()
changed=0
for word in "${words[@]}"; do
  if [[ $word == "$device_wait" ]]; then
    changed=1
    continue
  fi
  kept+=("$word")
done

# cryptdevice=: the encrypt hook, a root inside a dm-crypt mapping on a LUKS
# partition, and no cryptdevice= or rd.luks.* left in either variable.
cryptdevice=""
if [[ " $hooks " == *" encrypt "* && " $cmdline $cmdline_default " != *" cryptdevice="* &&
  " $cmdline $cmdline_default " != *" rd.luks."* ]]; then
  mapper="" luks_part=""
  if [[ $root_source == /dev/* ]]; then
    while read -r name type fstype; do
      if [[ -z $mapper && $type == crypt ]]; then
        mapper=${name#/dev/mapper/}
      elif [[ -n $mapper && -z $luks_part && $fstype == crypto_LUKS ]]; then
        luks_part=$name
      fi
    done < <(lsblk -nsrpo NAME,TYPE,FSTYPE "$root_source" 2>/dev/null || true)
  fi
  luks_uuid=""
  if [[ -n $luks_part ]]; then
    luks_uuid=$(lsblk -ndo UUID "$luks_part" 2>/dev/null || true)
    [[ -n $luks_uuid ]] || luks_uuid=$(sudo blkid -s UUID -o value "$luks_part" 2>/dev/null || true)
  fi
  if [[ $mapper =~ ^[A-Za-z0-9._-]+$ && $luks_uuid =~ ^[0-9A-Fa-f-]{36}$ ]]; then
    # The line this boot unlocked with, when it names the same partition and
    # mapping, keeps its options; otherwise the mapping's own discard flag.
    read -ra booted <<<"$(cat "$proc_cmdline" 2>/dev/null || true)"
    for word in "${booted[@]}"; do
      if [[ $word == "cryptdevice=UUID=$luks_uuid:$mapper" || $word == "cryptdevice=UUID=$luks_uuid:$mapper:"* ]]; then
        cryptdevice=$word
      fi
    done
    if [[ -z $cryptdevice ]]; then
      cryptdevice="cryptdevice=UUID=$luks_uuid:$mapper"
      if sudo cryptsetup status "$mapper" 2>/dev/null | grep -Eq '^[[:space:]]*flags:.*[[:space:]]discards'; then
        cryptdevice+=":allow-discards"
      fi
    fi
    if [[ ! $cryptdevice =~ ^cryptdevice=UUID=[0-9A-Fa-f-]{36}:[A-Za-z0-9._-]+(:[a-z_,-]+)?$ ]]; then
      cryptdevice=""
    fi
  elif [[ -n $root_source ]]; then
    echo "The encrypt hook is in HOOKS but the root ($root_source) does not trace to a LUKS partition; leaving cryptdevice= alone." >&2
  fi
  if [[ -n $cryptdevice ]]; then
    kept+=("$cryptdevice")
    changed=1
  fi
fi

(( changed )) || [[ -e $pending ]] || exit 0

if (( changed )); then
  echo "Restoring the busybox initramfs kernel line: ${cryptdevice:-no cryptdevice= needed}, no second rootflags="
else
  echo "Finishing the busybox initramfs kernel line repair left pending"
fi
sudo mkdir -p "$(dirname "$pending")"
sudo touch "$pending"
work=$(mktemp -d)
cp "$grub_default" "$work/before"
sudo mkdir -p "$backup_dir"
backup="$backup_dir/grub.pre-cmdline-repair"
[[ -e $backup ]] || sudo cp "$grub_default" "$backup"

# From the first edit on, any failure puts the defaults and grub.cfg back.
# A rollback that lands leaves the Mac as it was before the repair: the
# repair warns (the damage may remain, to fix by hand before rebooting),
# keeps its pending marker and lets the migrations go on.
# Only a rollback that fails stops the update, as the Mac may not boot.
restore() {
  trap - ERR
  local restored=1
  echo "GRUB repair: $1." >&2
  if ! install_defaults "$work/before"; then
    echo "Could not restore $grub_default; the original is $backup." >&2
    restored=0
  elif ! sudo "${OMARCHY_UPDATE_GRUB:-update-grub}" >/dev/null 2>&1; then
    echo "update-grub failed while restoring GRUB." >&2
    restored=0
  fi
  rm -rf "$work"
  if (( ! restored )); then
    echo "The GRUB repair could not roll back and this Mac may not boot. Before rebooting, copy $backup to $grub_default and run sudo update-grub; the GRUB repair migration will retry later." >&2
    exit 1
  fi
  cat >&2 <<WARN
Warning: the GRUB repair could not verify its result, so $grub_default and
grub.cfg are back as they were before the repair. The damage it was fixing
may remain: fix it by hand before rebooting. In GRUB_CMDLINE_LINUX drop
$device_wait${cryptdevice:+ and add $cryptdevice}, run sudo update-grub, and check
that every linux line in $grub_cfg carries one rootflags= (with subvol=@)${cryptdevice:+ and
the cryptdevice=}. To retry the repair:
bash -euo pipefail "${OMARCHY_PATH:-/usr/share/omarchy}/migrations/1790226002.sh"
WARN
  exit 0
}
set -E
trap 'restore "a repair step failed"' ERR

(( ! changed )) || set_assignment GRUB_CMDLINE_LINUX "${kept[*]}"
sudo "${OMARCHY_UPDATE_GRUB:-update-grub}" >/dev/null || restore "update-grub failed"

# The cryptdevice= the line now carries, restored here or on an earlier run.
unlock=""
read -ra final_words <<<"$(get_assignment GRUB_CMDLINE_LINUX)"
for word in "${final_words[@]}"; do
  if [[ $word == cryptdevice=* ]]; then
    unlock=$word
  fi
done

# Every kernel entry 10_linux wrote for this system (os-prober's entries for
# other installations, even on the same filesystem, sit in their own
# section) now carries one rootflags= (with subvol= when the root is a
# subvolume, as 10_linux writes it), no device wait, and the cryptdevice=.
fsroot=$(findmnt -no FSROOT / 2>/dev/null || true)
entries=$(sudo cat "$grub_cfg" 2>/dev/null | awk '
  /^### BEGIN \/etc\/grub\.d\/10_linux ###$/ { inside = 1; next }
  /^### END \/etc\/grub\.d\/10_linux ###$/ { inside = 0; next }
  inside && /^[[:space:]]*linux[[:space:]]/ { print }
' || true)
ours=0
while read -r entry; do
  [[ -n $entry ]] || continue
  ours=$((ours + 1))
  rootflags=$({ grep -Eo '(^|[[:space:]])rootflags=[^[:space:]]*' <<<"$entry" || true; } | wc -l)
  if [[ -n $fsroot && $fsroot != / ]]; then
    if (( rootflags != 1 )) || ! grep -Eq '(^|[[:space:]])rootflags=([^[:space:]]*,)?subvol=' <<<"$entry"; then
      restore "a kernel entry does not carry exactly one rootflags= with subvol="
    fi
  elif (( rootflags > 1 )); then
    restore "a kernel entry carries more than one rootflags="
  fi
  [[ " $entry " != *" $device_wait "* ]] || restore "a kernel entry still waits through a second rootflags="
  [[ -z $unlock || " $entry " == *" $unlock "* ]] || restore "a kernel entry does not carry $unlock"
done <<<"$entries"
(( ours > 0 )) || restore "$grub_cfg has no 10_linux kernel entry"
trap - ERR
sudo rm -f "$pending"
rm -rf "$work"
