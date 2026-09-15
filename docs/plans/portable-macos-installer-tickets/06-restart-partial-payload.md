# Start over after partial partition or payload installation

## Parent

[Portable Omarchy Mac installer specification](../portable-macos-installer-spec.md)

## What to build

Extend the reviewed Start over journey to unfinished stub, ESP, boot and root partition or payload installation. A user can remove the proven failed attempt and begin a fresh approved installation even when the old complete-layout detector cannot recognize the partial result.

## Acceptance criteria

- [ ] Support attributable interrupted stub population, partial later-partition creation and partial payload writes without requiring a complete four-part installation layout.
- [ ] Extend the existing Start over review and cleanup contract from the preceding ticket rather than introducing another cleanup path.
- [ ] Reconcile durable evidence with actual disk identities; delete only resources created by the failed attempt and preserve all protected and pre-existing resources.
- [ ] An attempt with a completed valid Recovery handoff uses the existing handoff/retry path. A complete or subsequently used installation is not eligible for failed-attempt cleanup.
- [ ] Journal each cleanup effect and reconcile interruptions during cleanup; stale failure flags or partition labels alone never establish erase permission.
- [ ] Unknown or inconsistent evidence, unhealthy APFS, unexpected disk changes and active operations remain specific blockers.
- [ ] After successful cleanup, fresh inspection, plan review and authorization lead through the existing installation execution path without replaying an old shrink.
- [ ] Inject failure before and after later partition operations, during payload population and during cleanup; test the full reopen-review-cleanup-replan outcomes at existing seams.
- [ ] Run focused engine and Swift checks, rebuild and inspect representative later-stage Start over and blocked states.

## Blocked by

- [05: Start over after interrupted target preparation](05-restart-target-preparation.md)
