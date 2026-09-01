# Asahi Installer Integration Contract for the Omarchy macOS App

Research snapshot: 2026-08-26

Primary-source revisions inspected:

- `AsahiLinux/asahi-installer` at
  [`f0469cea0899f3efed8efead604174c7a53c4451`](https://github.com/AsahiLinux/asahi-installer/tree/f0469cea0899f3efed8efead604174c7a53c4451)
- `AsahiLinux/asahi-installer-data` at
  [`42648e71423eba308d2e3e6228253eff679b068b`](https://github.com/AsahiLinux/asahi-installer-data/tree/42648e71423eba308d2e3e6228253eff679b068b)
- `AsahiLinux/docs` at
  [`9d0ed3c6e42bc7c1f2ffc4ae6e00fefb0068f151`](https://github.com/AsahiLinux/docs/tree/9d0ed3c6e42bc7c1f2ffc4ae6e00fefb0068f151)

This document describes the contract that a branded Swift application can
safely build on. It distinguishes public downstream integration points from
implementation details, and it deliberately does not authorize a real install
on the MacBook M4 used to develop the prototype.

## Executive decision

The recommended first production architecture is:

```text
Omarchy Swift app
  -> performs read-only preflight and explains the operation
  -> launches a pinned, Omarchy-hosted downstream build of the Asahi installer
     for all APFS resize, Apple stub, firmware, and boot-policy preparation
  -> guides the user through the physical paired-recovery/1TR step
  -> boots Omarchy's Apple-capable AArch64 UEFI media
  -> Omarchy's installer touches only the free space created by Asahi
```

The Swift app must not reimplement APFS resizing, Apple boot-policy creation,
firmware extraction, or m1n1 stage-1 installation. The reference installer is
designed to own those operations, and Asahi's distribution policy explicitly
requires downstream installers to leave APFS alone and operate only in the free
space created by Asahi ([distribution guidelines, installation
procedure](https://github.com/AsahiLinux/docs/blob/9d0ed3c6e42bc7c1f2ffc4ae6e00fefb0068f151/docs/alt/policy.md#L72-L116)).

The application must have two execution modes:

- **Simulation:** available on any development Mac, including the M4; no
  privileged process, disk command, mount, raw-device write, shutdown, or boot
  policy command may be reachable.
- **Real preparation:** compiled or remotely enabled only for a named allowlist
  of devices that both the current Asahi installer and Omarchy validation
  records support. It is unavailable on M4 today.

## Hard blocker: the MacBook M4 is not an installation target

The official M4 support matrix marks `Installer` as `no` for every listed M4,
M4 Pro, and M4 Max device. NVMe, display, USB, GPU, device trees, and the other
core blocks are also `TBA` ([M4 feature support](https://github.com/AsahiLinux/docs/blob/9d0ed3c6e42bc7c1f2ffc4ae6e00fefb0068f151/docs/platform/feature-support/m4.md#L22-L104)).

The current installer independently enforces this boundary. Its chip and device
tables contain M1 through M3 identifiers, but no M4 identifiers
([`CHIP_MIN_VER` and `DEVICES`](https://github.com/AsahiLinux/asahi-installer/blob/f0469cea0899f3efed8efead604174c7a53c4451/src/main.py#L39-L95)).
Startup exits when the chip or device is absent, or when the device is
expert-only and expert mode was not accepted
([device gate](https://github.com/AsahiLinux/asahi-installer/blob/f0469cea0899f3efed8efead604174c7a53c4451/src/main.py#L964-L999)).

Therefore:

- The M4 can run the UI, state machine, fixture-based preflight, fake executor,
  metadata validation, and screen-level tests.
- It must not run the reference installer with patched device tables or a
  locally invented firmware tuple.
- Expert mode is not an escape hatch. There is no M4 identity to admit, and
  expert mode explicitly carries a no-support warning.
- The earliest real-device work requires a spare, officially installable M1 or
  M2 model. M3 remains `WIP` in the official support matrix despite being
  present as expert-only in current installer source
  ([M3 feature support](https://github.com/AsahiLinux/docs/blob/9d0ed3c6e42bc7c1f2ffc4ae6e00fefb0068f151/docs/platform/feature-support/m3.md#L58-L102)).

The real-path allowlist must be the intersection of:

1. current non-expert Asahi installer support;
2. current official Asahi feature status;
3. the firmware combinations accepted by the installer;
4. an Omarchy-owned, named device validation record.

No processor-generation label is sufficient by itself.

## Supported downstream integration surface

### Bootstrap and branding

The installer README says it is intended to be invoked through a bootstrap
script. Downstream distributions are encouraged to host their own modified
bootstrap, installer build, metadata, and images. The documented configuration
surface is:

- `VERSION_FLAG`
- `INSTALLER_BASE`
- `INSTALLER_DATA` and optional `INSTALLER_DATA_ALT`
- `REPO_BASE`
- optional `REPORT` and `REPORT_TAG`

The build also accepts a downstream `.icns` `LOGO` and an optional prebuilt
`M1N1_STAGE1` ([README: building, bootstrapping, and
branding](https://github.com/AsahiLinux/asahi-installer/blob/f0469cea0899f3efed8efead604174c7a53c4451/README.md#L11-L45)).

The reference bootstrap verifies that it is running on macOS, downloads a
versioned installer archive and metadata, extracts them to a temporary tree,
then runs `caffeinate -dis sudo -E ./install.sh`
([production bootstrap](https://github.com/AsahiLinux/asahi-installer/blob/f0469cea0899f3efed8efead604174c7a53c4451/scripts/bootstrap-prod.sh)).
Production follows tagged releases; the development installer follows `main`
([README](https://github.com/AsahiLinux/asahi-installer/blob/f0469cea0899f3efed8efead604174c7a53c4451/README.md#L20-L22)).

For Omarchy this means:

- build and host a pinned downstream installer, metadata file, and payload;
- publish checksums/signatures and verify before elevation;
- never silently use Asahi's development channel or floating `main`;
- omit reporting by default unless Omarchy defines a separately reviewed,
  explicit opt-in reporting policy;
- keep the downstream delta small and auditable.

There is no documented stable library, RPC, JSON event stream, or unattended
command-line interface for a native GUI to call. The current interface is an
interactive terminal program. A Swift process that drives its prompts by
matching human-readable strings would be coupled to implementation text, not a
supported contract. The safe initial bridge is therefore to launch the pinned
bootstrap in a visible terminal and let the Asahi installer retain interactive
control. A deeper native UI requires either an upstream-agreed machine-readable
interface or a maintained downstream refactor with its own compatibility tests.

### Metadata and delivery choices

The reference metadata selects an OS package, boot object, next object,
supported firmware set, and partition list. Partition entries can request an
image, copied tree, expansion, firmware, and persisted installer data. The
current UEFI-only entry contains a single 500 MB FAT EFI partition, requests
firmware and installer data, and supplies m1n1/U-Boot content
([current installer metadata](https://github.com/AsahiLinux/asahi-installer-data/blob/42648e71423eba308d2e3e6228253eff679b068b/data/installer_data.json)).

Asahi supports two downstream delivery patterns:

1. **Preferred: standard AArch64 UEFI media.** Use the minimal UEFI environment
   to boot the distribution's existing installer media. Asahi says this avoids
   forking the installer and is the direction distributions should invest in.
2. **Alternative: streamed disk image.** A downstream may fork and host the
   installer and a ZIP-streamable prebuilt image, but must scramble the root
   UUID on first boot, grow into trailing free space, include the Asahi packages,
   enable supported hardware immediately, keep images current, and test all
   flows on multiple devices.

Asahi describes the disk-image path as a carry-over from early bring-up rather
than the future direction for workstation hardware
([forked installer and disk image policy](https://github.com/AsahiLinux/docs/blob/9d0ed3c6e42bc7c1f2ffc4ae6e00fefb0068f151/docs/alt/policy.md#L133-L170)).

For the experience currently mocked by the application—prepare from macOS,
reboot, then let the Omarchy installer take over—the preferred UEFI-media flow
is the closest official fit. The artifact may be presented as an ISO-like
installer to users, but technically it must be Apple-capable AArch64 UEFI media
with `/EFI/BOOT/BOOTAA64.EFI` and an Asahi-compatible kernel/device-tree path.

## Partition ownership and mutation rules

The Asahi installer must own macOS APFS resizing. Its normal path:

- accepts only APFS containers with sufficient free capacity;
- reserves 38 GB in an OS-containing APFS container and 1 GB in a non-OS
  container;
- adds a 500 MB margin before declaring a container resizable;
- combines its conservative calculation with `diskutil`'s
  `MinimumSizePreferred` limit;
- detects large snapshot/pending-update overhead and warns the user;
- reconfirms the chosen size immediately before mutation;
- performs the mutation through native `diskutil apfs resizeContainer`;
- reports APFS repair guidance rather than improvising after failure.

These checks and the resize operation are implemented together
([resize eligibility and action](https://github.com/AsahiLinux/asahi-installer/blob/f0469cea0899f3efed8efead604174c7a53c4451/src/main.py#L776-L923),
[`DiskUtil.resizeContainer`](https://github.com/AsahiLinux/asahi-installer/blob/f0469cea0899f3efed8efead604174c7a53c4451/src/diskutil.py#L272-L277)).
Duplicating only some of this logic in Swift would create two conflicting safety
authorities.

The Omarchy media installer must treat the disk as:

- immutable Apple/Asahi structures; plus
- a precisely identified free-space extent created by the Asahi step.

It must refuse automatic partitioning unless its storage backend can prove that
every planned write is wholly inside that extent. In particular, it must never
offer “use whole disk,” reorder the GPT, resize APFS, delete APFS, or infer a
target merely from `/dev/disk*` numbering. Asahi warns that damaging an APFS
container can require DFU restore and says it is never safe for the downstream
installer to alter anything except the free space Asahi left
([distribution policy](https://github.com/AsahiLinux/docs/blob/9d0ed3c6e42bc7c1f2ffc4ae6e00fefb0068f151/docs/alt/policy.md#L83-L111)).

Terminology matters: this is not one global “System ESP.” A normal installation
is a logical unit containing:

- a 2.5 GB APFS stub with the Apple boot wrapper and paired recoveryOS;
- a per-install, approximately 500 MB EFI System Partition;
- the OS partitions or trailing free space.

The iBoot System Container at the start of internal storage and System Recovery
at the end are separate critical Apple structures and must never be touched
([partitioning guide](https://github.com/AsahiLinux/docs/blob/9d0ed3c6e42bc7c1f2ffc4ae6e00fefb0068f151/docs/sw/partitioning-cheatsheet.md)).

## Firmware and boot handoff

The supported chain is:

```text
Apple boot policy / iBoot
  -> m1n1 stage 1 in the machine-specific stub
  -> m1n1 stage 2 + device trees + U-Boot on the paired ESP
  -> /EFI/BOOT/BOOTAA64.EFI
  -> GRUB or another AArch64 EFI loader
  -> Linux
```

m1n1 stage 1 is installed from recoveryOS, signed with a machine-specific key,
and embeds the PARTUUID of its paired ESP. The distribution owns updates to
stage 2, device trees, U-Boot, the EFI loader, and Linux. U-Boot has no
persistent EFI-variable boot order, and Asahi asks each installed OS to keep its
own stub/ESP ownership boundary
([boot process and per-install ESP](https://github.com/AsahiLinux/docs/blob/9d0ed3c6e42bc7c1f2ffc4ae6e00fefb0068f151/docs/alt/boot-process-guide.md#L12-L38)).

USB rescue/installer media are the explicit exception: the vanilla UEFI-only
m1n1/U-Boot bundle may boot `/EFI/BOOT/BOOTAA64.EFI` from the USB media, but the
USB environment must not update `boot.bin` on the internal paired ESP. Only the
properly installed OS becomes owner of that internal container
([boot-process exception](https://github.com/AsahiLinux/docs/blob/9d0ed3c6e42bc7c1f2ffc4ae6e00fefb0068f151/docs/alt/boot-process-guide.md#L28-L38)).

The installer constructs the handoff by embedding
`chosen.asahi,efi-system-partition=<PARTUUID>` and, when applicable,
`chainload=<PARTUUID>;<next_object>` in the m1n1 boot object
([`OSInstaller.install`](https://github.com/AsahiLinux/asahi-installer/blob/f0469cea0899f3efed8efead604174c7a53c4451/src/osinstall.py#L179-L200)).
It extracts device-matched FUD firmware and collects Wi-Fi, Bluetooth,
multitouch, ISP, kernel, and ALS firmware from Apple material, then places the
result in `vendorfw` on the target requested by metadata
([firmware collection](https://github.com/AsahiLinux/asahi-installer/blob/f0469cea0899f3efed8efead604174c7a53c4451/src/stub.py#L402-L484),
[firmware copy](https://github.com/AsahiLinux/asahi-installer/blob/f0469cea0899f3efed8efead604174c7a53c4451/src/osinstall.py#L143-L173)).

Omarchy must package and continuously update the complete Asahi platform stack
required by policy, including the Asahi kernel, m1n1, Asahi U-Boot,
`asahi-scripts` or equivalent, `tiny-dfr`, firmware tooling, speaker safety, and
audio components appropriate to the installation type
([required packages](https://github.com/AsahiLinux/docs/blob/9d0ed3c6e42bc7c1f2ffc4ae6e00fefb0068f151/docs/alt/policy.md#L52-L70)).

## Physical recovery and resume are part of the product

This is not a single uninterrupted GUI transaction. After the first stage, the
user must shut down, physically hold the power button, choose the new OS, and
enter its paired recoveryOS/One True Recovery (1TR). The second-stage script:

- rejects the wrong recoveryOS and attempts to select the correct volume;
- rejects recovery mode that is not 1TR;
- explains that security policy changes apply to the new OS, not macOS;
- obtains machine-owner authentication;
- uses `bputil` and `kmutil configure-boot` to create the boot policy and custom
  boot object;
- retries credential-sensitive commands rather than pretending success;
- only then marks the stub visible and complete.

See the reference
[`step2.sh`](https://github.com/AsahiLinux/asahi-installer/blob/f0469cea0899f3efed8efead604174c7a53c4451/src/step2/step2.sh#L25-L150).
Apple documents that each installation has a paired recoveryOS, that it can
downgrade policy only for its paired OS, and that fallback recoveryOS cannot do
so ([paired recoveryOS restrictions](https://support.apple.com/guide/security/paired-recoveryos-restrictions-sec4cf9d63a6/web)).
Apple also defines the CustomOS policy hash as mutable only from 1TR via
`kmutil configure-boot`
([LocalPolicy fields](https://support.apple.com/guide/security/contents-a-localpolicy-file-mac-apple-silicon-secc745a0845/web)).

The app must model at least these durable states:

```text
not_started
preflight_complete
resize_complete
stub_and_esp_written
awaiting_physical_recovery
recovery_step_incomplete
boot_policy_complete
awaiting_omarchy_media
omarchy_installing
installed
manual_recovery_required
```

The state must be reconstructed from read-only evidence after every launch;
never trust a UI flag alone. The reference installer enumerates incomplete
installs and offers repair, but can resume only when first-stage files are
complete. If the first stage was interrupted too early, it explicitly requires
manual partition removal and a fresh install
([repair/resume limits](https://github.com/AsahiLinux/asahi-installer/blob/f0469cea0899f3efed8efead604174c7a53c4451/src/main.py#L409-L466)).
It persists installer data and the log to the selected metadata target
([installation flow](https://github.com/AsahiLinux/asahi-installer/blob/f0469cea0899f3efed8efead604174c7a53c4451/src/main.py#L562-L585)).

Credentials cannot be collected once by the Swift app and replayed across the
reboot boundary. The user must authenticate in the Apple-controlled recovery
context. The app should explain and guide this boundary, not hide it.

## Expert mode is forbidden in the product flow

Setting `EXPERT` does not directly enable expert behavior. It exposes a warning
and an interactive prompt that states expert options are for Asahi developers
and unsupported if they fail
([expert prompt](https://github.com/AsahiLinux/asahi-installer/blob/f0469cea0899f3efed8efead604174c7a53c4451/src/main.py#L941-L962)).
After acceptance, expert mode admits expert-only models, firmware and OS entries,
permits external-disk selection/whole-disk wipe, lowers normal size safeguards,
and uses an older minimum macOS version.

The Omarchy production bootstrap must not set `EXPERT`, and the GUI must not
expose a hidden override. Development experiments belong in an independently
identified build on disposable hardware, never in a release binary.

## Safe test architecture

### Layer 0 — static and pure tests on every machine

No subprocesses or mounted volumes:

- Swift UI and navigation tests for every state and failure screen;
- metadata schema, checksum, signature, and pinned-version tests;
- compatibility-selection tests using captured upstream device, firmware, and
  model fixtures;
- partition arithmetic, alignment, reserve, and target-containment properties;
- recovery transition and relaunch/resume tests;
- accessibility and localization tests for irreversible-action warnings;
- tests proving the M4 and every unknown identifier can reach simulation only.

### Layer 1 — fake system adapters in CI

Put every side effect behind an interface and supply a recording fake for:

- `ioreg`, `sysctl`, and system/device discovery;
- `diskutil` plist reads and all disk actions;
- downloads and archive reads;
- mounts, `hdiutil`, raw `/dev/r*` writes, and firmware extraction;
- privilege acquisition and credentials;
- `bless`, `bputil`, `kmutil`, shutdown, and reboot;
- terminal/PTY execution and progress parsing.

Tests should assert an explicit ordered operation transcript and stop at injected
failures before and after each boundary. A fake executor is the only acceptable
way to test destructive commands on the M4.

### Layer 2 — disposable virtual storage

Synthetic GPT/APFS disk images can test discovery, free-extent accounting,
command construction, idempotency, and refusal behavior. They cannot prove:

- Apple internal-NVMe topology;
- paired recoveryOS and machine-owner authorization;
- Secure Enclave LocalPolicy changes;
- machine-specific m1n1 signing;
- firmware compatibility;
- a successful physical reboot chain.

The installer contains an `ALLOW_VM` development identity, but its own comment
says Asahi does not support running in a VM and that the option exists only for
installer development
([VM development hook](https://github.com/AsahiLinux/asahi-installer/blob/f0469cea0899f3efed8efead604174c7a53c4451/src/main.py#L91-L95)).
It is not a dry-run switch and does not neutralize disk operations.

### Layer 3 — disposable supported hardware

Real mutation tests require all of the following:

- an officially supported, non-primary spare Mac on the exact device allowlist;
- current verified backup of macOS data;
- a second Mac, correct USB cable, and rehearsed DFU revive/restore procedure;
- a local human operator at the keyboard; no remote unattended execution;
- captured before/after disk, APFS, boot-policy, firmware, and installer logs;
- one injected interruption point per run, with a documented recovery result;
- reboot into macOS after every preparation-stage scenario to prove coexistence;
- independent verification that the Omarchy installer wrote only inside the
  Asahi-created free extent.

Apple distinguishes **revive**, which attempts firmware recovery without
erasing the Mac, from **restore**, which erases and returns it to factory state;
restore is the fallback if revive fails
([Apple firmware revive/restore procedure](https://support.apple.com/108900)).
That procedure must be rehearsed before the first destructive test, not merely
linked from a failure screen.

### Layer 4 — named model qualification

Before enabling a model in a preview, record installation, interruption,
recovery, macOS coexistence, cold boot, display, keyboard, trackpad, storage,
networking, audio, suspend, update, and rollback results for that exact model.
The preview allowlist is generated from these records and fails closed when the
upstream compatibility snapshot changes.

## Required gates before implementation can become destructive

1. **Architecture decision:** choose the preferred UEFI-media route or justify
   accepting the maintenance burden of the discouraged image route.
2. **Upstream relationship:** confirm whether Omarchy will contribute a
   machine-readable interface upstream or maintain a minimal downstream fork.
3. **Artifact ownership:** identify the official owner and signing keys for the
   bootstrap, installer archive, metadata, UEFI media, Asahi packages, and
   update channel.
4. **Storage contract:** define a machine-verifiable free-extent handoff from
   the Asahi stage to the Omarchy installer. A screenshot or device name is not
   sufficient.
5. **Privilege contract:** preserve visible, local, human confirmation for the
   actual resize and Apple recovery-policy operations.
6. **Recovery readiness:** acquire a supported sacrificial device and a second
   DFU host, then demonstrate revive and restore before installation testing.
7. **Model policy:** define who can add/remove a model, which upstream snapshots
   are accepted, and what automatically disables a model.
8. **Support ownership:** establish Omarchy as first contact for distro-specific
   Apple Silicon problems, as required by Asahi's distribution guidelines
   ([support policy](https://github.com/AsahiLinux/docs/blob/9d0ed3c6e42bc7c1f2ffc4ae6e00fefb0068f151/docs/alt/policy.md#L118-L131)).
9. **M4 boundary:** keep the prototype M4 simulation-only until official Asahi
   installer support changes and Omarchy completes named-device qualification.

## Questions that must be answered before Phase 4 can pass review

- Are we building standard Apple-capable AArch64 UEFI media, or a streamed disk
  image? What concrete requirement makes the non-preferred route necessary?
- Who owns the downstream Asahi fork and guarantees urgent updates when Apple or
  Asahi changes the boot/firmware contract?
- Which exact M1/M2 device will be the first sacrificial target, and where is the
  second Mac that can perform DFU recovery?
- What signed object tells the Omarchy installer the exact free extent it may
  mutate, and how does it reject a stale disk layout after reboot?
- What happens if power is lost after APFS resize, after stub creation, during
  firmware extraction, before 1TR, during `kmutil configure-boot`, or during the
  first Omarchy write?
- Can a user always return to macOS after every intermediate state, and what
  evidence proves it?
- Which components update m1n1 stage 2, device trees, U-Boot, firmware, GRUB,
  kernel, and platform packages after installation? How are incompatible
  combinations prevented?
- What is the signed rollback story for both the macOS preparation artifacts and
  the installed Omarchy system?
- Is reporting absent, or is it separately consented and documented? It cannot
  inherit Asahi's endpoint silently.
- Who has authority to turn a simulated model into a real-install model, and can
  a server-side flag ever weaken a locally compiled safety floor? It should not.

Until these have evidence-backed answers, the app may become a complete
simulation, artifact verifier, read-only preflight tool, and guided terminal
launcher. It may not become an independent disk or Apple boot-policy engine.
