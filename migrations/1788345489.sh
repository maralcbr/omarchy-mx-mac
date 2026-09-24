echo "Keep the Apple Silicon speaker amplifiers powered so playback stops popping"

# The hardware leaf writes the machine-wide copy; the user leaf writes the
# per-session copy. New installs run both; this migration reaches machines
# that predate either leaf. Re-run if either file is missing so a user-only
# copy from an earlier revision still becomes OS-wide.
#
# Earlier revisions also installed a software-dsp.lua overlay; it stopped
# WirePlumber from starting on some models and migration 1790225826 removes it.
OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
hardware_script="$OMARCHY_PATH/install/hardware/apple/fix-speaker-pop.sh"
user_script="$OMARCHY_PATH/install/user/hardware/apple/fix-speaker-pop.sh"
sys_conf="${OMARCHY_ASAHI_SPEAKER_CONF:-/etc/wireplumber/wireplumber.conf.d/asahi-audio-no-suspend.conf}"
user_conf="$HOME/.config/wireplumber/wireplumber.conf.d/asahi-audio-no-suspend.conf"

[[ -f $hardware_script || -f $user_script ]] || exit 0
[[ -f $sys_conf && -f $user_conf ]] && exit 0

[[ -f $hardware_script ]] && source "$hardware_script"
[[ -f $user_script ]] && source "$user_script"
[[ -f $sys_conf || -f $user_conf ]] || exit 0

# WirePlumber only reads drop-ins at startup. Restarting the audio stack is a
# few hundred milliseconds of silence in the visible update terminal, and it is
# what makes the fix take effect without a logout. A failed restart is not a
# failed migration: the file is in place and the next login picks it up.
systemctl --user restart wireplumber.service >/dev/null 2>&1 || true
