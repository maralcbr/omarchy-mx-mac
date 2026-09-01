# Work Changelog

This is the chronological engineering record for local work. Read it before
starting, append notes while work is active, and include validation evidence,
decisions, blockers, commits, and the next action. Keep entries tool agnostic.

## 2026-08-24

### Active — Align local execution with the six-phase roadmap

- Reviewed the existing six-phase integration roadmap, detailed Phase 1 plan,
  current package-validation record, physical M1 Pro evidence, and the original
  engineering brief.
- Decision: retain the roadmap's fixed Phase 1–6 dependency order and describe
  current results as local evidence, not official phase completion.
- Classified the current state as: Phase 1 locally proven but not extracted
  against current upstream; Phase 2 transaction proven through the local signed
  channel but blocked on official publication; Phase 3 seam demonstrated but
  blocked on the official feed; Phase 4 operational as an M1 Pro prototype;
  Phase 5 limited to one candidate model; and Phase 6 not started.
- Expanded `docs/apple-silicon-local-plan.md` with a promotion lane for Phases
  1–3 and a parallel evidence-incubation lane for Phases 4–5. This preserves the
  formal phase gates while allowing useful local validation to continue.
- Added three executable milestones: a local Phase 1 promotion dossier, a Phase
  2 publication decision pack, and a named M1 Pro Phase 4–5 evidence baseline.
- Constraint: keep all work local; do not push, create upstream branches, or
  open pull requests.
- Next: freeze the current upstream/MX revisions and map every PR0–PR4 behavior
  to its implementation, focused tests, and remaining evidence gap.

### Active — Prepare Apple Silicon presentation material

- Clarification: the current Omarchy instance is already running successfully
  on physical Apple Silicon, so the presentation must treat the M1 Pro as the
  primary real-hardware validation and the disposable VM as clean-install and
  package-reproducibility evidence.
- Captured read-only physical identity: Apple MacBook Pro (14-inch, M1 Pro,
  2021), `aarch64`, Apple `j314s/t6000`, kernel `7.1.6-1-1-ARCH`,
  `linux-asahi 7.1.6.asahi1-1`, `m1n1 1.5.2-1`, Mesa `26.1.7-1`, and local
  signed release sequence 17 (`asahi-quattro-59c188fa`).
- The maintainer confirms that Omarchy and the machine's normal desktop and
  hardware functions are working. This validates the current M1 Pro; it does
  not by itself establish support for every Apple Silicon model.
- The read-only documentation environment could not access the live display or
  D-Bus sockets, so detailed renderer, network, audio, and power transcripts
  remain optional evidence-capture follow-up rather than reported failures.
- Updated `docs/dhh-aarch64-status.md` from its pre-validation milestone state
  into an executive progress brief reflecting the completed sequence-18 clean
  install and its evidence boundary.
- Added `docs/dhh-apple-silicon-speaking-notes.md` with a five-minute narrative,
  likely questions, direct answers, and claims that must remain out of scope.
- Added `docs/dhh-apple-silicon-evidence.md` with tested revisions, package and
  installed-closure results, harness failure history, validation evidence, and
  the remaining physical-hardware and official-product dependencies.
- Decision: presentation claims distinguish the validated physical M1 Pro and
  reproducible software/package path from untested Apple models. The material
  does not imply an approved upstream PR, official ARM release, wholesale fork
  merge, or all-model hardware support promise.
- Validation: every local link in the three presentation files resolves and
  `git diff --check` passes.
- Next: review the presentation pack for tone, then capture additional
  structured M1 Pro subsystem evidence when convenient and apply the checklist
  to any additional model proposed for support.

### Active — Establish durable work records and continue package validation

- Decision: all Apple Silicon work remains on local branches. Do not push or
  create upstream pull requests unless this policy is explicitly changed.
- Added repository guidance requiring every activity and note to be recorded
  here and requiring a live tracked plan with status and evidence.
- Added `docs/apple-silicon-local-plan.md` as the active execution plan.
- Audited all scripts invoked by `test/vm/asahi-fresh/run` and ran a host
  preflight. Docker and `/dev/kvm` are present, but sandboxed Docker access
  requires explicit approval.
- Found a sequencing blocker before starting the VM: the candidate installer
  reads `omarchy-asahi-source.packages` from the bundled `omarchy-dev` archive,
  while the harness intentionally downloads the previous published bundle whose
  archive predates that manifest. An unadapted run would fail before package
  resolution and would not test the intended candidate/payload pair.
