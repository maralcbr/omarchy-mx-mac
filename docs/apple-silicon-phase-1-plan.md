# Apple Silicon Integration — Detailed Phase 1 Plan

> **Decision:** approve a small upstream PR series that recognizes Apple
> Silicon, prevents known unsafe mutations, extracts neutral improvements, and
> defines the package-input boundary needed by later phases. Recognition in
> Phase 1 is explicitly **not** an installation or support claim.

## Outcome and constraints

Phase 1 moves only proven, immediately useful behavior from Omarchy MX Mac onto
a fresh branch from current `basecamp/omarchy` Quattro. It does not merge the
fork. Every change must be independently explainable, testable on fixtures, and
safe for the existing x86-64 product.

At the Phase 1 exit:

- Official Omarchy can distinguish Apple Silicon from x86-64 and generic ARM.
- Covered runtime and setup paths fail before overwriting Asahi-owned state.
- Architecture-neutral fixes work without an Apple-specific support claim.
- Optional install actions reflect the complete transaction available from the
  configured repositories.
- Package and media teams have a minimal input contract to evaluate in Phase 2.

Phase 1 does **not** include an Apple installer, ARM media, official ARM package
publication, signed Mac updates, Mac branding, device support promises, a
wholesale fork merge, or a final package schema.

## Execution model

Use the MX repository as a behavioral evidence set. For each candidate change,
identify its current upstream owner, extract the smallest coherent patch, port
the relevant fixtures, and review it against current upstream rather than
preserving the fork’s historical commit or file layout.

The sequence is dependency ordered. PR0 prepares the evidence; PR1 establishes
the platform boundary; PR2 and PR3 upstream independent reusable behavior; PR4
records the inputs that later package and media work will consume. Each PR must
remain mergeable if later work is delayed or declined.

## PR0 — Rebase and classify the evidence

**Purpose.** Replace the long-lived-fork comparison with a current, reviewable
inventory against upstream Quattro.

**Prerequisites.** Current `basecamp/omarchy` Quattro and the MX commits, files,
and tests identified by the 2026-08-23 readiness review.

**Included work.** Create a fresh upstream branch; classify MX changes by
behavior and current owner; separate Apple-only safety behavior from neutral
fixes, installation, packages, updates, and branding; identify upstream drift;
and map every Phase 1 behavior to a focused test or a documented test gap.

**Non-goals.** Do not merge or rebase the MX branch into upstream, preserve
historical commit structure for its own sake, or port code before its current
upstream consumer is confirmed.

**Evidence and tests.** Record the upstream revision, MX source revision, and
behavior-to-test mapping. Run the upstream focused CLI and shell baseline before
any extracted code is applied.

**Review boundary.** Evidence and patch planning only; no Apple support claim
and no unrelated fork cleanup.

**Exit criterion.** Every proposed PR1–PR4 behavior has a current upstream
owner, an explicit inclusion decision, and a test strategy. Reviewers can
assess the series without reading the full fork history.

## PR1 — Recognize Apple Silicon and protect platform state

**Purpose.** Give shared runtime code one reliable Apple Silicon predicate and
use it where existing x86 behavior could overwrite Apple/Asahi-owned state.

**Prerequisite.** PR0’s current-upstream inventory. PR1 must be based directly
on upstream Quattro and must not depend on MX release or installer code.

### Detector contract

Add `bin/omarchy-hw-apple-silicon` with the required Bash shebang and explicit
command metadata:

```bash
#!/bin/bash

# omarchy:summary=Detect whether the computer is an Apple Silicon Mac.
```

The command is an exit-code predicate:

- Exit successfully only when `uname -m` reports `aarch64` **and**
  `/proc/device-tree/compatible` contains an `apple,` compatibility string.
- Exit non-zero for x86-64, generic aarch64, missing device-tree data, or unreadable
  compatibility data.
- Produce no normal output; callers use it directly in conditionals.
- Permit a test-only proc root override, matching the established MX fixture
  approach, so tests never depend on the host machine.
- Keep architecture and platform independent. `aarch64` alone must never imply
  Apple Silicon.

The `hw-` prefix already belongs to the Hardware command group; no new command
group or alias is required.

### Guard placement and behavior

Apply the detector only to current consumers with a proven safety requirement:

- **Repository and channel changes.** Guard `omarchy-channel-set` and
  `omarchy-refresh-pacman` before checkout creation, backup, package-manager,
  repository, or mirror mutation. Explain that official Omarchy package
  channels are not yet available for Apple Silicon and that existing Arch Linux
  ARM/Asahi repositories are being preserved.
