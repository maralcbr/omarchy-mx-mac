echo "Install the PipeWire realtime scheduling provider on Apple Silicon"

omarchy-hw-apple-silicon || exit 0
omarchy-pkg-add rtkit
