# Omarchy on Apple Silicon: progress brief

Prepared: 2026-08-24

## The headline

Omarchy is already running successfully on a physical 14-inch M1 Pro MacBook
Pro as the maintainer's working system.

The physical machine proves the real Apple Silicon experience. A separate clean
disposable aarch64 installation proves that the package and installation path
is reproducible. Together, these move the work beyond feasibility: the product
runs on real M1 Pro hardware and its software transaction completes from a
clean state.

## Physical M1 Pro validation

The current system reports:

- Apple MacBook Pro (14-inch, M1 Pro, 2021)
- `aarch64`
- Apple device-tree identifiers `apple,j314s` and `apple,t6000`
- `linux-asahi 7.1.6.asahi1-1`
- `m1n1 1.5.2-1`
- Mesa `26.1.7-1`
- Signed local Omarchy release sequence 17, `asahi-quattro-59c188fa`

The maintainer confirms that Omarchy and the machine's normal desktop and
hardware functions are working. This is sufficient to validate the claim that
Omarchy works on this M1 Pro. Broader support across other Apple models remains
a separate product and test-matrix question.

## What is complete

### Package feasibility is measured, not estimated

- Traced 450 direct inputs across Omarchy, `omarchy-iso`, optional installs,
  package recipes, and the Apple Silicon reference manifests.
- Found 323 inputs in the tested Arch Linux ARM and Asahi indexes; 322 resolve
  with their complete dependency closure.
- Classified 354 inputs as usable as-is or correctly excluded from ARM.
- Identified the real official-distribution blocker: the official Omarchy
  aarch64 repository endpoints do not exist. The four mandatory official
  packages therefore have no official aarch64 source today.
- Separated genuine blockers from x86-only hardware packages and optional
  applications that do not determine whether the desktop can run.

### The local Apple Silicon install path is deterministic

- The runtime manifest contains 141 explicit packages.
- Ten source-built packages now live in a checked-in manifest rather than a
  hard-coded installer array.
- Source builds use a pinned `omarchy-pkgs` revision so upstream recipe changes
  cannot silently alter a validation run.
- Release artifacts are signature-verified before use.
- The installer validates its runtime and source manifests before its first
  persistent mutation.
- Asahi-owned kernel, GPU, firmware, repository, and boot state remain outside
  Omarchy's ownership boundary.

### A reproducible fresh installation completed end to end

The separate disposable-VM run used signed release sequence 18,
`4.0.0-mac.14`:

- 664 repository packages installed.
- The complete signed nine-package release transaction installed.
- All ten pinned source packages built and installed.
- The final package database contained 972 packages.
- All 141 runtime-manifest entries and all ten source-manifest entries were
  present; both missing-package reports were empty.
- Reboot verification, migrations, updater state, protected-package checks,
  protected boot-file hashes, and safe rerun behavior passed.
- SDDM rendered the Omarchy password greeter after reboot and retained the
  expected user and session.

### The validation harness now survives realistic failures

The first runs exposed issues in the test environment rather than package
closure: network reloads broke SSH supervision, and larger QEMU guests caused
host out-of-memory kills. The harness was hardened to:

- run the guest workflow as a detached system-managed job;
- persist the full log and an atomic exit status in the guest;
- reconnect after expected network reloads;
- detect dead or zombie QEMU processes;
- use a conservative 2-vCPU, 3-GiB default;
- retain a host-backed package cache while still verifying package integrity.

Those changes turned a fragile smoke test into a repeatable failure-reporting
and validation workflow.

## What this means

The core Omarchy desktop is not the architectural problem. Most of it already
resolves on ARM. The remaining work divides cleanly into three different
ownership areas:

1. **Current Apple Silicon product:** preserve and regression-test the working
   M1 Pro experience.
2. **Official ARM distribution:** choose an ARM base, publish and sign the
   mandatory Omarchy aarch64 packages, and define the supported application
   set.
3. **Installation media and Apple boot integration:** finish generic ARM media
   first, then integrate with the boot environment owned by Asahi rather than
   recreating it inside Omarchy.

The fork demonstrates a working product path. It should be used as an evidence
and test source, not merged wholesale into Basecamp Omarchy.

## What remains outside the current proof

- Repeatable validation across other Apple Silicon models and SoC generations.
- A structured evidence capture for each physical subsystem on the current M1
  Pro; the system is working, but not every observation has a retained command
  transcript or artifact yet.
- Installation and recovery across supported Apple models.
- An official signed Omarchy aarch64 repository and release channel.
- A generic ARM64 installer artifact built by official infrastructure.
- A product decision on whether ARM must reproduce every x86 preinstalled app
  or may use an explicit supported subset.

## Recommended next move

Treat the current M1 Pro as the first validated reference machine. Capture its
working state with the checked-in hardware checklist so the existing success is
auditable and repeatable, not because hardware functionality is still blocking
the central claim.

In parallel, decide whether the goal is:

- a maintained local Apple Silicon edition using the current signed bundle; or
- an official Omarchy ARM product, which requires repository, signing, media,
  application-parity, and support-policy commitments.

No upstream pull request or push is part of the current work policy.

## Supporting material

- [Presentation speaking notes](dhh-apple-silicon-speaking-notes.md)
- [Validation evidence appendix](dhh-apple-silicon-evidence.md)
- [Package parity report](aarch64-package-parity.md)
- [Machine-readable package matrix](aarch64-package-parity.json)
- [Physical hardware checklist](apple-silicon-hardware-validation.md)
- [Tracked local execution plan](apple-silicon-local-plan.md)
