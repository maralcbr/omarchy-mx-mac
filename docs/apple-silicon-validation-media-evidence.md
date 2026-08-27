# Apple Silicon validation-media evidence plan

Status: first static candidate validated locally; boot and release remain unverified
Official-source check: 2026-08-27

## Scope and non-goals

This plan defines the evidence required to call an `omarchy-mx-mac` AArch64
candidate **build-valid** and, later, **boot-valid** through an Asahi-prepared
Apple Silicon boot chain. The 2026-08-27 candidate below passes the recorded
static layout checks only; it does not yet satisfy the complete build-valid or
boot-valid gates.

Repository roles must remain distinct:

- `maralcbr/omarchy-mx-mac` owns the product decision and evidence record.
- `omarchy-iso` and `omarchy-pkgs` may supply ISO and package inputs only after
  their exact repositories and revisions are recorded.
- `omarchy-mac` is a historical reference fork only and is not an input,
  synchronization target, or release authority.

This document does **not** authorize fetching or changing repositories,
downloading dependencies, building or writing media, installing an Asahi UEFI
environment, changing a LocalPolicy, booting a Mac, touching an internal disk,
using credentials, signing, notarizing, publishing, or enabling an installer.

The standard Asahi removable-media route is an AArch64 installer on a FAT32 EFI
System Partition using the UEFI boot protocol. The UEFI-only environment loads
that media through m1n1 and U-Boot; a USB rescue/installer ESP contains
`/EFI/BOOT/BOOTAA64.EFI`, not its own `m1n1/boot.bin`.
([Open OS Platform Interoperability](https://asahilinux.org/docs/platform/open-os-interop/),
[Asahi Boot Process](https://asahilinux.org/docs/alt/boot-process-guide/))

## Current upstream constraint

As of the source check above, Asahi's official M4 feature page marks
**Installer: no** for M4 and M4 Pro/Max MacBook Pro models. Its official device
list maps the 14-inch M4 Pro MacBook Pro to `Mac16,8` / `J614sAP` / `T6040`.
Asahi's 2026-08-26 progress report says M4 NVMe support has advanced, but also
says the remaining support is insufficient and M4 machines are not ready to be
enabled in the installer.
Therefore a build may be evaluated without hardware, and a removable-media
boot may later be demonstrated on an explicitly supported canary, but neither
is M4 acceptance. No M4 boot attempt or enablement should be scheduled while
that official installer status remains `no`.
([M4 feature support](https://asahilinux.org/docs/platform/feature-support/m4/),
[device list](https://asahilinux.org/docs/hw/devices/device-list/),
[August 2026 progress report](https://asahilinux.org/2026/08/progress-report-7-2/))

This status is time-sensitive. Recheck both official pages on the day of any
future canary proposal and retain the page URLs, retrieval time, and relevant
status excerpt in the evidence bundle.

## Static candidate checkpoint - 2026-08-27

Candidate `2026-08-27-9885cf7d` was built from source `cb26f81` and then
verified with the format-aware verifier at source `50d9771` in the dedicated
`phase3-arm-build` AArch64 Lima VM. No media was written or booted, and no
package, release, channel, remote branch, installed application, user
configuration, internal disk, LocalPolicy, or existing-user path was changed.

Exact identities:

- ISO repository: `maralcbr/omarchy-iso`, local branch
  `feature/apple-validation-media-rebase`;
- accepted ARM64 base:
  `b5d562f` (`release/v4.0.1-arm64-iso`, tag `v4.0.1.m.1`);
- ISO build source:
  `cb26f81dbe66b4bf9b31f564f334ba0287a3a164`;
- static-layout verifier source:
  `50d97710347d82e61b420658d23173c210c46d60`;
- ArchISO submodule:
  `424e78130db2af6c1ceb55b442d7914b1109ff2b`;
- build image:
  `menci/archlinuxarm@sha256:1245992a2b371b5aeeede7dae44937ab29dc446e9e77abe263b99b02e5c1813d`;
- embedded `SOURCE_DATE_EPOCH`: `1787832096` (`2026-08-27T12:01:36Z`);
- command:
  `./bin/omarchy-iso-make --target aarch64/apple-silicon --apple-media-validation-build --keep-pkg-cache --no-cache --no-boot-offer`;
- artifact: `omarchy-2026.08.27-aarch64.iso`, 3,414,587,392 bytes,
  SHA-256
  `9885cf7df10b251e51b74ac4621a131d966bb1ac7c69bb062b16dedf5042ebda`;
- canonical static evidence SHA-256:
  `ededd9f28735dbaf642f718ab35bf95c727ff2515ce7fcb7398841e96da98799`.

The repository-safe evidence is retained at
[`evidence/apple-silicon/2026-08-27-9885cf7d/static-media-evidence.json`](../evidence/apple-silicon/2026-08-27-9885cf7d/static-media-evidence.json).
It proves that the ISO9660 and appended-ESP `BOOTAA64.EFI` bytes match, the EFI
image is AArch64 PE/COFF, the live kernel is `linux-asahi`, the concatenated
mkinitcpio image contains the Asahi runtime hook and firmware helpers, the
generic ARM kernel and Limine artifacts are absent, and the shipped snapshot is
the exact pinned signed package snapshot. The Asahi keyring package, its
detached signature, signing fingerprint
`12CE6799A94A3F1B5DDFFE88F576553597FB8FEB`, and owner-trust 4 were verified
before pacman accepted the platform packages.

This is **static-structure-valid**, not yet B/build-valid: a second clean build
comparison and complete exported build log/tool manifest are still required.
It is not C/boot-valid because no physical Apple boot occurred; the evidence
correctly records `boot.verified=false` and
`disposable-asahi-boot-evidence-absent`. The package-time `update-m1n1` hook
also found no mounted Apple ESP in the disposable live-root build. That is
expected for this ISO-only stage and reinforces that device-tree and
machine-firmware handoff remain physical-boot blockers.

## Prerequisites

Before a build is proposed:

1. Record exact source identities for the active repository and every ISO,
   package, submodule, patch, and upstream boot input. Use full commit IDs and
   archive hashes; do not use moving branch names as evidence.
2. Define one candidate ID that binds those source identities, the dependency
   manifest, build recipe, and build-environment image digest.
3. Select an AArch64 build environment that can be destroyed in full. Record
   its base image digest, architecture, kernel, toolchain, locale, clock/time
   source, network policy, and available storage.
4. Enumerate the Asahi-specific package set appropriate to the validation
   image. Asahi's distribution guidance identifies the Asahi kernel, m1n1,
   Asahi U-Boot, asahi-scripts/equivalent, tiny-dfr, asahi-firmware/lzfse,
   speakersafetyd, and asahi-audio; a deliberately reduced validation image
   must document why omitted packages are not exercised.
   ([distribution guidelines](https://asahilinux.org/docs/alt/policy/))
5. Establish the image's write policy before boot: internal NVMe must not be
   mounted writable, swap must not use it, and the installer/mutation entry
   point must be absent or fail closed. Logs must go to RAM or a separate
   approved evidence device.
6. Identify a dedicated, non-user canary and its exact model only after current
   official support is verified. A user workstation is not disposable.
7. If physical testing is ever approved, have a recovery host and procedure
   ready first. Apple's current recovery prerequisites are another Mac on
   macOS 14 or later, internet access, sufficient free space (Apple says 32 GB
   is more than enough), and a direct USB-C data-and-charge cable, not a
   Thunderbolt 3 cable.
   ([Apple revive/restore guidance](https://support.apple.com/en-us/108900))

## Disposable-environment boundary

There are two different environments; neither substitutes for the other:

- **Disposable build sandbox:** an isolated AArch64 VM/container/ephemeral
  runner with no production credentials, signing keys, package publication
  token, release channel, mounted user home, or installed-user path. Destroy it
  after exporting the evidence bundle.
- **Disposable boot canary:** a dedicated, recoverable physical Apple Silicon
  Mac with no user data and no production role. A VM cannot prove the Apple
  iBoot/LocalPolicy → m1n1 → U-Boot handoffs. The Asahi stage-1 bootstrap and
  its paired ESP live on internal storage, even when U-Boot subsequently loads
  removable media.
  ([Asahi Boot Process](https://asahilinux.org/docs/alt/boot-process-guide/))

An already prepared canary may be used read-only only if its owner, current
partition layout, LocalPolicy/UEFI ownership, firmware pairing, and recovery
readiness are documented. Creating or changing that preparation is a separate
internal-disk and credential-bearing operation. Apple documents LocalPolicy as
Secure-Enclave-signed, model/chip-bound state whose changes are controlled by
credentials and boot mode; a physical hold into paired 1TR is a trust signal.
([Apple LocalPolicy](https://support.apple.com/guide/security/contents-a-localpolicy-file-mac-apple-silicon-secc745a0845/web))

## Build evidence

A build-valid candidate must retain:

- candidate ID and UTC start/end times;
- clean source/input manifest with repository URLs, full commits, submodule
  commits, patch hashes, and a statement of any local changes;
- immutable build-environment identity and complete tool versions;
- exact build commands, environment allowlist, exit codes, and unedited
  stdout/stderr;
- dependency URLs, versions, publisher-provided checksums where available, and
  locally calculated SHA-256 hashes for every fetched input;
- final media filename, byte size, SHA-256 hash, partition/filesystem inventory,
  and recursive file manifest;
- proof of an AArch64 EFI System Partition and
  `/EFI/BOOT/BOOTAA64.EFI`;
- kernel, initramfs, bootloader, package database, and Asahi-specific component
  versions/hashes; and
- a second clean build comparison. Byte-identical output passes; a mismatch
  requires a documented diff and identified source of nondeterminism before
  proceeding.

Build-valid means only that the recorded inputs reproducibly produced a
structurally valid candidate. It is not boot, model, installation, security, or
release evidence.

## Boot-chain evidence

For an owner-approved, officially supported canary, capture one continuous
timeline of:

1. exact canary model/product/SoC identity, firmware/macOS version, current
   official support evidence, and pre-test internal partition/volume inventory;
2. native Apple boot picker selection of the pre-existing Asahi UEFI
   environment;
3. m1n1 stage 1 loading the paired internal ESP's m1n1 stage 2;
4. stage 2 selecting the device tree and entering U-Boot;
5. U-Boot identifying the removable FAT32 ESP and loading the candidate's
   `BOOTAA64.EFI`;
6. the selected EFI loader loading the recorded kernel and initramfs with the
   device tree; and
7. arrival at a validation-only shell or screen that reports the same candidate
   ID and proves that internal NVMe is not writable or used for swap.

The expected high-level chain is Apple boot components → m1n1 stage 1 → m1n1
stage 2 + device tree → U-Boot → EFI loader (GRUB is one option) → Linux.
([Asahi Boot Process](https://asahilinux.org/docs/alt/boot-process-guide/))

Prefer a serial transcript when the selected canary supports a known capture
method. Supplement it with timestamped photographs/screenshots of the boot
picker, U-Boot/EFI selection, kernel start, and validation result. At the live
shell, capture read-only outputs for the device-tree model/compatible strings,
kernel command line and version, OS release, block-device topology, mounts,
swap, and boot log. Redact usernames, serial numbers, ECIDs, network names, and
credentials from repository-safe copies.

Firmware and device-tree pairing is an acceptance concern: Asahi warns that
OS-paired firmware is not backwards compatible and that foreign kernel/device-
tree combinations may fail or lose features. Record, rather than infer, the
UEFI environment, firmware, device-tree, kernel, m1n1, and U-Boot identities.
([platform quirks](https://asahilinux.org/docs/platform/quirks/))

## Acceptance criteria

### B — build-valid

- Every input and output is content-addressed and traceable to the candidate.
- Both clean builds succeed and are reproducible or have an approved,
  explained nondeterminism report.
- The removable-media UEFI structure and `BOOTAA64.EFI` are present.
- The image exposes no production credentials, signing keys, user data,
  publication endpoints, or enabled mutation path.
- Unsupported/unknown model handling is fail closed in source tests.

### C — supported-canary boot-valid

- B passes, and official same-day evidence says the exact canary is supported.
- One uninterrupted record demonstrates every expected boot-chain handoff.
- The reported candidate, component hashes, model, and device tree match the
  build manifest and approval record.
- Internal NVMe is never mounted writable, used for swap, repartitioned, or
  selected as an installation target.
- The pre-test and post-test partition/volume inventories match.
- Rebooting without validation media returns the canary to its unchanged prior
  boot path.

C is useful compatibility evidence but does not establish M4 support or release
readiness. Asahi's distribution guidance requires install flows to be tested
before release and disk-image flows to be tested on multiple devices; a single
validation boot is insufficient.
([distribution guidelines](https://asahilinux.org/docs/alt/policy/))

### M — exact M4 acceptance

Blocked while the official M4 feature page says `Installer: no`. Later, M
requires a new owner-approved protocol, current official support for the exact
model, B and C evidence, an explicit project allowlist change, and separate
authorization for any physical or privileged step. Do not infer M from a
successful M1/M2/M3 boot.

## Evidence bundle to retain

Use a candidate-specific directory such as
`evidence/apple-silicon/<candidate-id>/` containing:

- `README.md` — purpose, non-goals, outcome, reviewers, and gate decisions;
- `sources.json` — repository/input identities and retrieval timestamps;
- `build-environment.txt`, `build-commands.log`, and `build.log`;
- `SHA256SUMS`, media size, partition/filesystem listing, and file manifest;
- package/component/version manifest and clean-build comparison;
- `canary.json` — redacted model, firmware, UEFI/ESP ownership, and official
  support-source snapshot details;
- pre/post partition, mount, and swap inventories;
- raw serial/console boot transcript and read-only live-system outputs;
- timestamped screenshots/photos plus their hashes; and
- `result.json` — pass/fail per B/C/M criterion, deviations, and owner approvals.

Keep any unredacted hardware identifiers or sensitive recovery information out
of Git and in an access-controlled evidence store. Checksums are integrity
evidence, not signatures; signing the bundle is a later explicit gate.

## Failure and rollback

- **Build failure:** preserve logs and input identities, mark the candidate
  failed, export evidence, and destroy the sandbox. Do not publish partial
  output.
- **Pre-boot mismatch:** stop before power-on or media selection. Do not repair
  the canary as part of this protocol.
- **Boot failure:** capture the last proven stage, power down, remove the media,
  and verify the prior boot path. Do not respond by editing the System ESP,
  LocalPolicy, APFS containers, GPT, firmware, or boot order.
- **Any unexpected internal-disk difference:** stop, preserve evidence, and
  quarantine the canary for owner review. Never automate partition deletion.
  Asahi warns that damaging APFS or System Recovery can require DFU recovery.
  ([partitioning guidance](https://asahilinux.org/docs/sw/partitioning-cheatsheet/))
- **Recovery:** use Apple's procedure only under a separate approval. Apple
  says to try **Revive** first because it does not erase the Mac; **Restore**
  erases it and returns it to factory state.
  ([Apple revive/restore guidance](https://support.apple.com/en-us/108900))

## Explicit owner gates

Each gate requires a new, immediately preceding approval naming exact targets:

1. **Source refresh:** fetch or modify `omarchy-mx-mac`, `omarchy-iso`, or
   `omarchy-pkgs` and select candidate revisions.
2. **Build:** download dependencies or execute the build in the disposable
   sandbox.
3. **Media write:** overwrite a specifically identified removable device.
4. **Canary preparation:** back up a Mac, create/change an Asahi UEFI
   environment, partition internal storage, enter 1TR, use owner credentials,
   or change LocalPolicy/security state.
5. **Physical boot:** use the specifically identified supported canary and
   approved read-only capture protocol.
6. **Mutation testing:** expose any installer, privileged authorization, or
   internal-disk write path.
7. **M4 acceptance:** change the model allowlist or perform any M4 physical
   action after official support changes.
8. **Distribution:** sign, notarize, upload, push, open a pull request, merge,
   publish packages/media/catalogs, change channels, deploy, or integrate with
   existing users.

## Unknowns to resolve before execution

- Whether two clean builds are byte-reproducible.
- A complete exported build log, tool-version manifest, recursive media
  manifest, and clean-build comparison for B/build-valid.
- The exact enforced read-only behavior of the validation shell on hardware.
- Availability of a dedicated officially supported canary with a pre-existing,
  correctly paired Asahi UEFI environment.
- A safe serial/console capture method for that exact canary.
- Recovery-host, backup, cable, and DFU readiness.
- Future official support status for `Mac16,8` / `J614sAP`; currently it is not
  an authorized or supported installer target.

Any unresolved item is a stop condition, not a reason to infer readiness.
