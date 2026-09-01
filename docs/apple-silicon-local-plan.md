# Apple Silicon Local Execution Plan

Updated: 2026-08-24

## Operating constraints

- Work only on local, AI-tool-agnostic branches.
- Do not push or create upstream pull requests.
- Update this plan and `changelog.md` as work progresses and before handoff.
- Preserve Asahi-owned kernel, GPU, firmware, and boot state.

## Current objective

Preserve the proven M1 Pro implementation, its reproducible clean-install path,
and sufficient evidence to present the completed work without generalizing one
validated model into an unsupported all-model claim.

## Roadmap alignment

This plan executes the existing
[`apple-silicon-integration-roadmap.md`](apple-silicon-integration-roadmap.md);
it does not replace it. A phase is complete only when its documented exit gate
is met. Local prototype evidence may reduce a later phase's uncertainty without
advancing the official phase sequence.

- **Phase 1 — Runtime boundary: locally proven; promotion gate open.** The fork
  contains the Apple predicate, pre-mutation safety guards, neutral portability
  fixes, transaction checks, and package-input evidence. The formal gate remains
  open because these behaviors have not been reclassified against current
  upstream as an independently reviewable PR0–PR4 series. Under the current
  operating constraint, prepare the evidence locally but do not open PRs.
- **Phase 2 — Official ARM packages: local substitute proven; infrastructure
  blocked.** The signed bundle, ten pinned source recipes, empty-cache install,
  and 141/141 runtime closure prove the required transaction. They do not meet
  the gate requiring an official Omarchy-owned, signed aarch64 repository that
  installs and updates without the MX channel.
- **Phase 3 — Generic ARM64 media: seam demonstrated; build gate open.** The
  separate `omarchy-iso` reference branch proves a small architecture-target
  seam, but a reproducible generic ARM64 artifact cannot meet its official gate
  until Phase 2 provides the package feed.
- **Phase 4 — Apple backend and Asahi bridge: operational prototype; formal
  gate open.** The current installer, update protections, VM workflow, and
  working M1 Pro demonstrate the vertical path. Repeatable physical install,
  recovery, macOS-coexistence, and unsupported-layout evidence are still needed
  after the generic package/media foundations exist.
- **Phase 5 — Model-gated preview: one candidate model; not release-ready.** The
  M1 Pro is the first named reference device. A formal subsystem record,
  destructive-step allowlist guard, recovery result, support policy, and more
  representative hardware are required before an official preview claim.
- **Phase 6 — Standard signed channel: not started.** Migration remains gated on
  a stable official package channel and a successful model-gated preview. The
  local signed channel supplies migration fixtures, not the final destination.

Two lanes can therefore proceed without breaking the fixed dependency order:

1. **Promotion lane:** finish local Phase 1 evidence, define the Phase 2
   publication decision, then resume generic Phase 3 media work only when an
   official package feed exists.
2. **Incubation lane:** continue collecting Phase 4–5 M1 Pro install, recovery,
   update, and hardware evidence without representing those official gates as
   complete.

## Next three tracked milestones

- [ ] Produce the local Phase 1 promotion dossier.
  - Pin the current upstream and MX revisions.
  - Map each PR0–PR4 behavior to its current upstream owner, local implementation,
    focused tests, and remaining test gap.
  - Re-run the unchanged x86-64 baseline plus Apple and generic-aarch64 fixtures.
  - Exit: the proposed changes are independently reviewable locally, with no
    upstream branch, push, or PR.
- [ ] Produce the Phase 2 publication decision pack.
  - Convert the proven package closure into an official-channel contract:
    package owners, rebuild inputs, provenance, signing responsibility,
    repository metadata, update behavior, and CI publication requirements.
  - Separate the six mandatory binary outputs, ten source recipes, official
    repository packages, and optional transactions.
  - Exit: the infrastructure owner can make a go/no-go decision, and the
    acceptance command is a cold install and update using no MX repository.
- [ ] Complete the named M1 Pro Phase 4–5 evidence baseline in parallel.
  - Capture the structured subsystem checklist from the working machine.
  - Record boot-chain preservation, macOS coexistence, update, rollback, and
    recovery evidence; schedule any destructive reinstall test only in an
    explicitly approved hardware window.
  - Exit: one versioned device record states what passed, what was not tested,
    and which claims remain unsupported.

## Tracked steps

- [x] Inventory aarch64 package availability and dependency resolution.
  - Evidence: `docs/aarch64-package-parity.{md,json}`.
- [x] Provide and verify the signed six-package Apple Silicon release bundle.
  - Evidence: fresh installer and bundle-update tests.
- [x] Make the ten pinned source builds an explicit checked-in manifest.
  - Evidence: commit `8f102e88`; focused Asahi package tests pass.
