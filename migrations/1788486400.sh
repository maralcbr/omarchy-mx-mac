echo "Install the default packages that were missing from the Apple Silicon package set"

# These are defaults on every architecture. On x86 they are already present,
# so this is a no-op there; on Apple Silicon they were previously left out of
# the default set because no aarch64 build existed.

# A Mac from the omarchy-mac project still holds obsidian-appimage and
# hyprland-preview-share-picker-git, which block the two packages below, and
# may list the retired [omarchy-aarch64] repository ahead of [omarchy]. A
# cleanup that cannot finish does not stop here: the install below still
# runs, and omarchy update retries the cleanup before its next upgrade.
if omarchy-hw-apple-silicon; then
  omarchy-update-asahi-legacy-repository ||
    echo "The legacy repository cleanup did not finish; installing the default packages anyway." >&2
fi

omarchy-pkg-add asdcontrol dotnet-runtime gpu-screen-recorder herdr hyprland-preview-share-picker \
  libreoffice-fresh moonlight-qt obs-studio obsidian omacalc omacut omawrite pinta \
  qemu-user-static-binfmt qt6-imageformats tensaku tobi-try ttfx tzupdate