- Decision: add an early, deterministic payload preflight and make the local VM
  candidate fixture supply the current manifest without modifying or
  misrepresenting the verified published assets.
- Updated the fresh installer to validate both runtime and source manifests
  before its first persistent mutation. The source manifest now travels as an
  explicit file in the verified bundle directory rather than being assumed to
  exist inside an older package archive.
- Updated the VM harness to copy the current manifest into only the local
  candidate payload after verifying the published assets unchanged, and to
  record the adapter hashes in `vm-adapter.log`.
- Validation: shell syntax, both focused Asahi package/installer tests, and
  `git diff --check` pass.
- First full VM attempt verified and cached the signed 790 MiB Arch Linux ARM
  rootfs, then stopped during base-disk construction because `losetup` reported
  no usable loop device. No guest was started and no install transaction ran.
- Host diagnosis: the loop kernel module, `/dev/loop-control`, and loop block
  devices exist. A disposable privileged container subsequently attached and
  detached the same retained 96 GiB sparse raw test disk successfully using
  `/dev/loop0`, so the failure was transient rather than a missing capability.
- The retry built the base disk, verified release sequence 17
  (`asahi-quattro-59c188fa`), and passed the lock, build-account, sudo-rule,
  and package-checkout collision tests.
- The real repository transaction resolved and installed 664 packages
  (1177.33 MiB download, 4802.37 MiB installed). Pacman selected `ardour` for
  `lv2-host`, `jack2` for `jack`, and `qt6-multimedia-ffmpeg` for the Qt media
  backend.
- Blocker: post-transaction hook 6/24 reloaded system services and reset the
  guest network connection. The installation continued independently of
  pacman's completed transaction, but the host harness interpreted the SSH
  transport loss as an installer failure and destroyed the disposable
  container before bundle and source-build validation could run.
- Decision: launch the guest workflow as a system-managed detached job, write
  its complete log and exit status atomically inside the guest, and have the
  host reconnect and poll that explicit result. An SSH reset alone must be
  neither success nor failure.
- Implemented the reconnect-safe runner with a guest wrapper that atomically
  publishes the real workflow exit status. The host also detects a failed
  system service and retains the detached install log on either outcome.
- Validation: runner, guest workflow, and wrapper syntax pass; both focused
  Asahi package/installer tests and `git diff --check` pass.
- The first supervised run correctly returned and retained an explicit nonzero
  guest result. The signed stable channel had advanced from
  `4.0.0-mac.13` to `4.0.0-mac.14`, while the test paired its mutable `latest`
  URL with a hard-coded `.13` assertion. No package transaction started.
- Decision: validate the signature, descriptor format, stable track, numeric
  sequence, and source hash without pinning a mutable latest-release URL to a
  single version. The installed-version reboot check remains bound to the
  exact signed descriptor downloaded by that run.
- The corrected sequence-18 run installed all 664 repository packages and the
  complete signed nine-package bundle, including all package hooks. The host
  kernel OOM killer then killed QEMU at 03:28:29 UTC with about 8.16 GiB guest
  RSS on a 16 GiB, no-swap workstation. This occurred before the ten pinned
  source builds and before the guest could record an exit status.
- Offline, read-only recovery of the retained overlay confirmed the install log
  ends after the signed bundle post-hooks. The guest journal contains no
  shutdown, panic, or guest OOM event; host kernel logs explicitly identify
  `qemu-system-aarch64` as the killed process.
- Decision: lower the disposable default to 4 vCPUs and 5 GiB RAM, keep both
  values overridable, periodically retain the guest log, and fail promptly if
  QEMU exits or becomes a zombie while SSH is unavailable.
- The 5 GiB run completed the repository and signed-bundle transactions, then
  successfully built `aether` and `cliamp`. While resolving `localsend` build
  dependencies, the host OOM killer again selected QEMU at about 5.17 GiB RSS;
  the new liveness check failed promptly and the periodic log snapshot retained
  the exact boundary.
- Decision: use 2 vCPUs and 3 GiB by default to reduce both resident guest
  memory and build parallelism. Expose the VM's host-backed pacman cache through
  virtio 9p so clean-overlay retries reuse packages while pacman still verifies
  their integrity and signatures.
