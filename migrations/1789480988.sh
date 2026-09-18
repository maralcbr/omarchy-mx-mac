echo "Install the Touch Bar daemon on Apple Silicon MacBook Pros with a Touch Bar"

# install/hardware/apple/touch-bar.sh covers new installs only.
omarchy-hw-apple-touch-bar || exit 0
omarchy-pkg-present tiny-dfr && exit 0

omarchy-pkg-add tiny-dfr

# The running compositor opened the Touch Bar display before tiny-dfr's seat
# rule existed, and keeps it until it restarts.
omarchy-state set reboot-required
