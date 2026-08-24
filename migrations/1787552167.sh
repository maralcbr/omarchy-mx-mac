echo "Restore GNOME Keyring unlock for password-based SDDM login"

omarchy-pkg-present gnome-keyring || exit 0

pam_file="${OMARCHY_SDDM_PAM_FILE:-/etc/pam.d/sddm}"
[[ -f $pam_file ]] || exit 0
grep -Eq '^[[:space:]]*-?auth[[:space:]]+.*pam_gnome_keyring\.so([[:space:]]|$)' "$pam_file" && exit 0

sudo env OMARCHY_SDDM_PAM_FILE="$pam_file" \
  bash -euo pipefail -c 'source "$1"' _ "$OMARCHY_PATH/install/login/sddm.sh"
