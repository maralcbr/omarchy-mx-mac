echo "Retire the legacy [omarchy-aarch64] repository on Apple Silicon"

# Macs that crossed from the omarchy-mac project still list its unsigned
# [omarchy-aarch64] repository and hold obsidian-appimage and
# hyprland-preview-share-picker-git, which conflict with the signed [omarchy]
# packages. The command drops the section and replaces those packages where
# they are installed. When it cannot finish, omarchy update runs it again
# before its next package upgrade, so later migrations are not held back.

omarchy-hw-apple-silicon || exit 0

omarchy-update-asahi-legacy-repository ||
  echo "The legacy repository cleanup did not finish; the next omarchy update tries again." >&2
