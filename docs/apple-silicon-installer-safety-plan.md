# Apple Silicon Installer Safety Plan

Status: draft for product decisions. No live disk or boot-policy execution is
authorized by this document.

## Goal

Turn the native macOS prototype into a safe front end for an Omarchy-branded,
pinned Asahi installer engine. The Swift application owns the experience,
planning display, explicit approval, and progress presentation. It does not own
APFS mutation, Apple boot policy, firmware extraction, m1n1, U-Boot, device
trees, or System ESP creation.

The intended product path is:

```text
macOS Swift app
  -> inspect and produce an immutable installation plan
  -> obtain explicit approval for that exact plan
  -> invoke a pinned Omarchy build of the Asahi installer engine
  -> let Asahi prepare the target partition, stub macOS, boot policy, firmware, and UEFI
  -> complete the authenticated recoveryOS stage
  -> reboot into Omarchy ARM64 installation media
  -> install only into the empty Linux partition created by Asahi
```

## Accepted product and canary decisions

The initial physical canary is the 14-inch 2021 MacBook Pro with M1 Pro
(`apple,j314s`). Development and orchestration run from the M4, but the M4 is
never an installation target and no mutation path may be reachable there.
Network and SSH are the normal orchestration channel; USB-C is an independent
DFU/recovery channel, not an unattended installation transport.

The M1 Pro is disposable test hardware. A restorable system backup is not
required, and the operator has accepted permanent loss of macOS, Linux, user
files, local keys, and recovery partitions if the approved test requires it.
Before destructive testing, preserve the current project source and uncommitted
work in a separately identified snapshot on the M4. That source-only snapshot
is not a machine backup.

Additional decisions:

- the first Asahi handoff is a visible pinned terminal flow; a structured
  engine interface follows without prompt scraping;
- the UEFI-media route is preferred;
- the app is telemetry-free;
- macOS coexistence and recovery come before automated uninstall;
- local development uses local/ad-hoc signing, while official production
  signing belongs to Omarchy CI;
- physical interruption tests occur only at engine-declared safe checkpoints,
  never during APFS resize, firmware work, or `kmutil` boot-policy work;
- Asahi creates the empty Linux target partition from the approved free extent,
  so the Linux-side installer never edits GPT;
- the Linux-side installer accepts only an immutable, signed target-partition
  manifest and fails closed if it cannot prove every write remains inside it;
- the model allowlist fails closed, and remote configuration may disable a
  model but cannot enable one absent from the signed local allowlist; and
- Phase 5 success requires the named M1 Pro evidence gate, including two clean
  installations, macOS coexistence, recovery, reboot, hardware, and update
  evidence. One successful machine does not imply broad Apple Silicon support.

This is Phase 4 incubation. It cannot satisfy Phase 5 until named models have
complete installation, reboot, recovery, macOS-coexistence, hardware, and
update evidence.

## Non-negotiable upstream constraints

1. The Asahi distribution guidelines recommend the minimal UEFI environment
   plus normal AArch64 installation media for workstation distributions. They
   require Asahi to create installation space and warn that changing any disk
   structure outside that free space can require a DFU restore.
2. Apple Silicon has a per-install boot environment: m1n1 stage 1, a paired
   internal System ESP, m1n1 stage 2, device trees, U-Boot, and a default
   `EFI/BOOT/BOOTAA64.EFI`. There is no normal persistent EFI variable store.
3. The Asahi reference installer is an interactive implementation, not a
   stable machine-readable interface. Downstream distributions are expected to
   build, brand, pin, and host their own installer and metadata.
4. The authenticated recoveryOS and LocalPolicy steps are real security gates.
   The Omarchy application must explain and hand off to them, not imitate or
   suppress them.
5. Asahi currently reports `Installer: no` for every M4-series model. The M4
   development Mac is therefore simulation- and read-only-test-only.

Primary sources:

