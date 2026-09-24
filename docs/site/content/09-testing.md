---
title: Testing and qualification
description: What is tested, what each layer proves, and what none of it proves.
section: How it is built
---

Omarchy MX Mac writes to the internal disk of a Mac that also holds macOS. Three separate things have to be true, and they are established by different evidence that does not substitute for each other:

1. **The installer does not damage what is already on the disk.**
2. **The system it installs actually works.**
3. **It works on your particular Mac.**

Most of the automation addresses the second. This page says which evidence answers which question, because a reader deciding whether to run the installer is asking the first, and a green test suite is not an answer to it.

{{diagram:test-ladder}}

## Does the installer preserve macOS?

This is the expensive failure, and it is the least automated of the three.

**The installer is covered by unit and component tests against simulated targets.** The engine's Python overlay carries about 3,800 lines across nine modules: the planner that chooses where partitions go, staged execution and its checkpoints, interruption and resume, the repair path, replacing an existing install, and the image writer. The Swift package adds three test targets over 38 files for the trust core, the installation lifecycle and the interface, and some of those touch a real file system to check staging and permissions. What none of them do is resize a real APFS container.

**Only some of this is wired into a gate.** Building the pinned engine runs its test modules first and stops if they fail, so a broken engine cannot be packaged. The Swift tests have no such gate. Neither suite runs in this repository's continuous integration, though several shell tests do cover the app from outside.

**No virtual machine test performs the resize either.** The image harness builds its own empty disk with `sgdisk`: three partitions on a blank file, no APFS container, no macOS. The fresh-install harness installs into a blank generic machine. Neither ever meets the situation that could cost someone their macOS install.

So the evidence is the engine's planning and interruption tests, the fact that APFS resizing, the boot policy and recoveryOS are Asahi's code rather than this project's, and whatever physical installation a given release records. There is no automated end-to-end proof, and this page will not imply one.

### How to read a release's evidence

