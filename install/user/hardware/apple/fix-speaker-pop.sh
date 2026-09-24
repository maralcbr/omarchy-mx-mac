# Keep the Apple Silicon speaker amplifiers powered between streams.
#
# The machine-wide copy lives under /etc (see
# install/hardware/apple/fix-speaker-pop.sh). This per-user copy covers the
# session that is finalizing now, including users created after install, and
# stays in lockstep with the shipped file whenever the leaf re-runs.
omarchy-hw-apple-silicon || return 0

echo "Detected Apple Silicon Mac: keeping the speaker amplifiers powered between streams"

mkdir -p "$HOME/.config/wireplumber/wireplumber.conf.d"
cp "$OMARCHY_PATH/default/wireplumber/wireplumber.conf.d/asahi-audio-no-suspend.conf" \
  "$HOME/.config/wireplumber/wireplumber.conf.d/"