- **Direct boot.** Guard `omarchy-setup-direct-boot` before EFI inspection or
  `efibootmgr` mutation. Direct users to the Apple boot flow supplied by Asahi
  without attempting to model it in runtime code.
- **Platform-owned configuration.** Skip only installation or refresh steps
  proven to assume the x86 filesystem, repository, service, or boot model. Each
  skip needs its own regression test; the detector must not become a broad
  “skip all setup” switch.
- **Broadcom firmware policy.** Exclude Apple Silicon from Intel/T2 Mac
  `brcmfmac` quirks before configuration or migration writes. Preserve existing
  Intel Mac behavior.
- **Vulkan selection.** Select `vulkan-asahi` from the platform predicate rather
  than a PCI vendor string that can conflate unrelated hardware.

Every rejecting command must test the platform before its first mutation,
return non-zero, and provide a specific error. Tests must treat calls to `sudo`,
the package manager, Git checkout operations, boot tools, and config writes as
mutations and prove that none occurred.

### PR1 test matrix

- Positive detector fixture: `aarch64` plus Apple device-tree compatibility.
- Negative detector fixture: identical Apple data with `x86_64` architecture.
- Negative detector fixture: `aarch64` plus a non-Apple compatibility string.
- Negative detector fixture: missing or unreadable compatibility data.
- Pre-mutation tests for package/channel refresh and direct boot.
- Focused tests for each platform-owned configuration skip.
- Apple exclusion and unchanged Intel/T2 behavior for the Broadcom quirk.
- Apple selection and unchanged Intel/AMD behavior for Vulkan.
- Command metadata and routing validation for the new `hw-` command.
- Full focused CLI and shell suites on x86-64, plus fixture-driven Apple and
  generic ARM coverage.

### PR1 non-goals

Do not add the MX signed bundle updater, Apple installer/bootstrap, package
manifests, release signing, Mac branding, support documentation, a boot-backend
field, an artifact/media field, or a broad `apple-silicon` target object.

### PR1 review boundary

Reviewers should be able to answer two questions from the patch alone: is the
predicate specific enough to avoid generic ARM, and does every guarded path
stop before mutation? Any abstraction without an immediate consumer moves out
of this PR.

### PR1 exit criterion

Apple Silicon is recognized in fixtures; covered unsafe operations fail with
clear messages before changing state; generic ARM is not misclassified; Intel
Mac and x86-64 behavior is unchanged; and no official Apple install, release,
or hardware-support claim exists.

## PR2 — Upstream architecture-neutral fixes

**Purpose.** Move reusable fixes that are valid beyond Apple Silicon without
coupling them to the new detector.

**Prerequisites.** PR0’s classification. PR1 is conceptually prior but should
not be a code dependency unless a specific neutral fix truly consumes the
platform predicate.

**Included work.** Generalize battery discovery around UPower’s reported native
path; accept arbitrary battery directory names instead of hard-coded `BAT*` or
`macsmc-battery*`; read charge thresholds and cycle count from that resolved
path; retain safe behavior for absent or partially populated devices; and
extract any other neutral fix with a non-Apple justification and focused test.

**Non-goals.** No Apple platform branches, Apple-only package selection,
branding, or opportunistic cleanup unrelated to a demonstrated portability
problem.

**Evidence and tests.** Fixtures for standard `BAT0`, `macsmc-battery`, and an
arbitrary native path such as `CMB0`; absent battery; missing optional metrics;
charge thresholds; cycle count; and existing shell output compatibility.

**Review boundary.** One architecture-neutral behavior per coherent patch. The
commit message and tests must explain the generic portability benefit.

**Exit criterion.** Battery reporting works for arbitrary UPower native paths,
existing systems retain their output, and the change makes no Apple support
claim.

## PR3 — Resolve complete optional-package transactions

**Purpose.** Stop menus and optional installers from offering actions that the
configured repositories cannot complete on the current architecture.

**Prerequisites.** PR0’s package inventory and current upstream optional-install
entry points. Official ARM repository publication is not required.

**Included work.** Provide a repository-availability predicate; evaluate the
entire package transaction for an optional install rather than only its lead
package; encode required and architecture-specific package inputs in one
maintained source; make installers use the transaction result; and hide menu
actions that cannot resolve.

