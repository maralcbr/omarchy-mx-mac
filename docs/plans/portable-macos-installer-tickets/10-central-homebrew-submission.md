# Submit and validate central Homebrew Cask distribution

## Parent

[Portable Omarchy Mac installer specification](../portable-macos-installer-spec.md)

## What to build

Submit the already tested Cask against the immutable public ZIP to central Homebrew Cask, work through maintainer review, and establish the accurate Homebrew install-and-open experience. Central acceptance is an upstream decision and is recorded separately from submission.

## Acceptance criteria

- [ ] Use the canonical public homepage, real versioned ZIP URL, final checksum and appropriate platform declarations for the same qualified app.
- [ ] Run the required Cask checks and audit, plus installation, explicit launch and uninstallation checks against public bytes.
- [ ] Verify Cask lifecycle actions do not start Omarchy disk operations, register persistent installer services or erase Omarchy/essential attempt evidence.
- [ ] Submit to central Homebrew Cask under the applicable publication authority; retain the upstream review URL and handle actionable review feedback.
- [ ] Do not substitute a custom tap or a custom execution framework as the completed target.
- [ ] Record whether the Cask is submitted, accepted, or held by a specific upstream blocker; do not mark central availability complete merely because a pull request exists.
- [ ] After acceptance, verify installation through the central token and publish the final install-and-open instructions. If acceptance is blocked externally, retain the unresolved status and concrete next action.

## Blocked by

- [09: Publish the qualified ZIP as the direct download](09-publish-direct-download.md)
