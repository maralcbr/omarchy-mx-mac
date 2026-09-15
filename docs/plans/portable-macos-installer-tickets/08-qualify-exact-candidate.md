# Qualify installation and Start over on supported hardware

## Parent

[Portable Omarchy Mac installer specification](../portable-macos-installer-spec.md)

## What to build

Demonstrate that the exact review candidate works through the real download or Cask placement path, finishes installation through Recovery, and safely starts over after a controlled interruption on supported test hardware.

## Acceptance criteria

- [ ] Identify the exact immutable candidate and approved test machine/state before testing; reuse earlier proof only where candidate and environment identities match.
- [ ] Honor the applicable owner authority and hardware-in-the-loop requirements before privileged or disk operations; missing cables or macOS access remain explicit blockers.
- [ ] Verify a real downloaded ZIP with quarantine intact and local Cask placement/explicit launch; confirm normal platform trust and no installer disk effect from Cask installation.
- [ ] Complete the normal installation through Recovery and boot Omarchy, then verify macOS access and protected partition identities against the recorded baseline.
- [ ] Exercise a controlled interrupted attempt and a reviewed Start over leading to a fresh successful installation; preserve evidence of the actual cleanup extent and resulting layout.
- [ ] Verify no persistent installer helper or login item remains, no service returns after reboot, and discarding/uninstalling the Mac launcher does not break the Recovery handoff or installed Omarchy.
- [ ] Record passed, failed and untested claims separately; a build, simulation or successful root launch alone is insufficient.
- [ ] Any corrective code/artifact change produces a new candidate identity and reruns only the qualification invalidated by that change; do not publish until all required evidence passes.

## Blocked by

- [07: Build the portable ZIP and Homebrew review candidate](07-portable-release-candidate.md)
