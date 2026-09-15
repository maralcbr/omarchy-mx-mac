# Prove temporary privileges from a downloaded app

## Parent

[Portable Omarchy Mac installer specification](../portable-macos-installer-spec.md)

## What to build

Open a signed, notarized app extracted from a ZIP in Downloads, approve a native administrator prompt, perform one harmless authenticated helper request, and observe the helper retire. This is the decision gate for the deprecated SMJobSubmit approach before connecting it to disk execution. Reuse the existing helper interface; keep any required separation of signing identity from service address small and behavior preserving.

## Acceptance criteria

- [ ] The downloaded app runs from a user-owned folder with quarantine intact and without a PKG, Applications placement or developer tools.
- [ ] The GUI stays unprivileged and the temporary worker accepts only the intended signed client; the client verifies the worker and a compatible response.
- [ ] A harmless request succeeds through Authorization Services and SMJobSubmit; cancellation and startup failure produce a usable, explicit outcome.
- [ ] Unused and completed workers exit; no persistent helper, daemon plist, login item or reboot registration remains.
- [ ] The existing disk engine is not invoked by this proof; existing installation paths remain unchanged.
- [ ] Record the candidate identity and results on the supported macOS floor and current supported macOS release, using the agreed small real-app integration harness.
- [ ] Obtain the applicable owner authority immediately before signing, notarization and privileged execution; a source-only mock does not satisfy this capability gate.
- [ ] If the approach fails qualification, retain the measured failure and alternatives rather than silently introducing a persistent daemon.

## Blocked by

None — can start immediately.
