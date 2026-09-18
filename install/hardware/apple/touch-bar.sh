# tiny-dfr draws the Touch Bar keys. Its udev rules give the Touch Bar display
# and digitizer their own seat, so the compositor leaves them alone, and start
# the daemon when the Touch Bar appears. There is no service to enable.
omarchy-hw-apple-touch-bar || return 0

echo "Detected Apple Silicon Touch Bar: installing tiny-dfr"

omarchy-pkg-add tiny-dfr
