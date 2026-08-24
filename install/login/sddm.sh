pam_file="${OMARCHY_SDDM_PAM_FILE:-/etc/pam.d/sddm}"

if [[ -f $pam_file ]] && ! grep -Eq '^[[:space:]]*-?auth[[:space:]]+.*pam_gnome_keyring\.so([[:space:]]|$)' "$pam_file"; then
  tmp="${pam_file}.omarchy.$$"
  if ! awk '
    { print }
    !inserted && $1 ~ /^-?auth$/ {
      print "-auth       optional    pam_gnome_keyring.so"
      inserted = 1
    }
    END { if (!inserted) exit 1 }
  ' "$pam_file" >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  chmod --reference="$pam_file" "$tmp"
  chown --reference="$pam_file" "$tmp"
  mv "$tmp" "$pam_file"
fi
