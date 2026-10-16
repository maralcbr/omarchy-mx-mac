echo "Install wf-recorder so screen recording works on Apple Silicon"

# gpu-screen-recorder can't capture on Apple Silicon (its KMS backend can't
# reach the Apple display controller), so recording silently never started.
# omarchy-capture-screenrecording now records with wf-recorder there.

omarchy-hw-apple-silicon || exit 0
omarchy-pkg-present wf-recorder && exit 0

omarchy-pkg-add wf-recorder || {
  echo "wf-recorder did not install; the screen recording migration will retry later." >&2
  exit 1
}