Each release carries notes and a hash-bound acceptance record in [docs/releases/](https://github.com/maralcbr/omarchy-mx-mac/tree/main/docs/releases). They are worth reading literally, because they distinguish things that are easy to blur:

- A virtual-machine acceptance pass is not a physical install.
- A physical check of one feature is not a fresh install of the final image.
- An update on an existing Mac is not a first install alongside macOS.

The notes for the current stable release say outright that a fresh physical installation of the final image was not performed. Match the identities too: the installer, the engine and the image each have their own version, and evidence for one is not evidence for another. The underlying transcripts live on the maintainer's machines and the records reference them by path and hash, so what you can inspect is the record, not the run.

## Does the installed system work?

### Source tests

Two suites that need no Mac, no virtual machine and no network.

```bash
./test/all      # both suites
./test/cli      # the command-line router
./test/shell    # everything else
```

The **router suite** drives `omarchy` end to end: help output, the command list in human and JSON form, the requirement that every one of the 200-plus documented commands carries a summary, that the JSON keeps its shape, and that dispatch refuses anything unsafe. It covers the theme helpers too.

The **shell suite** is 315 runnable files in `test/shell.d/`, plus a shared helper, roughly one per command or feature and named after what it covers. The list reads like an index of the distribution, from the compositor and the top bar to the updater, the channel record and the Apple Silicon boot path.

```bash
ls test/shell.d/          # the names are the documentation
./test/shell --shard 1/4  # the way CI splits it
```

Most are fixture tests: they assert what a script would do against a prepared tree and stubbed commands. A few probe the live session instead, and those report a skip and pass when no compositor is present. A green run on a headless machine therefore includes checks that did not run.

### Package manifests

A workflow resolves the default package lists against real repositories in containers matching each architecture. For x86 it verifies resolvability only. For aarch64 it goes further and installs each manifest into its own fresh root, which proves today's dependency closure actually installs, currently with `vulkan-asahi` excluded while an upstream rebase settles. A separate audit of optional-package recipes reports what it finds without enforcing completeness.

### Fresh-install acceptance

The gate a full release cannot skip. It exercises the Linux installation lifecycle in a throwaway virtual machine on one of the test Macs: install from the candidate, interrupt it and resume, reboot, run the installer again to check it refuses, and work through the optional package transactions.

It is an adapted environment, not a Mac: the hardware check is patched out of a retained copy of the installer and restored afterwards, and the guest boots a generic kernel.

The verification stage then interrogates the result in detail: the release version, sequence and tag agree; `[omarchy]` leads the pacman configuration with signatures required; the signing fingerprints are present; the candidate descriptor checksum and package versions match; the expected units are enabled; the network backend is iwd; no migration is pending; the runtime package passes a file-integrity check; the temporary build account is gone; and the boot payloads are present.

Run the way the release tooling runs it, with the optional-package checks enabled, a pass prints 25 `ok` lines in 10 to 15 minutes. Read that carefully: 23 of the 25 are optional-package transactions, and the whole verification stage collapses into one line. Those checks are off by default.

Packages come from a dated, immutable mirror snapshot rather than live mirrors, so a mirror mid-update cannot fail an unrelated run.

### Image acceptance

The image harness verifies the image signature and every member digest, unpacks the payload, then boots it three times: a plain first boot, an encrypted first boot that converts the root to LUKS2 in place, and a second boot that must unlock and reach a login rather than an emergency shell. Seven milestones for a full release-backed run.

Two limits matter. The second boot unlocks with the throwaway key file the conversion leaves on the boot partition, so **owner passphrase enrolment and passphrase unlocking are not tested here**. And the Aurora kernel cannot boot on QEMU's virtual machine at all, for want of a PL011 console, a generic PCI host and ACPI, so the harness boots a generic Arch Linux ARM kernel with an initramfs built from the image's own hooks. Its own documentation draws the conclusion: the boot loader, m1n1 and the Apple hardware are qualified on a real Mac, and this harness cannot stand in for that.

Image acceptance is run separately from the workflow that builds and publishes an image. That workflow checks layout, provenance and descriptors, and signs; it does not require a harness result.

### Graphical acceptance

Eight tests that run inside a live session in a disposable virtual machine, reached over SSH. The runner finds the compositor's socket and bus itself, because a remote shell inherits none of a desktop.

They check that the compositor reports a monitor and the shell runs on a btrfs root; that core packages are installed and the kernel has matching headers; that daily applications open and close; that the emoji picker and clipboard history appear; that the weather and power panels behave; that the menu works; that printing has no root backend and no automatic discovery; and that security grants are opt-in rather than shipped.

It is not in CI and not in `./test/all`, deliberately, because it opens real applications and changes desktop configuration as it runs. Its notes admit that synthetic keystrokes in the guest do not reliably prove a global keybinding works.

## Does it work on your Mac?

A person at a real Mac, following a checklist that covers platform identity, desktop and graphics, networking, audio, power and suspend, and update safety. Its rules are stricter than they look:

- Hardware acceleration must be reported. A software renderer is a failure, not a pass.
- An untestable path is recorded as **not tested**, never as passed.
- Suspend is tested from a local session, on AC and on battery, because SSH cannot prove a lid or a wake.
- A path is never marked passed on virtual-machine evidence.

After any boot following a kernel or boot-file change, a cold boot and further remote checks are required: the boot check, no failed units, the vendor firmware service finished, the monitors the session really has, and a tone played through the speakers and captured on the microphone to prove audio end to end. The checklist also lists known harmless messages, so noise is not read as regression.

Two Macs carry this: a 14-inch MacBook Pro with M1 Pro for the full regression, and a 16-inch MacBook Pro with M2 Max for multi-display work. The current catalog admits 22 M1 and M2 models; these two are the only ones qualified on hardware.

## What the release gates actually enforce

Gates are enforced by tooling, and it is worth being precise about what each one checks rather than what it is named after.

| Gate | What the tooling actually verifies |
| --- | --- |
| Candidate build | Changed packages build and sign, eligible archives are reused, and every one keeps its signature and digest check |
| Fresh-install acceptance | A fresh run must pass, with its exit status, identities, log hashes and failures checked. A matching committed record is accepted instead, without rechecking its logs |
| Hardware evidence | A supplied record's identity lines match the candidate and the boot packages that moved |
| Promotion | The promoted release is a byte-identical copy of the accepted candidate |
| Channel publication | The sequence strictly increases and every published object is read back |
| Catalog signature | The owner signs, with a key that never leaves their Keychain |

The **hardware evidence** gate is the weak one. It binds a record to the candidate and to the boot packages that moved, and checks nothing else: no stated outcome, no model, no date, no transcript. It makes publishing an unqualified release hard to do by accident, and proves nothing about whether the testing happened.

A **boot package** is a kernel, m1n1, U-Boot, the Asahi firmware and script tools, the boot package, the Limine hook or a DKMS module. One counts as moved when the release would publish a different version, when its recipe changed, or when its payload differs file by file. A comparison that cannot be made counts as moved too, which is the safe direction.

There is also a **fast path** that publishes a runtime-only change without VM acceptance, an image, or a package channel. It is allowed only when the candidate rebuilt nothing but runtime packages and its package set is exactly what the live channel already publishes.

## Evidence

A fresh-install run writes a directory holding the identities it ran against, the result, the logs with their hashes, a checksum file and a screenshot of the desktop it reached; a passing run deletes its own 23 GB disk image and a failing one keeps it. The image harness records identities and logs without that bundle. Acceptance records are committed alongside their release, and a valid record for the same candidate already on the main branch counts instead of a fresh run.

Hardware evidence is plain text: date, model, pass or fail or not-tested, the command, its output, and where any artefact lives.

## What is not tested

- **The installer's own tests are not in CI.** The engine's run when the engine is built, which is a real gate; the Swift tests are run by hand.
- **No test boots a Mac on an owner passphrase.** Enrolment and recovery have fixture tests with a stubbed `cryptsetup`, and the image harness unlocks with a throwaway key file, so the two halves are never joined.
- **No automated test touches Apple hardware.** Graphics, Wi-Fi, audio, suspend and power are a person with a checklist, on two machines.
- **The graphical suite never runs in CI**, so a desktop regression waits for someone to run it.
- **Some suites run in no workflow at all.** In the package repository, 13 of 43 test scripts, including the one covering the encryption path.
- **A green headless run can contain skips**, because the runtime probes pass when no compositor is present.
- **Unified kernel images are not inspected** by the fresh-install harness, which matters now that the current image boots through Limine.
