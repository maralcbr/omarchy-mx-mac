# Start over after interrupted target preparation

## Parent

[Portable Omarchy Mac installer specification](../portable-macos-installer-spec.md)

## What to build

A user whose attempt stopped during macOS resizing or creation of the Omarchy target can review Start over, clean up only the resources proven to belong to that early attempt, and approve a fresh installation. Cleanup itself is safe to interrupt from the first version of this feature.

## Acceptance criteria

- [ ] Recognize and reconcile the bounded early-attempt cases: no completed disk change, already freed space, or an attributable Omarchy APFS target before later partition/payload installation.
- [ ] Show the exact cleanup proposal and require explicit confirmation; declining leaves the attempt unchanged.
- [ ] Require machine-wide exclusion and revalidate disk identity, ownership and the reviewed cleanup proposal immediately before any cleanup mutation.
- [ ] Remove only proven attempt-owned target resources. Preserve original macOS and Apple recovery identities, unrelated partitions and all pre-existing installations.
- [ ] After cleanup, reinspect and require a fresh installation plan and approval; reuse valid freed space and never blindly repeat the previous macOS shrink.
- [ ] Journal cleanup intent and observed results; interruption before or after each cleanup effect can be reconciled on the next launch without repeated arbitrary deletion.
- [ ] Later-stage, ambiguous, corrupt, externally changed or still-active attempts remain blocked with a specific explanation.
- [ ] Prove the review-confirm-cleanup-replan journey and interruption cases through existing session and engine boundaries; rebuild and inspect the review, declined and blocked states.

## Blocked by

- [03: Recognize unfinished installations when the app reopens](03-recognize-unfinished-attempt.md)
