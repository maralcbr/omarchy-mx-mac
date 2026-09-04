echo "Install the default packages that were missing from the Apple Silicon package set"

# These are defaults on every architecture. On x86 they are already present,
# so this is a no-op there; on Apple Silicon they were previously left out of
# the default set because no aarch64 build existed.
omarchy-pkg-add asdcontrol dotnet-runtime gpu-screen-recorder herdr hyprland-preview-share-picker \
  libreoffice-fresh moonlight-qt obs-studio obsidian omacalc omacut omawrite pinta \
  qemu-user-static-binfmt qt6-imageformats tensaku tobi-try ttfx tzupdate
