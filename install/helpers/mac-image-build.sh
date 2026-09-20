# Image-build helpers for OMARCHY_MAC_IMAGE_BUILD=1. Sourced from the fresh
# installer and from install/hardware/all.sh; no shebang.

omarchy_mac_image_build() {
  [[ ${OMARCHY_MAC_IMAGE_BUILD:-} == 1 ]]
}

omarchy_mac_deferred_steps_file() {
  printf '%s\n' "${OMARCHY_MAC_DEFERRED_STEPS:-/var/lib/omarchy/mac-first-boot/deferred-steps}"
}

omarchy_mac_hardware_step_paths() {
  local all="${OMARCHY_INSTALL:-$OMARCHY_PATH/install}/hardware/all.sh"

  [[ -f $all ]] || return 1
  sed -n 's/^run_logged "\$OMARCHY_INSTALL\/\(hardware\/.*\)"$/install\/\1/p' "$all"
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

omarchy_mac_record_deferred_hardware_steps() {
  local relative count=0 paths

  paths=$(omarchy_mac_hardware_step_paths) || return 1
  [[ -n $paths ]] || return 1
  while IFS= read -r relative; do
    [[ -n $relative ]] || continue
    omarchy_mac_record_deferred_step "$relative" || return 1
    count=$((count + 1))
  done <<<"$paths"
  (( count > 0 ))
}
