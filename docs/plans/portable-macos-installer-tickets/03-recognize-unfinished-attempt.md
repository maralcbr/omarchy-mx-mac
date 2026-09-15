# Recognize unfinished installations when the app reopens

## Parent

[Portable Omarchy Mac installer specification](../portable-macos-installer-spec.md)

## What to build

When an installation is interrupted, reopening the app identifies its last known attempt before offering a new plan. It distinguishes an unfinished attempt, a still-running operation, a valid Recovery handoff and a complete installation, and explains uncertainty without changing disk contents.

## Acceptance criteria

- [ ] Before the first disk mutation, persist a protected attempt identity bound to the approved plan, disk, original partition inventory, protected macOS/recovery identities and target extent.
- [ ] Durable intent and observed results cover individual partition-changing operations with stable partition/container identities; the records do not rely solely on current coarse checkpoints.
- [ ] Inspection and the UI expose unfinished and still-active states before normal fresh-install planning; inspecting or dismissing the state causes no cleanup.
- [ ] A complete stage-one Recovery handoff is not misclassified as failed merely because Recovery has not finished; complete or subsequently used installations remain protected.
- [ ] Missing or corrupt provenance, changed identities, unexpected partitions and unhealthy APFS state produce explicit blockers instead of guessed ownership.
- [ ] Previously active engine children remain covered by the execution guard; UI disconnection cannot authorize a new operation.
- [ ] Exercise the complete record-interrupt-reopen journey at the existing session and engine seams, using real journal decoding and failure injection around each mutation boundary.
- [ ] Run focused engine and Swift checks, rebuild and inspect the unfinished, active, Recovery and blocked states. Start over is not enabled by this ticket.

## Blocked by

- [02: Run an approved installation through the temporary worker](02-install-with-temporary-worker.md)