- [x] Audit the disposable fresh-Asahi VM harness against the current installer.
  - Docker and KVM are present; Docker access needs approval in this sandbox.
  - The published bundle predates `omarchy-asahi-source.packages`, so the
    current candidate cannot be meaningfully tested against that payload
    without a local fixture adapter.
- [x] Add deterministic candidate/payload preflight to the VM harness.
  - Preserve verification of the published bundle unchanged, then supply the
    current source manifest only to the explicitly marked local candidate.
  - Focused syntax and package/installer tests pass.
- [x] Run the fresh package transaction from an empty package cache.
  - Record the bundle identity, pinned source revision, package failures, and
    complete command result in `changelog.md`.
  - Attempt 1 stopped before guest creation on a transient loop allocation
    error after successfully verifying and caching the ARM rootfs. A direct
    privileged-container reproduction attached the same sparse disk normally.
  - Attempt 2 installed all 664 repository packages, then the host lost SSH
    during post-transaction system reload hook 6/24. The harness destroyed the
    container before bundle/source validation because it had no out-of-band
    completion status.
  - Final evidence: signed sequence 18 completed all repository, bundle, and
    ten pinned-source transactions under the 3-GiB guest profile; reboot and
    safe-rerun verification passed.
- [x] Make the VM guest workflow survive expected network reloads.
  - Run it as a system-managed detached job and persist its full log plus an
    atomic exit-status file in the guest.
  - Reconnect and poll the explicit result; never infer success from transport
    loss.
  - Evidence: focused shell syntax/package/installer tests and
    `git diff --check` pass.
  - The first supervised execution proved failure propagation and log
    retention when a stale `.13` assertion rejected the newly published signed
    `.14` stable descriptor.
  - The sequence-18 retry survived the repository hooks and completed the
    signed bundle, but the host OOM killer terminated the 8 GiB QEMU guest
    before source builds. The harness now defaults to a configurable 4-vCPU,
    5-GiB guest and detects dead/zombie QEMU processes during result polling.
  - A 5-GiB retry built two source packages before another host OOM at
    `localsend`. Defaults are now 2 vCPUs/3 GiB, and a host-backed pacman cache
    avoids repeating verified package downloads across clean overlays.
- [x] Capture and compare the installed explicit package set with
  `install/omarchy-base-asahi.packages`.
  - Fail on missing required packages; explain permitted provider substitutions
    and protected Asahi packages.
  - Evidence: 141/141 runtime entries and 10/10 source entries are present in
    the retained 972-package database; both missing-package reports are empty.
  - Pacman selected `ardour` for `lv2-host`, `jack2` for `jack`, and
    `qt6-multimedia-ffmpeg` for the Qt media backend.
- [x] Verify first-boot essentials in the disposable VM.
  - Desktop/session, networking, audio, GPU acceleration, suspend boundary, and
    update safety each need evidence or a documented environment limitation.
  - SDDM rendered the Omarchy password greeter after reboot; remembered user
    and session state, NetworkManager+iwd, migrations, protected boot hashes,
    and updater state all passed automated verification.
  - Physical Apple GPU, Wi-Fi/audio devices, and suspend cannot be represented
    by this generic virtio VM; the running M1 Pro provides the real-hardware
    proof for the current implementation.
- [x] Validate the current physical Apple Silicon reference system.
  - Apple MacBook Pro (14-inch, M1 Pro, 2021), `aarch64`, Apple `j314s/t6000`.
  - The maintainer confirms that Omarchy and the normal desktop and hardware
    functions are working on this machine.
  - Read-only evidence captured the device, kernel, Asahi package, Mesa, and
    installed signed-release identity.
  - Detailed per-subsystem transcripts remain useful as a regression baseline,
    but are not a blocker to the current M1 Pro validation claim.
- [x] Prepare a DHH-facing presentation pack for the completed work.
  - Updated the executive status brief to reflect the completed clean install.
  - Added speaking notes, likely questions, bounded claims, and a technical
    evidence appendix.
  - Kept other-model validation and official-infrastructure work explicitly
    outside the completed M1 Pro claim.
  - Validation: all presentation-local links resolve and `git diff --check`
    passes.

## Known blockers and risks

- Official Omarchy aarch64 repository endpoints are unavailable; the local
  signed bundle is the current mandatory-package source.
- Source recipes may fail because of upstream changes even when their names are
  stable; builds are pinned so any failure is reproducible.
- A generic virtual machine cannot validate Apple hardware behavior. VM results
  cover package/install correctness; the current physical proof is limited to
  the validated M1 Pro and must not be generalized to every Apple model.
- The unrelated automatic-interface case in `network-qr-test.sh` currently
  fails in this environment and is outside the package transaction scope.

## Next action

Start the local Phase 1 promotion dossier by freezing the current upstream/MX
revisions and mapping PR0–PR4 behaviors to code and tests. In parallel, review
the DHH presentation pack for tone and capture non-destructive structured M1
Pro evidence when convenient. Do not push or open an upstream pull request.
