# Apple Silicon validation evidence appendix

Evidence snapshot: 2026-08-24

This appendix supports the claims in
[`dhh-aarch64-status.md`](dhh-aarch64-status.md). It distinguishes completed
proof on the current physical M1 Pro, reproducible VM proof, and work that
would be required for broader model or official-product support.

## Physical M1 Pro reference system

Read-only identity captured on 2026-08-24:

- Model: Apple MacBook Pro (14-inch, M1 Pro, 2021)
- Architecture: `aarch64`
- Device tree: `apple,j314s`, `apple,t6000`, `apple,arm-platform`
- Kernel: `7.1.6-1-1-ARCH`
- `linux-asahi`: `7.1.6.asahi1-1`
- `linux-asahi-headers`: `7.1.6.asahi1-1`
- `m1n1`: `1.5.2-1`
- Mesa: `26.1.7-1`
- Installed local release sequence: 17
- Installed release tag: `asahi-quattro-59c188fa`
- Installed source revision:
  `59c188fa9cc70afed21344074d49d7ff6f2ea802`

The maintainer confirms that this is the current running Omarchy system and
that its normal desktop and hardware functions are working. This is the
physical validation for the current M1 Pro implementation.

The read-only command environment used while preparing this appendix could
read kernel, device-tree, package, and release identity. Its sandbox could not
connect to the live display or D-Bus sockets, so renderer, NetworkManager,
PipeWire, and power-service transcripts were not captured in that pass. That is
an evidence-retention limitation, not a reported failure of the running system.

## Revisions under test

- Signed local release: sequence 18, `asahi-quattro-5318aed5`
- Omarchy version: `4.0.0-mac.14`
- Omarchy source:
  `5318aed577928f6fc228d80d3c6893ce81281c1f`
- Package-recipe source:
  `2f683cb2d5384eea001f005e77b15b605fd1002d`
- Current local validation records: `e986dd06`
- Fresh-install hardening: `cbc62158`
- Explicit source-package boundary: `8f102e88`
- Package-parity research: `5e3d1d92`
- Reference `omarchy-iso` architecture seam: `85d0bb4` on the separate local
  `aarch64-target-config` branch

## Package research evidence

The package inventory traces 450 direct inputs from the current Omarchy
runtime, current ISO inputs, optional transactions, package recipes, and the
Apple Silicon reference manifests.

- 323 lead packages are present in the tested Arch Linux ARM and Asahi indexes.
- 322 lead packages resolve with their dependency closure.
- 354 inputs are usable as-is or correctly excluded as architecture-specific.
- Four mandatory official packages lack an official aarch64 repository source:
  `omarchy`, `omarchy-settings`, `omarchy-keyring`, and `omarchy-nvim`.
- One dependency trap was confirmed: `winetricks` is present, but its
  transaction cannot resolve because `wine` is absent.

Canonical artifacts:

- [`aarch64-package-parity.md`](aarch64-package-parity.md)
- [`aarch64-package-parity.json`](aarch64-package-parity.json)

## Fresh-install transaction evidence

The successful run started with a clean overlay and an empty guest package
state. A host-backed cache reused downloads from earlier attempts, but pacman
still verified integrity and signatures before installation.

Completed transaction:

- 664 repository packages installed.
- All nine packages in the signed release transaction installed.
- All ten packages in `install/omarchy-asahi-source.packages` built from the
  pinned recipe revision and installed.
- 972 packages were present in the final package database.
- Every one of the 141 explicit runtime entries was installed.
- Every one of the ten explicit source entries was installed.
- Runtime and source missing-package reports were empty.

Provider choices recorded by pacman:

- `ardour` provided `lv2-host`.
- `jack2` provided `jack`.
- `qt6-multimedia-ffmpeg` provided the Qt media backend.

## Reboot and state evidence

After the completed installation:

- SDDM rendered the Omarchy password greeter at 1280x800.
- The expected `omarchy` user and session were remembered.
- NetworkManager with the iwd backend was enabled.
- No Omarchy migrations remained pending.
- The updater accepted the installed signed release state.
- Protected Asahi package versions and boot-file hashes were unchanged.
- Re-running the completed installer was rejected without state changes.

These checks establish reproducible installation and correct installed state in
a generic aarch64 VM. Physical behavior is established separately by the
working M1 Pro reference machine above.

## Harness reliability evidence

Three failure boundaries were captured before the successful run:

1. A transient loop-device allocation error stopped before guest creation.
2. A repository hook reloaded services and interrupted SSH after the repository
   transaction, revealing that transport status was not workflow status.
3. QEMU guests configured with 8 GiB and then 5 GiB were killed by host memory
   pressure during later stages.

The resulting controls are checked into the harness:

- detached, system-managed guest execution;
- complete persistent guest log;
- atomic guest exit-status file;
- reconnect and explicit-result polling;
- QEMU dead/zombie detection;
- periodic log retention;
- configurable resources with 2 vCPUs and 3 GiB as defaults;
- host-backed verified pacman cache.

The final run completed under the 3-GiB profile.

## Automated validation

Recorded passing checks include:

- Bash syntax for the installer and VM workflow scripts.
- Focused Asahi package tests.
- Focused fresh-installer tests.
- The complete CLI test suite.
- `git diff --check`.

The CLI suite emitted an existing headless read-only warning for the
`/run/user/1001` theme lock and still completed successfully.

An unrelated automatic-interface case in `network-qr-test.sh` fails in this
environment. Explicit-interface cases pass. This issue is outside the Apple
Silicon package transaction and is not counted as a package blocker.

## Evidence still worth retaining

The M1 Pro system is working. The following detailed transcripts and artifacts
should still be captured so that success can be repeated and compared over
time:

- A renderer transcript documenting the working Apple GPU acceleration.
- Display summaries documenting scaling, hotplug, and resume behavior.
- Network transcripts documenting Wi-Fi, DNS, IPv4/IPv6, reconnection, and
  Bluetooth.
- PipeWire/WirePlumber summaries documenting working speakers, microphone, and
  available external audio paths.
- Timestamped suspend/resume records on AC and battery.
- Post-resume records for graphics, input, network, audio, brightness, and
  clock behavior.
- Installation, recovery, and macOS-coexistence evidence for any additional
  model proposed for support.

Use [`apple-silicon-hardware-validation.md`](apple-silicon-hardware-validation.md)
for this evidence. The current M1 Pro is the physical reference; the generic VM
must remain package/install evidence only.

## Official product dependencies

The local signed-bundle path is proven, but an official Omarchy ARM product
would additionally require:

- official aarch64 package repository ownership, publication, and signing;
- a supported generic ARM base environment;
- an official generic ARM media build and boot pipeline;
- an explicit mandatory and optional application policy;
- an Apple installation bridge that preserves Asahi's ownership boundary;
- named device validation and a support policy;
- a migration and release-channel strategy for existing local installations.

None of those official-product dependencies is represented as approved or
complete by the local validation work.
