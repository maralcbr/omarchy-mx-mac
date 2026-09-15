# Build the portable ZIP and Homebrew review candidate

## Parent

[Portable Omarchy Mac installer specification](../portable-macos-installer-spec.md)

## What to build

Produce one immutable review candidate that contains the complete portable installer and rebuilt execution engine. Reviewers can extract it in Downloads or place the same app through a local Cask definition, explicitly launch it, use the completed journeys, and remove the launcher without affecting Omarchy.

## Acceptance criteria

- [ ] Rebuild and repin the changed immutable execution engine using the normal release process; the app executes the new restart-capable engine rather than an older published archive.
- [ ] Package the app, signed helper and required runtime together, with portable resource resolution and no PKG dependency or required Applications placement.
- [ ] Complete Developer ID signing, hardened runtime, notarization and stapling under the applicable owner authority; recreate and hash the final ZIP after stapling.
- [ ] Artifact validators, release metadata and staged channel publishing consume the ZIP and reject mismatched artifacts; public channels are not changed by building the candidate.
- [ ] A local Cask definition uses the same immutable candidate and checksum. Cask installation only places the app; launch and disk approval are explicit.
- [ ] Cask uninstall and discarding the download do not remove Omarchy, the target's Recovery resources or attempt evidence still needed for safe restart.
- [ ] Keep hardware restrictions, channels and minimum macOS policy unchanged; install instructions describe the actual ZIP and Cask experience without claiming central availability.
- [ ] Run applicable focused debug/release Swift, Python, formatting and packaging checks. Rebuild/open one review app and verify fresh, denied, interrupted, Start over, blocked and Recovery screens.
- [ ] Record exact app, engine, ZIP and Cask candidate identities for reuse by qualification; do not publish or promote an unqualified candidate.

## Blocked by

- [04: Stop safely when the installer quits or loses its UI](04-stop-at-operation-boundary.md)
- [06: Start over after partial partition or payload installation](06-restart-partial-payload.md)
