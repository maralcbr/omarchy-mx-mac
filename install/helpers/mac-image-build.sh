# Image-build helpers for OMARCHY_MAC_IMAGE_BUILD=1. Sourced from the fresh
# installer and from install/hardware/all.sh; no shebang.
#
# Image builds cannot inspect the target Mac. They export
# OMARCHY_MAC_TARGET=generic-apple-silicon so omarchy-hw-apple-silicon reports
# the generic Apple Silicon configuration without reading /proc/device-tree.
# HID and btrfs drop-ins stay in the image. Model-specific hardware leaves are
# recorded in deferred-steps and run on first boot with OMARCHY_MAC_TARGET
# unset so they probe the real machine.

omarchy_mac_image_build() {
  [[ ${OMARCHY_MAC_IMAGE_BUILD:-} == 1 ]]
}

omarchy_mac_export_image_identity() {
  omarchy_mac_image_build || return 1
  export OMARCHY_MAC_IMAGE_BUILD=1
  export OMARCHY_MAC_TARGET=generic-apple-silicon
}

omarchy_mac_deferred_step_rebuilds_initramfs() {
  case $1 in
    install/hardware/apple/fix-asahi-hid-race.sh | install/hardware/apple/fix-asahi-btrfs-race.sh)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

omarchy_mac_deferred_steps_file() {
  printf '%s\n' "${OMARCHY_MAC_DEFERRED_STEPS:-/var/lib/omarchy/mac-first-boot/deferred-steps}"
}

omarchy_mac_hardware_step_paths() {
  local all="${OMARCHY_INSTALL:-$OMARCHY_PATH/install}/hardware/all.sh" line

  [[ -f $all ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ run_logged[[:space:]]+\"\$OMARCHY_INSTALL/(hardware/[^\"\;]+)\" ]]; then
      printf 'install/%s\n' "${BASH_REMATCH[1]}"
    elif [[ $line =~ run_logged[[:space:]]+\$OMARCHY_INSTALL/(hardware/[^\"\;[:space:]]+) ]]; then
      printf 'install/%s\n' "${BASH_REMATCH[1]}"
    fi
  done <"$all"
}

omarchy_mac_record_deferred_step() {
  local relative=$1
  local file dir tmp

  [[ -n $relative && $relative != /* && $relative != *..* ]] || return 1
  file=$(omarchy_mac_deferred_steps_file)
  dir=$(dirname "$file")
  install -d -m 0755 "$dir"
  if [[ -f $file ]] && grep -Fxq -- "$relative" "$file"; then
    chmod 0644 "$file"
    return 0
  fi
  tmp=$(mktemp "$dir/.deferred-steps.XXXXXX")
  if [[ -f $file ]]; then
    cat "$file" >"$tmp"
  fi
  printf '%s\n' "$relative" >>"$tmp"
  chmod 0644 "$tmp"
  mv "$tmp" "$file"
}

# The image ships the Limine gate: install/hardware/apple/limine-boot.sh,
# deferred to first boot, activates Limine on every Mac installed from it.
omarchy_mac_enable_limine() {
  local gate=${OMARCHY_LIMINE_GATE:-/var/lib/omarchy/limine.enabled}
  install -d -m 0755 "$(dirname "$gate")" && : >"$gate" && chmod 0644 "$gate"
}

omarchy_mac_record_deferred_hardware_steps() {
  local relative count=0 paths

  paths=$(omarchy_mac_hardware_step_paths) || return 1
  [[ -n $paths ]] || return 1
  while IFS= read -r relative; do
    [[ -n $relative ]] || continue
    omarchy_mac_deferred_step_rebuilds_initramfs "$relative" && continue
    omarchy_mac_record_deferred_step "$relative" || return 1
    count=$((count + 1))
  done <<<"$paths"
  (( count > 0 ))
}
