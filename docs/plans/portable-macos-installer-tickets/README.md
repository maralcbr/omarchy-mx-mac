# Portable Mac installer tickets

The specification and tickets are maintained in this repository. GitHub issues #88–#98 were deleted on 2026-09-11 using the owner’s `maralcbr` account; the repository is now the source of truth. This move does not mark any implementation work complete.

- [Specification](../portable-macos-installer-spec.md)
- [Implementation plan](../portable-macos-installer-plan.md)

| Ticket | Blocked by |
| --- | --- |
| [01: Prove temporary privileges from a downloaded app](01-temporary-helper-proof.md) | None |
| [02: Run an approved installation through the temporary worker](02-install-with-temporary-worker.md) | [01](01-temporary-helper-proof.md) |
| [03: Recognize unfinished installations when the app reopens](03-recognize-unfinished-attempt.md) | [02](02-install-with-temporary-worker.md) |
| [04: Stop safely when the installer quits or loses its UI](04-stop-at-operation-boundary.md) | [03](03-recognize-unfinished-attempt.md) |
| [05: Start over after interrupted target preparation](05-restart-target-preparation.md) | [03](03-recognize-unfinished-attempt.md) |
| [06: Start over after partial partition or payload installation](06-restart-partial-payload.md) | [05](05-restart-target-preparation.md) |
| [07: Build the portable ZIP and Homebrew review candidate](07-portable-release-candidate.md) | [04](04-stop-at-operation-boundary.md), [06](06-restart-partial-payload.md) |
| [08: Qualify installation and Start over on supported hardware](08-qualify-exact-candidate.md) | [07](07-portable-release-candidate.md) |
| [09: Publish the qualified ZIP as the direct download](09-publish-direct-download.md) | [08](08-qualify-exact-candidate.md) |
| [10: Submit and validate central Homebrew Cask distribution](10-central-homebrew-submission.md) | [09](09-publish-direct-download.md) |

## Migration record

The `github-archive` directory preserves the exact issue bodies, original states, labels, assignees, comments, timestamps and publication dependency mapping captured before deletion on 2026-09-11. There were no issue comments. Historical GitHub URLs in that archive are provenance, not active work links. The specification also retains the owner’s newer local clarification to preserve the existing installer UI.

The initial attempt used the wrong account and was rejected. After switching to `maralcbr`, all eleven deletions succeeded and their absence was verified. Unrelated issues were left untouched. See `github-archive/deletion-results.json`.