- Recovered 1,600 pacman cache files (1.8 GiB) read-only from the retained
  failed overlay. The temporary raw conversion used for recovery was deleted;
  the original qcow2 and periodic install log remain as evidence.
- The 3 GiB cached run completed successfully against signed package release
  sequence 18 (`asahi-quattro-5318aed5`, Omarchy source
  `5318aed577928f6fc228d80d3c6893ce81281c1f`, package source
  `2f683cb2d5384eea001f005e77b15b605fd1002d`).
- Result: all 664 repository packages, the signed nine-package transaction,
  and all ten pinned source packages installed. The direct Omarchy 4 reboot
  verification passed, protected Asahi packages and boot files remained
  unchanged, no migrations were pending, the updater accepted the installed
  release state, and the completed rerun was rejected without state changes.
- Exact installed-database audit: 972 total packages were installed; all 141
  explicit entries from `omarchy-base-asahi.packages` and all ten entries from
  `omarchy-asahi-source.packages` are present. Retained missing-package reports
  are empty.
- Visual evidence: the retained 1280x800 desktop frame renders the Omarchy SDDM
  password greeter after reboot. Automated checks also prove the remembered
  `omarchy` user/session, NetworkManager with iwd, and enabled SDDM.
- Environment boundary: the generic virtio VM cannot prove Apple GPU, physical
  Wi-Fi/audio, or suspend behavior. Those remain explicit hardware-validation
  items rather than package blockers.
- Local commit: `cbc62158 Harden fresh Asahi package validation`. It contains
  the installer preflight, candidate adapter, detached/reconnect-safe runner,
  QEMU liveness checks, conservative configurable resources, retained pacman
  cache, documentation, and focused tests. It was not pushed.
- Added `docs/apple-silicon-hardware-validation.md` as the next-stage physical
  test checklist. It separates read-only identity/package evidence from local
  interactive graphics, Wi-Fi, audio, suspend, and update-safety checks and
  forbids treating generic VM evidence as a hardware pass.
- Local records commit subject: `Record Apple Silicon validation work`. Do not
  push it.
- Final validation: shell syntax, focused Asahi package and fresh-installer
  tests, the complete CLI suite, and `git diff --check` pass. The CLI suite
  emitted its existing headless read-only `/run/user/1001` theme-lock warning
  but completed successfully.
- Next: commit the durable records locally, then execute the checklist on
  physical Apple Silicon hardware when a safe local test window is available.
  Do not open an upstream pull request.

### Completed — Make the Asahi source package boundary explicit

- Commit: `8f102e88 Make Asahi source package boundary explicit`.
- Moved the ten packages built from pinned `omarchy-pkgs` recipes out of a
  hard-coded installer array and into `install/omarchy-asahi-source.packages`.
- Updated the fresh installer to read the manifest from the verified Omarchy
  package archive and fail if it is missing or empty.
- Added tests proving the source set is exact, duplicate-free, and contained in
  the Apple Silicon runtime closure.
- Validation: installer syntax, focused Asahi shell tests, checkout-dependent
  package-ownership tests, and `git diff --check` passed.
- Known unrelated issue: `test/shell.d/network-qr-test.sh` fails when its
  automatic interface case receives no output; explicit-interface cases pass.

### Completed — Package parity research and repository conventions

- Commit: `5e3d1d92 Document Omarchy aarch64 package parity`.
- Recorded 450 direct inputs: 323 available in tested ARM repositories, 322
  dependency-resolving, with 354 GREEN, 92 YELLOW, and four RED mandatory
  official Omarchy artifacts.
- Confirmed the current local Apple Silicon path uses a signed six-package
  bundle to supply the mandatory runtime while official aarch64 repository
  endpoints remain unavailable.
- Commit: `8e1bcc64 Require tool-agnostic branch names`.
- Renamed the working branch to `aarch64-package-parity` and the local ISO
  reference branch to `aarch64-target-config`.
- Added the rule that branch names must never use an AI tool or agent name.

### Completed — Local architecture target reference

- Local `omarchy-iso` commit: `85d0bb4 Add explicit ISO architecture target`.
- Added an explicit architecture target, profile propagation, matching artifact
  selection, and early rejection of unsupported targets while preserving x86
  defaults.
- This branch is reference-only and will not be pushed upstream.