- [Asahi distribution guidelines](https://asahilinux.org/docs/alt/policy/)
- [Asahi installer repository](https://github.com/AsahiLinux/asahi-installer)
- [Asahi boot process](https://asahilinux.org/docs/alt/boot-process-guide/)
- [Apple Silicon platform quirks](https://asahilinux.org/docs/platform/quirks/)
- [M4 feature support](https://asahilinux.org/docs/platform/feature-support/m4/)
- [Apple startup security policy](https://support.apple.com/guide/security/startup-security-sec7d92dc49f/web)

## Deep module and seam

Create one deep `AppleInstallation` module. Its interface is the complete test
surface for the Swift application:

```swift
protocol AppleInstallation: Sendable {
  func inspect() async throws -> InstallationInspection
  func plan(_ request: InstallationRequest) async throws -> InstallationPlan
  func execute(_ approval: ApprovedInstallationPlan) -> AsyncThrowingStream<InstallationEvent, Error>
  func recover() async throws -> RecoveryState
}
```

Interface invariants:

- `inspect` and `plan` are read-only.
- A plan contains the exact machine identity, selected free-space extent,
  engine version, metadata digest, payload digest, required human recovery
  steps, and a digest of the whole plan.
- `execute` accepts only an approval bound to that digest. Any disk, model,
  payload, metadata, or engine change invalidates approval.
- The Swift process never receives or stores the administrator password.
- The engine emits structured events and durable checkpoints; the UI never
  infers success from process exit or terminal text.
- Cancellation is allowed only at engine-declared safe checkpoints. The UI
  cannot promise cancellation during APFS resize or boot-policy work.

Adapters make the seam real:

- `FixtureInstallation`: deterministic scenarios for UI and state tests.
- `TranscriptInstallation`: replays versioned engine event transcripts and
  injected failures.
- `ReadOnlyAsahiInstallation`: runs real, non-privileged inspection on macOS
  and always rejects execution.
- `PinnedAsahiInstallation`: the only live adapter; wraps a reviewed,
  signed/pinned Omarchy build of Asahi's engine.

### Implementation checkpoint — 2026-08-26

The M4 application now has the first two adapters at the approved seam:

- `FixtureInstallation` provides deterministic supported and unsupported
  identities, content-bound plan digests, and stale-approval rejection. It
  cannot execute.
- `ReadOnlyAsahiInstallation` reads only `hw.model`,
  `machdep.cpu.brand_string`, and `hw.targettype` through `sysctlbyname`, the
  macOS version through `ProcessInfo`, and the current power source through
  IOKit. A closed read-only command module can execute only
  `diskutil info -plist /` and
  `diskutil apfs resizeContainer <validated-container> limits -plist`. It does
  not accept caller-supplied executables or argument arrays, validates the
  container as `disk` followed only by digits, discards stderr, and never
  exposes a mutation form. The adapter does not query serial-number-bearing
  system profiles, elevate privileges, use the network, or create a plan on
  the unsupported M4.

The physical M4 development host reported `Mac16,8`, `Apple M4 Pro`, and
`apple,j614s`. With no signed local support record for that exact identifier,
the application displays a blocked result, keeps storage navigation disabled,
shows the observed macOS version and AC/battery source, and labels all other
unimplemented live probes `NOT LOADED` or `NOT CHECKED`. It also shows
FileVault state, root APFS free capacity, and Apple's preferred APFS shrink
limit. The shrink limit is explicitly informational: it is not free-space
selection and does not include Asahi's reservation and safety policy. Fixture
scenarios remain available but are visibly separated from `This Mac`.

The app also contains the first fail-closed model-admission implementation. A
detached Ed25519 signature covers the exact catalog JSON bytes. Every enabled
record binds one exact Apple device identifier to a semantic Asahi tag, full
Asahi installer, installer-data, and downstream commit hashes, three SHA-256
artifact digests, and an evidence revision. Schema, sequence, validity window,
duplicate model, identifier, tag, revision, digest, and signature failures all
reject the catalog. The runtime policy can disable a signed local record but
has no remote-enable operation. Accepted sequence and payload identity can now
be persisted atomically; production still needs to choose the app-owned state
location and connect the guard to the live trust root before catalogs can be
updated over a channel.

The reviewed source baseline is Asahi installer `v0.9.0` at
`f0469cea0899f3efed8efead604174c7a53c4451` and installer-data at
`42648e71423eba308d2e3e6228253eff679b068b`. This records upstream identity; it
does not claim a production-signed Omarchy engine or physical M1 Pro success.
No production public key or catalog is bundled, so the live adapter uses an
empty catalog and admits no machine. Generated signing keys and the M1 Pro
record appear only in tests.

The first downstream overlay is now source-locked under
`apps/omarchy-apple-installer/Engine`. Its engine modes are structured,
read-only inspection and candidate-bound planning. They reuse Asahi's own
free-space and resize calculations, bind candidate source and resulting extent
to the plan, and return before any current-OS or action-menu path. The stored
patch applies to the exact pin and passes 11 focused Python tests. Three clean
same-host builds with the pinned toolchain produced the same unsigned
validation archive, and a closed bundle adapter verifies and launches those
exact bytes for read-only inspection and planning. The engine has not been
production-signed, published, or made mutation-capable.

The local Phase 3 `omarchy-iso` worktree now contains a dormant Linux handoff verifier.
It verifies the exact manifest bytes with Ed25519, requires the signer-key
fingerprint, plan digest, and installation nonce from unique kernel-command-line
fields, and matches the GPT disk UUID, disk size, sector size, Asahi-created
Linux partition, and paired ESP by UUID, type, offset, and length. It rejects
duplicate JSON keys, a changed ESP or target, overlapping partitions, unknown
whole-disk fields, and every proposed byte range outside the target partition.
The target is pre-created by Asahi specifically to avoid Linux-side GPT writes.
The verifier is not routed from the generic installer and no production
connected handoff signer or boot-chain injection exists yet. The Swift app now
has a dormant ephemeral-Ed25519 producer for the exact schema, and a
Swift-produced fixture is verified by the Linux consumer.

A dormant Apple-only storage planner on the Phase 3 ARM worktree now consumes
the verified object and renders operations only against the exact Linux
partition node. It names the boot backend `asahi-grub`, never Limine, and
exposes the paired ESP only through a read-only inspection mount. A
descriptor-pinned executor revalidates the signed target and kernel topology
before each operation and passes only the target descriptor to formatting and
mount tools. A separate signed boot-file contract authorizes only the
content-addressed GRUB write while preserving `m1n1/boot.bin`; neither path is
routed into the live phase graph yet. Canonical `x86_64/pc`, `aarch64/generic`, and
`aarch64/apple-silicon` target contracts now bind architecture, platform, boot
backend, and artifact kind. The Apple target and consumer both fail closed
until the exact Apple media marker and locked live inputs exist. The complete
Phase 3 shell suite plus 105 Python tests pass.

T0/T1/T2/T3 and initial T4 evidence at this checkpoint: 78 Swift tests pass on
the M4, including a
physical-host read-only inspection, unsupported planning rejection,
unreachable execution, content-bound plan digest, stale approval rejection,
OS/power/FileVault/APFS observations, malicious container-identifier rejection
before the limits command, state integration, and minimum-window rendering.
The T2 slice includes a Python-produced golden inventory whose layout digest is
independently recomputed by Swift, plus tampered-extent and unknown-field
rejection. This is unsigned validation-engine evidence, not a
production-signed engine result.
The blocked-M4 render was visually inspected for clipping, overlap, indicator
semantics, unverified-claim leakage, and disabled navigation.
The T4 slice adds a private append-only journal, full-transcript validation
before every durable append, `fsync`, symlink and unsafe-permission rejection,
and restart recovery from the last checkpoint. Its controlled coordinator also
proves cancellation before engine launch, stale-approval rejection, rejection
of a different internally valid plan before persistence, process/network fault
recovery, and restart continuation. The app packages as a native arm64 bundle
with its resource bundle and a verified hardened-runtime ad-hoc signature.
Two assemblies from the same cached release build were byte-identical across
every bundle file, including signing data; clean-room compiler reproducibility
has not been tested.
Developer ID signing, notarization, a live authorization implementation, and a
privileged mutation-capable engine process remain intentionally absent.

The platform/update ownership boundary is also executable rather than only
descriptive. `install/apple-silicon-platform-stack.json` covers Apple boot
policy, both m1n1 stages, device trees, U-Boot, machine firmware, installed and
removable-media GRUB, the Asahi kernel, speaker safety/audio, and conditional
Touch Bar support. `omarchy-apple-platform-stack-verify --require-ready`
refuses physical-install readiness until the live engine, complete Apple live
input set, verified `BOOTAA64.EFI` assembly, compatible platform transaction,
and physical evidence gates are all closed. Packages marked as delivered by an
Omarchy manifest must occur exactly once in the shipped Asahi package closure.

The current nine-package Asahi platform candidate is now content-addressed in
the Phase 3 ISO worktree. Each package and detached signature has a fixed
SHA-256, and every detached signature was verified using the pinned Asahi ALARM
key fingerprint. Because the upstream release tag is mutable, the hashes—not
the tag—are the input identity. This closes package-byte selection only; live
build/boot evidence, removable-EFI compatibility, and installed
update-transaction compatibility remain separate blockers.

The future Apple media profile now consumes those bytes through a dedicated
offline fetch path. It boots `linux-asahi`, builds
`initramfs-linux-asahi.img` with the Asahi firmware hook, and preserves Apple
packages instead of mapping them to generic ARM substitutes. The bridge-owned
internal `m1n1/boot.bin` supplies m1n1, model DTs, and U-Boot; U-Boot then loads
the removable media's `/EFI/BOOT/BOOTAA64.EFI`. This separation is implemented
in profile logic but remains disabled until a disposable build-and-boot test
proves the complete path.

## Privilege and process model

The Swift app remains unprivileged. The live adapter launches a separately
signed engine using a reviewed macOS authorization mechanism. Credentials stay
inside macOS/Asahi authentication flows. The engine receives an immutable plan
file, not arbitrary shell arguments, and writes a root-owned append-only event
and checkpoint journal.

The first implementation must not:

- call `diskutil apfs resizeContainer` from Swift;
- set `EXPERT=1` or expose whole-disk wipe paths;
- accept unknown hardware using a local override;
- write directly to `/dev/disk*`;
- edit the System ESP or `m1n1/boot.bin` itself;
- replace Asahi model, firmware, minimum-space, or APFS safety calculations;
- hide the recoveryOS authentication handoff; or
- download and execute an unpinned `curl | sh` installer.

## Safe test ladder

No level may be skipped merely because a later level is available.

### T0 — Pure state tests

- State-machine transitions for supported, blocked, interrupted, cancelled,
  stale-plan, and recovery-required states.
- No filesystem, process, network, authorization, or disk access.
- Run on Linux CI and macOS.

### T1 — Snapshot and accessibility tests

- Render every state at minimum and standard window sizes.
- Verify keyboard navigation, VoiceOver labels, destructive-copy wording,
  progress monotonicity, and blocked-button behavior.
- Use `FixtureInstallation` only.

### T2 — Engine contract tests

- Versioned JSON fixtures for inspection, plan, event, error, and checkpoint
  messages.
- Golden transcripts from a pinned engine build.
- Reject unknown fields where they affect safety; tolerate explicitly
  extensible display metadata.
- Fuzz sizes, partition identifiers, event ordering, truncation, duplicate
  events, and stale plan digests.

### T3 — Read-only M4 tests

- Run actual model, macOS, power, FileVault, disk-layout, APFS-limit, and free
  space probes without `sudo` or mutation.
- Assert the current M4 returns `unsupportedByAsahi` and cannot create an
  executable plan.
- Compare observations with sanitized fixtures; never upload serial numbers or
  full disk identifiers.

### T4 — Disposable macOS environment tests

- Verify packaging, code signing, authorization cancellation, engine launch,
  journal permissions, restart/resume, and injected process/network failures.
- Replace `diskutil`, device access, firmware extraction, shutdown, boot-policy
  tools, and the installer subprocess with controlled adapters.
- A macOS VM is not evidence for Apple boot or physical disk safety.

### T5 — Disposable generic AArch64 VM

- Reuse `test/vm/asahi-fresh` for the post-reboot Omarchy package payload.
- Verify signed payload resolution, installation, interruption recovery,
  reboot, update, and preservation of fixture Asahi boot files.
- This is not hardware evidence.

### T6 — Supported physical canary

Required before any preview claim:

- a named model whose current Asahi matrix says `Installer: yes`;
- a non-daily-driver Mac with either a current verified backup or an explicit,
  recorded disposable-machine data-loss waiver;
- preservation of active project source outside the canary, even when the
  disposable-machine waiver is used;
- a second Mac, appropriate USB cable, and tested DFU-restore procedure;
- AC power, no pending macOS update, current macOS/firmware, and a recorded
  pre-install disk map;
- an allowlisted engine, metadata digest, payload digest, and exact plan;
- operator confirmation immediately before the first mutation.

Do not deliberately cut power during APFS resize. Test interruptions through
adapters first and only exercise physical interruption at checkpoints the
Asahi engine declares recoverable.

### T7 — Named-device matrix

For every Phase 5 allowlisted device, retain evidence for install, reboot,
macOS coexistence, Startup Options, recovery, display, keyboard, touchpad,
storage, networking, audio, suspend, update, rollback, and uninstall/reclaim
guidance. A chip-generation label is not an allowlist.

## Engineering increments

1. **Freeze claims.** Replace simulated “supported” claims with explicit
   fixture labels and add a real read-only M4 block reason.
2. **Define the seam.** Add the `AppleInstallation` interface, domain values,
   typed errors, and `FixtureInstallation`; move the existing session behind
   it without changing behavior.
3. **Add contract artifacts.** Define versioned plan/event/checkpoint schemas,
   transcript fixtures, stale-plan rejection, and fault injection.
4. **Build read-only integration.** Add macOS inspection with no privileged
   helper and prove M4 execution is unreachable.
5. **Pin the Asahi base.** Select a tagged Asahi installer revision, record its
   source and build inputs, create an Omarchy downstream build, and minimize the
   maintained delta.
6. **Add a structured engine mode.** Implement inspect/plan/event/checkpoint
   output in the downstream installer without moving its disk/firmware/boot
   logic into Swift. Seek Asahi review before treating this as durable.
7. **Package and authorize.** Sign the app and engine separately, validate the
   immutable plan at the privilege seam, and complete T0-T4.
8. **Connect the ARM64 payload.** Use the UEFI environment path and an official
   Omarchy ARM64 artifact; keep the Linux installer restricted to the exact
   empty Linux partition Asahi created from the approved free extent.
9. **Run one physical canary.** Only after the recovery kit and live-test
   approval are complete; capture evidence independently of the test machine.
10. **Expand by named model.** Promote only through the Phase 5 evidence matrix.

## Installation video and commercial

Produce two separate artifacts after the physical canary succeeds:

1. **Engineering installation video.** A truthful, minimally edited record of
   the preflight, Asahi handoff, physical 1TR interaction, UEFI-media boot,
   installation, first boot, macOS coexistence, and recovery checks. Redact
   credentials, serial numbers, full disk identifiers, private logs, keys, and
   personal data. This video is evidence and must not use generated footage.
2. **Produced TV commercial.** A 30-second 16:9 master plus 15-second 9:16 and
   square derivatives. It may combine sanitized installation footage, the
   supplied Omarchy logos, and Seedance clips generated through OpenRouter. It
   may stylize the experience but must not imply M4 support, hide required 1TR
   interaction, or depict unattended capabilities not demonstrated by the
   engineering evidence.

OpenRouter generation has a hard total ceiling of **USD 5.00** for the first
commercial iteration. Estimate the complete job before submission, stop before
the request that would exceed the remaining ceiling, and retain a local ledger
of submitted job IDs, model, requested duration, quoted/observed cost, and
output. Submitting any paid generation requires a separate execution-time
approval after sanitized inputs and the estimate are shown. Never upload
credentials, recovery authentication, serial numbers, disk identifiers,
private logs, keys, or personal data.

## Live-test stop gate

Development may proceed through T5 without live disk mutation. Stop before T6
until all of the following are explicit:

- project ownership and signing authority;
- the supported canary model and owner;
- permission to resize that specific machine;
- recovery operator, second Mac, cable, and DFU drill;
- selected Asahi revision and downstream maintenance policy;
- selected Omarchy ARM64 artifact and update channel; and
- retention policy for local logs, sanitized reports, and device identifiers.
