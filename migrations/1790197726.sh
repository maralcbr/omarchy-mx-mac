echo "Install the Apple Silicon audio profile so the speakers play"

# alsa-ucm-conf-asahi splits the Mac sound card into speakers and headphones.
# Without it PipeWire only sees the headphone path, asahi-audio never loads the
# speaker DSP and speakersafetyd keeps the amps locked, so the speakers are
# silent. Macs installed from images built without the package get it here.

omarchy-hw-apple-silicon || exit 0
pacman -Q alsa-ucm-conf-asahi >/dev/null 2>&1 && exit 0

omarchy-pkg-add alsa-ucm-conf-asahi || {
  echo "alsa-ucm-conf-asahi did not install; the audio migration will retry later." >&2
  exit 1
}

# PipeWire reads UCM when it opens the card; a restart picks up the speakers now
# instead of at the next login. Without a user session this is a no-op.
systemctl --user try-restart wireplumber pipewire pipewire-pulse 2>/dev/null || true