**Non-goals.** Do not publish an ARM repository, silently substitute unrelated
packages, make AUR availability equivalent to official repository availability,
or redesign every package manifest.

**Evidence and tests.** Unit fixtures for available and unavailable packages;
multi-package transactions where a secondary dependency is absent; menu
visibility; installer refusal before mutation; x86-64 compatibility; aarch64
repository resolution; and, where infrastructure permits, a disposable Asahi
VM validation of the optional package set.

**Review boundary.** Availability and transaction truth only. Package rebuilds,
repository signing, and publication belong to Phase 2.

**Exit criterion.** Every covered optional action shown to a user resolves as a
complete transaction against configured repositories, and unavailable actions
are hidden or fail before mutation with a clear explanation.

## PR4 — Freeze the package-input boundary

**Purpose.** Give `omarchy-pkgs` and `omarchy-iso` one measured input contract
for Phase 2 design without prematurely selecting a durable schema.

**Prerequisites.** PR0’s manifest comparison, PR3’s transaction behavior, and a
resolved package inventory from the repositories expected to serve official
aarch64.

**Included work.** Document a deterministic target query whose logical outputs
are:

- core packages shared by the product;
- platform-specific packages;
- packages excluded for the selected architecture/platform;
- optional package transactions; and
- provenance for every inclusion, exclusion, or provider decision.

Record the independent input dimensions as
`architecture: x86_64 | aarch64` and
`platform: generic | apple-silicon`. Define consumer expectations, ordering,
diagnostics, and representative examples only where measured package data
supports them.

**Non-goals.** Do not add `boot_backend` or artifact/media type to the runtime
contract, finalize a serialization or storage schema, build Apple media,
publish packages, or make Apple the default/only aarch64 platform.

**Evidence and tests.** Resolve representative x86-64/generic,
aarch64/generic, and aarch64/Apple inputs; prove deterministic output and
provenance; reject unsupported combinations clearly; and compare the result
with the duplicated MX manifests to account for every difference.

**Review boundary.** This PR freezes required information and consumer
responsibilities, not the final wire format. Boot stack and media remain
installer-owned.

**Exit criterion.** Package and media maintainers can evaluate Phase 2 using
one unambiguous set of target inputs, with every package decision traceable to
source evidence and no competing installer contract introduced.

## Phase 1 integration gate

Phase 1 is complete only when all of the following are true:

- The PR0–PR4 work is based on current upstream and remains reviewable as
  independent changes rather than a fork merge.
- Existing x86-64 install, update, menu, battery, firmware, and graphics tests
  remain green.
- Apple detection has positive and negative fixtures, including generic ARM.
- Every guarded path proves it fails before its first mutation.
- Intel/T2 Mac behavior remains covered and distinct from Apple Silicon.
- Optional actions reflect complete transactions from configured repositories.
- The package-input boundary preserves independent architecture and platform
  dimensions and leaves boot/media choices to installers.
- User-facing copy says that Apple Silicon is recognized but not yet officially
  installable or supported.
- The roadmap and research record identify Phase 2 as a separate go/no-go
  decision.

If any condition fails, Phase 1 remains open; failure does not authorize
pulling package publication, installer work, or support claims forward.

## Risks and review responses

**Upstream drift.** Reconfirm consumers and test entry points in PR0; port
behavior, not stale file placement.

**Over-broad platform checks.** Require an immediate consumer and a focused
negative fixture for every check. Prefer local, pre-mutation guards over a
global mode switch.

**Accidental support signaling.** Use “recognized” and “protected”; keep install,
release, compatibility, and model claims out of code metadata and user docs.

**Generic ARM regression.** Make `aarch64` insufficient for Apple detection and
include a non-Apple device-tree fixture in the detector suite.

**Premature package abstraction.** Freeze required outputs only after resolving
real package transactions; defer the schema until package and media consumers
can review it together.

**Asahi ownership erosion.** Treat boot policy, firmware, kernel, device trees,
and platform repositories as external invariants. Runtime guards preserve that
state; they do not take it over.

## Research basis

- [Six-phase integration roadmap](apple-silicon-integration-roadmap.md)
- [`omarchy-iso` generic aarch64 plan](https://github.com/omacom-io/omarchy-iso/blob/quattro/plans/aarch64-support.md)
- [Asahi distribution guidelines](https://asahilinux.org/docs/alt/policy/)
- [Asahi boot process](https://asahilinux.org/docs/alt/boot-process-guide/)

Research snapshot: 2026-08-23.
