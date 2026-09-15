# Run an approved installation through the temporary worker

## Parent

[Portable Omarchy Mac installer specification](../portable-macos-installer-spec.md)

## What to build

Use the normal installer journey to inspect, plan, review, authorize and run an installation with a temporary worker, then present the existing Recovery handoff and retire the worker. Handle credential correction and narrow Recovery authorization retry in the same bounded session. This is a local implementation slice; broad release remains blocked by the later interruption and qualification tickets.

## Acceptance criteria

- [ ] Normal app actions obtain temporary-worker readiness instead of requiring a previously installed PKG helper; startup, authorization denial and incompatible peers have specific UI outcomes.
- [ ] Mutual signing checks, root-owned handoff import, exact-plan validation, supported-model restrictions, asset verification and credential clearing remain effective.
- [ ] A worker remains available through harmless checks, rejected credentials and reviewed removal previews, and retires after the bounded request sequence finishes.
- [ ] Native administrator authorization and machine-owner/Recovery credentials remain distinct; no unsupported one-password promise is introduced.
- [ ] One machine-wide execution guard prevents concurrent disk mutators from different copies, users, replacement workers or surviving engine children.
- [ ] An incompatible active legacy helper blocks disk work without being migrated, unloaded or deleted by the app.
- [ ] Successful stage one produces the existing independent Recovery handoff; Recovery-authorization retry does not replay disk work and the existing explicit removal feature remains usable.
- [ ] Use the existing session, XPC submission and trusted executor tests to prove happy, denied, mismatched, busy and failed outcomes; test cross-process exclusion with harmless work.
- [ ] Run applicable focused checks, rebuild and inspect the affected UI in one review app. Physical installation proof is reserved for the candidate qualification ticket.

## Blocked by

- [01: Prove temporary privileges from a downloaded app](01-temporary-helper-proof.md)
