# Publish the qualified ZIP as the direct download

## Parent

[Portable Omarchy Mac installer specification](../portable-macos-installer-spec.md)

## What to build

A website visitor can download the qualified ZIP, open the app from Downloads and follow accurate installation instructions. Release metadata and channel delivery reference the exact qualified bytes, and website availability does not wait for Homebrew review.

## Acceptance criteria

- [ ] Publish only the exact qualified app ZIP and its final checksum at an immutable versioned URL after the applicable release authorization.
- [ ] Update public download links and required release/channel metadata from the PKG route to the verified ZIP without promoting unrelated changes.
- [ ] Read back the public artifact and verify its checksum, signatures, notarization/stapling and identity against qualification evidence.
- [ ] Instructions describe extract, open, review, authorize, install and Recovery handoff, plus honest interruption/Start over behavior.
- [ ] No instructions require disabling Gatekeeper, installing a daemon or moving a direct download into Applications.
- [ ] Keep installed Omarchy's update behavior unchanged and do not claim central Homebrew availability until it exists.
- [ ] Record the public release URL, checksum and qualification reference for the Homebrew submission.

## Blocked by

- [08: Qualify installation and Start over on supported hardware](08-qualify-exact-candidate.md)
