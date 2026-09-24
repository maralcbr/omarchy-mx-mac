# Keep the Apple Silicon speaker amplifiers powered between streams.
#
# The drop-in is machine-wide so every user session and every PipeWire/Pulse
# client (current or future) gets the fix. It is also shipped at etc/wireplumber/
# for omarchy-settings; this leaf still copies it so an install whose settings
# package predates that path is repaired.
omarchy-hw-apple-silicon || return 0

echo "Detected Apple Silicon Mac: keeping the speaker amplifiers powered between streams"

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
dropin="$OMARCHY_PATH/default/wireplumber/wireplumber.conf.d/asahi-audio-no-suspend.conf"
sys_conf="${OMARCHY_ASAHI_SPEAKER_CONF:-/etc/wireplumber/wireplumber.conf.d/asahi-audio-no-suspend.conf}"

sudo mkdir -p "$(dirname "$sys_conf")"
sudo cp "$dropin" "$sys_conf"
