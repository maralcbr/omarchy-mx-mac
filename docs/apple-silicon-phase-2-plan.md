# Apple Silicon Integration — Phase 2 Package Publication Plan

> **Decision:** Phase 2 uses the existing public
> [`maralcbr/omarchy-pkgs`](https://github.com/maralcbr/omarchy-pkgs)
> repository to build and publish immutable ARM package candidates. Candidates
> are public GitHub prereleases. Promotion copies the exact accepted assets into
> a stable snapshot without rebuilding them.

This is a downstream package-publication and qualification system. It does not
claim official Omarchy media, upstream package ownership, or supported Apple
hardware.

## Outcome

Phase 2 replaces the current one-off 21-package snapshot with a repeatable,
auditable path:

1. build the complete reviewed repository closure on native GitHub-hosted ARM
   runners (expanded from 21 to 33 packages during dependency closure work);
2. sign every package and the repository metadata with a dedicated ARM
   repository signing subkey;
3. publish an immutable public candidate prerelease;
4. make this fork consume that exact release tag and descriptor digest;
5. prove dependency resolution and clean installation and upgrade transactions;
6. run fresh-system native-aarch64 VM acceptance locally; and
7. promote the exact accepted release assets without rebuilding.

The current x86-64 path and the externally owned Asahi kernel, firmware, device
trees, and boot policy remain out of scope.

## Verified starting position

The implementation begins with working evidence rather than a blank pipeline:

- `maralcbr/omarchy-pkgs` is public and the repository owner has admin access.
- The repository already contains the 12 ARM package sources that produce the
  current 21-package repository, transaction checks, release helpers, and an
  ARM GitHub Actions workflow.
- The current workflow builds all sources in one `ubuntu-24.04-arm` workspace,
  signs with the personal release key, and publishes a normal immutable release.
  Phase 2 must split those builds, replace the signing credential, and publish
  candidates as prereleases.
- The immutable release
  `asahi-packages-784daa3efaecfa81b5b4da888b524e6ec4574d24` contains all 21
  packages, detached signatures, `omarchy.db`/`omarchy.files`, and 50 assets.
  It is about 260 MB; the largest asset is about 165 MB.
- This fork currently pins that release tag and enforces signed packages with
  `SigLevel = Required DatabaseOptional`.
- Standard GitHub Actions use in this public repository currently has no paid
  minutes requirement. Durable packages belong in GitHub Release assets, not
  temporary Actions artifacts.
- A GitHub `ubuntu-24.04-arm` runner is approximately 4 CPU, 16 GB RAM, and
  14 GB SSD. The build must therefore use per-source matrix jobs instead of one
  workspace containing every build.
- The local Apple M1 Pro has 10 cores, 15 GiB RAM, and sufficient disk for the
  existing 96 GiB sparse VM image. With no swap, the VM should use about 6 GiB;
  an 8 GiB guest leaves too little host headroom.
- Docker CLI availability inside Codex does not prove host daemon readiness.
  `qemu-system-aarch64` is not currently visible and `/dev/kvm` is not exposed
  in the sandbox. QEMU/KVM must be verified or prepared on the host before the
  full-VM gate.

## Fixed decisions

- **Repository:** publish candidates and stable snapshots in
  `maralcbr/omarchy-pkgs`.
- **Candidate visibility:** use public GitHub prereleases.
- **Build topology:** one native ARM matrix job per package source, followed by
  an assembly/check job for the complete 33-package repository.
- **CI responsibility:** build packages; validate artifact architecture and
  completeness; generate and sign repository metadata; publish the immutable
  candidate; read it back; and run repository, dependency, clean-install, and
  upgrade transaction checks.
- **Local responsibility:** fresh-system native-aarch64 VM validation. Physical
  Apple Silicon hardware acceptance is deferred and is not a Phase 2 gate.
- **Signing:** store only a dedicated ARM repository signing subkey and its
  passphrase in GitHub Actions Secrets. Keep the personal master key out of
  Actions. Pin the public fingerprint as protected repository/environment
  configuration and force GnuPG to use that exact subkey.
- **Promotion:** download and verify the accepted candidate, then upload those
  exact bytes to the stable snapshot. Never invoke a build during promotion.
- **Coverage:** the gate is the complete current set of 33 repository packages
  plus six runtime packages. A partial repository or runtime bundle cannot be
  published or promoted.
- **Retention:** retain promoted stable snapshots indefinitely; retain at least
  the newest two unpromoted candidates and every unpromoted candidate younger
  than 14 days; retain failed candidates for 7 days unless linked to an
  unresolved defect; retain temporary Actions artifacts for 1 day.

## Candidate contract

Every candidate is identified by both an immutable Git tag and the SHA-256 of a
small signed release descriptor. The descriptor records at least:

- schema version, candidate tag, and source commit;
- package source revisions and the expected repository package count (`33`),
  plus the separately checksummed six-package runtime bundle;
- each package filename, architecture, version, SHA-256, and signature filename;
- the repository database/files filenames and SHA-256 values;
- the exact signing subkey fingerprint;
- the build workflow run and native runner architecture; and
- the repository inputs used by dependency resolution.

The descriptor and its detached signature are release assets and are included
in `SHA256SUMS`. After publication, CI downloads the public assets, verifies the
descriptor digest and signature, compares the complete asset inventory, and
performs tests from the downloaded copy. Local acceptance records the candidate
tag and descriptor digest, not merely a branch or commit.

The fork must reject a candidate when the tag, descriptor digest, signer,
package count, package checksum, or repository metadata checksum differs. The
existing stable pin remains the default until a candidate passes every gate.

## Implementation sequence

Code review, candidate publication, local acceptance, and stable promotion are
separate authority boundaries. Merging workflow support does not publish or
promote a release.

### P2-PR1 — Candidate build topology and inventory

**Repository:** `maralcbr/omarchy-pkgs`.

- Generate the matrix from the checked-in package-source inventory.
- Build one source per native ARM job and upload only its package archives as a
  one-day temporary artifact.
- Fan the artifacts into a clean assembly job and require exactly the checked-in
  list of 33 repository package names, with no duplicates or unexpected
  archives.
- Reject non-`aarch64`/`any` artifacts and preserve `.PKGINFO`, `.BUILDINFO`,
  source revision, build log, and checksums as evidence.
- Generate an unsigned repository only for pre-publication dependency and
  transaction checks; signing happens in the protected publication job.

**Gate:** all 33 repository packages build independently and the assembled
repository passes completeness, architecture, dependency-resolution, and
clean-transaction tests. Existing package-reuse and manifest tests remain
green.

### P2-PR2 — Dedicated signing and immutable candidate prerelease

**Repository:** `maralcbr/omarchy-pkgs`.

- Replace the personal release-key secret with a dedicated ARM repository
  signing-subkey secret and passphrase.
- Require the configured fingerprint, verify that the imported secret material
  can sign as that exact subkey, and use the `fingerprint!` GnuPG selector.
- Sign all 33 repository packages, the six runtime packages, and `omarchy.db`
  and `omarchy.files` metadata.
- Produce and sign the candidate descriptor and `SHA256SUMS`.
- Publish `asahi-packages-candidate-<source-commit>` as an immutable public
  GitHub prerelease, then verify the public readback independently.
- Set every temporary artifact retention period to one day.

**Gate:** a dry run succeeds without a publishing credential; the protected
publish job refuses the personal master fingerprint, incomplete secret
material, a partial repository, an existing tag, or a mismatched public
readback. No candidate is published while implementing or reviewing the PR.

### P2-PR3 — Exact candidate consumption and CI lifecycle tests

**Repositories:** this fork and `maralcbr/omarchy-pkgs`.

- Add an explicit candidate input consisting of release tag plus descriptor
  SHA-256. Do not silently follow `latest`, a branch, or a mutable URL.
- Verify the descriptor signature and dedicated subkey fingerprint before
  changing pacman configuration.
- Configure the release-asset repository only after descriptor and complete
  asset validation; keep `SigLevel = Required DatabaseOptional` or stronger.
- Run dependency resolution, a clean installation of the full required
  transaction, an upgrade from the previous accepted snapshot, and a no-op
  second upgrade against assets downloaded from the public prerelease.
- Confirm that PC boot packages are not introduced and approved Asahi
  repositories are preserved.

**Gate:** CI proves install and upgrade from the exact public candidate and the
fork records the tag, descriptor digest, and signer as reviewable inputs.

### P2-PR4 — Local fresh-system VM acceptance

**Execution host:** the local Apple Silicon machine.

- Verify host-side QEMU availability and the usable acceleration path outside
  the Codex sandbox. If KVM is unavailable on the host, record the slower TCG
  path rather than treating sandbox isolation as a hardware failure.
- Use an approximately 6 GiB aarch64 guest and close memory-heavy applications
  before running it.
- Install a fresh system from the exact candidate tag/digest, reboot, update
  from the previous accepted snapshot, and capture package/signature evidence.
- Store a reviewed, checksum-pinned acceptance record containing candidate
  identity, execution-host and guest identity, test versions, results, known
  defects, and evidence locations.
- Record physical boot, display/GPU, input, networking, audio, suspend/resume,
  and shutdown behavior as deferred and untested. Do not present VM acceptance
  as evidence for those hardware-specific capabilities.

**Gate:** the native-aarch64 VM acceptance passes with no unresolved release-
blocking defect. Physical hardware acceptance is optional follow-up evidence,
not a Phase 2 promotion gate.

### P2-PR5 — Byte-identical promotion and retention

**Repository:** `maralcbr/omarchy-pkgs`; protected manual environment.

- Require the accepted candidate tag, descriptor digest, and local acceptance
  record as promotion inputs.
- Download assets from the public candidate, verify all signatures and
  checksums, and compare their inventory with the signed descriptor.
- Create the stable snapshot by uploading the same bytes. The promotion job has
  no checkout, compiler, package builder, or rebuild step.
- Read the stable assets back and prove that each byte hash matches the
  candidate before marking the release promoted.
- Apply retention conservatively: stable snapshots are never deleted; keep the
  newest two unpromoted candidates even when older than 14 days, and keep all
  unpromoted candidates younger than 14 days; keep failed candidates for at
  least 7 days and indefinitely while an unresolved defect references them.
  Default to retention when defect status cannot be determined.

**Gate:** the stable descriptor and every stable package/database asset have
the same SHA-256 as the accepted candidate, and a final clean install and
upgrade read only stable release assets.

## Phase 2 completion gate

Phase 2 is complete only when:

- all 33 repository package outputs and six runtime package outputs are built
  and checked in isolated native ARM jobs;
- the dedicated ARM signing subkey is the only private signing material
  available to Actions and its public fingerprint is pinned;
- an immutable public candidate passes independent public readback;
- this fork consumes the exact candidate tag and descriptor digest;
- clean dependency, install, and upgrade transactions pass against downloaded
  public assets;
- fresh-system native-aarch64 VM acceptance passes locally, with physical
  hardware behavior explicitly recorded as deferred and untested;
- promotion copies the accepted bytes without rebuilding and stable readback
  proves byte identity;
- the retention policy is automated, conservative on uncertainty, and covered
  by dry-run tests; and
- no user-facing text expands the result into an official upstream or supported
  Apple hardware claim.

Any failed item leaves Phase 2 open. A local package build, a container install,
or a candidate prerelease alone is not sufficient.

## Immediate implementation boundary

The first safe implementation slice is P2-PR1 plus the non-secret scaffolding
of P2-PR2. It may change and test workflow code, descriptor generation, and
release validation, but it must not create GitHub Secrets, publish a release,
delete an old candidate, or promote a stable snapshot. Those are explicit
operator actions after review.

## Implementation status

The safe, non-publishing implementation slice is now present on the Phase 2
branches:

- `maralcbr/omarchy-pkgs` builds all 24 reviewed sources as a native ARM
  matrix, assembles the complete 33-package repository and six-package runtime
  bundle, and exercises signed clean-install and previous-snapshot upgrade
  transactions in disposable containers;
- production publication validates that the imported credential is a dedicated
  secret signing subkey, rejects the personal release fingerprint, and forces
  the exact subkey selector;
- this fork can verify a downloaded candidate offline against its exact tag,
  descriptor digest, public signing-subkey fingerprint, signatures, checksums,
  package count, and closed asset inventory without changing pacman state;
- promotion and retention are implemented as dry-run-first operator tools;
  promotion requires a matching acceptance record and verifies byte identity,
  while retention preserves stable releases and defaults to keeping uncertain
  candidates; and
- an immutable public candidate was published for source commit
  `a9bf4e5da273af2d4b432b3e0b123f74f3c5b933`, independently read back, and
  consumed by the fork using its exact tag, descriptor digest, and dedicated
  signing subkey;
- an Apple M4 Pro host ran the 10-vCPU, 12 GiB native-aarch64 VM gate. The
  fresh encrypted ISO install, reboot and disk unlock, compositor shortcut
  checks, graphical acceptance suite, services, runtime tools, and exact ARM
  VM package profile all passed; and
- physical Apple Silicon behavior is intentionally deferred and is not a
  promotion gate. GPU, Wi-Fi, audio, input, suspend/resume, and shutdown remain
  unqualified by this Phase 2 acceptance record.

The accepted candidate was promoted without rebuilding to the immutable stable
snapshot
`asahi-packages-stable-a9bf4e5da273af2d4b432b3e0b123f74f3c5b933`.
Independent public readback found the same 91 asset names and SHA-256 digests as
the candidate. The existing channel and installer endpoint were not changed,
so publication did not change the active Omarchy session or current online
installs. Under the VM-only acceptance policy recorded above, the Phase 2
publication system is complete; physical hardware qualification remains
optional follow-up work.

## Research basis

- [Six-phase integration roadmap](apple-silicon-integration-roadmap.md)
- [Detailed Phase 1 plan](apple-silicon-phase-1-plan.md)
- [`maralcbr/omarchy-pkgs`](https://github.com/maralcbr/omarchy-pkgs)
- [GitHub hosted runners](https://docs.github.com/actions/using-github-hosted-runners/using-github-hosted-runners/about-github-hosted-runners)
- [GitHub release management](https://docs.github.com/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
- [Asahi distribution guidelines](https://asahilinux.org/docs/alt/policy/)
- [MX signed repository evidence](releases/v4.0.0-mac.15.md)

Verified decision and environment snapshot: 2026-08-24.
