---
title: Testing and qualification
description: Every test suite and release gate, what each one proves, and what none of them can prove.
section: How it is built
---

Omarchy MX Mac writes to the internal disk of a Mac that also holds macOS. Getting that wrong is expensive for the person it happens to, so the testing is arranged around a single question: what would have to be true before this release touches a stranger's disk?

The answer is a ladder. Each rung is cheap and broad at the bottom and expensive and narrow at the top. A rung never claims what the rung above it exists to prove, and the project writes that limit down rather than letting it be assumed.

{{diagram:test-ladder}}

## What each layer proves

| Layer | Runs | Where | Proves | Cannot prove |
| --- | --- | --- | --- | --- |
| Source tests | Every push and pull request | Four parallel shards in CI | Scripts behave as specified against fixtures | That an installed system works |
| Package manifests | Push, pull request and weekly | Arch and Arch Linux ARM containers | The package lists resolve on both architectures | That installing them succeeds |
| Fresh-install acceptance | Every full release | A virtual machine on a test Mac | A clean install from the candidate boots, updates and passes its checks | Anything about Apple hardware |
| Image acceptance | Every image build | A virtual machine on a test Mac | The image boots plain and encrypted, and again after a reboot | The real boot chain, which uses a different kernel |
| Graphical acceptance | By hand, when the desktop changes | A disposable virtual machine with a live session | Applications launch, panels and menus work | Anything about Apple hardware |
| Hardware qualification | By hand, before a boot change ships | A real Mac, cold booted | Apple firmware, the real kernel, displays, audio, suspend | Every model, since only two are in the lab |

The gap in the right-hand column is the honest part. No virtual machine in this project boots the kernel that a user boots, for a reason given below. That is why a hardware step exists at all, and why it cannot be automated away.

## Source tests

Two suites, both pure. They read fixture trees and stubbed commands and assert on what a script would do, so they need no Mac, no virtual machine and no network.

```bash
./test/all      # both suites
./test/cli      # the command-line router
./test/shell    # everything else
```

**The command-line suite** is one script with 65 assertions. It drives the `omarchy` router end to end: help output, the command list in both human and JSON form, and the checks that every one of the 200-plus documented commands carries a summary, that the JSON keeps its shape, and that dispatch refuses anything unsafe. It also covers the theme helpers.

**The shell suite** is 316 test files in `test/shell.d/`, one per area. They divide roughly like this:

| Area | Files | Examples of what they assert |
| --- | --- | --- |
| Desktop, compositor and interface | 67 | Hyprland configuration, plugins, monitors, the top bar, menus, the lock screen, themes |
| Apple Silicon, Asahi, Aurora and boot | 45 | The boot check, the Limine path, fresh installs, the Aurora verification hook, kernel markers |
| Hardware and peripherals | 34 | Battery, networking, Bluetooth, audio, sleep, fingerprint, brightness, printing |
| Install, packages and applications | 29 | Optional package transactions, web apps, browsers, development tooling |
| Update, migration and channels | 25 | The updater's stages, migrations, the channel record, the update lock |
| Agents and usage | 9 | The usage scanners and their panel |
| Security | 6 | Privilege grants, the encrypted boot check, the keyring |

Run one file directly, or shard the suite the way CI does:

```bash
./test/shell --list
./test/shell --shard 1/4
```

## Package manifests

A separate workflow resolves the default package lists against real repositories, for x86 and for aarch64, in containers matching each. It proves the lists are installable in principle and catches a package that has been renamed or dropped upstream. The workflow says plainly that it verifies resolvability only, and that end-to-end installation is the acceptance harness's job.

## Fresh-install acceptance

This is the gate a full release cannot skip. It builds a throwaway virtual machine on one of the test Macs, installs Omarchy into it from the candidate exactly as a user would, and then interrogates the result.

It deliberately does the awkward things a real installation might suffer: it interrupts the install and resumes it, reboots, runs the installer a second time to check it refuses, and exercises the optional package transactions.

The verification stage alone carries 45 assertions. Among them: the release version, sequence and tag agree; `[omarchy]` leads the pacman configuration with signatures required; both signing fingerprints are present; the candidate descriptor checksum and every package version match; the expected units are enabled; the network backend is iwd; no migration is left pending; `pacman -Qkk` reports no modified files; the temporary build account is gone; and the boot payloads are the ones the release publishes.

A passing run prints 25 `ok` lines and exits zero. That number is worth reading correctly: 23 of them are the optional-package installs, and the entire 45-assertion verification collapses into one. It takes 10 to 15 minutes.

Packages come from a dated, immutable mirror snapshot rather than the live mirrors, so a mirror in the middle of its own update cannot fail a run that has nothing to do with it.

## Image acceptance

The Mac image gets its own harness, because the thing a user installs is an image, not a package transaction. It verifies the image signature and every member digest, unpacks the payload, then boots it twice over: once plain, and once with the in-place conversion to an encrypted root, followed by a second boot that must unlock with the passphrase and reach a login rather than an emergency shell. Seven checks, each printing its own line.

Here is the limitation that shapes everything above it. **The Aurora kernel cannot boot on QEMU's virtual machine at all**: there is no PL011 console, no generic PCI host and no ACPI. The harness therefore boots a generic Arch Linux ARM kernel, with an initramfs built from the image's own hooks so the hooks themselves are still exercised. The harness's own documentation states the consequence: the boot loader, m1n1 and the Apple hardware are qualified on a real Mac, and this harness cannot stand in for that.

## Graphical acceptance

Nine files that run inside a live Omarchy session, reached over SSH, in a disposable virtual machine. Because a remote shell inherits none of a desktop session, the runner finds the compositor's socket and bus for itself, waits up to five minutes for Hyprland, and gives each file seven minutes.

They check that the compositor reports a monitor and the shell is running on a btrfs root; that the core packages are installed and the running kernel has matching headers; that the daily applications open and close; that the emoji picker and clipboard history appear; that the weather and power panels behave; that the menu works; that printing is configured without a root backend or automatic discovery; and that the security grants are opt-in rather than shipped.

This suite is not in CI and is not part of `./test/all`, on purpose: it opens and closes real applications and changes desktop configuration while it runs, so it belongs in a machine you can throw away. Its own notes admit a limit too, that synthetic keystrokes inside the guest do not reliably prove a global keybinding works.

## Hardware qualification

Everything above stops short of Apple silicon. The last rung is a person at a real Mac.

The checklist covers platform identity, desktop and graphics, networking, audio, power and suspend, and update safety. Its rules are stricter than they first look:

- Hardware acceleration must be reported. A software renderer is a failure, not a pass.
- Paths that cannot be tested are recorded as **not tested**, never as passed.
- Suspend is tested from a local session, on AC and on battery, because an SSH session cannot prove a lid or a wake.
- A path is never marked passed on the strength of virtual-machine evidence.

After any boot that follows a kernel or boot-file change, a cold boot and a further set of remote checks are required: the boot check, no failed units, the vendor firmware service finished, the monitors the session actually has, and a speaker-to-microphone tone measurement to prove audio end to end. The checklist also carries a list of known noise, so that a documented harmless message is not mistaken for a regression.

Two Macs carry this: a 14-inch MacBook Pro with M1 Pro, which takes the full regression, and a 16-inch MacBook Pro with M2 Max, used for multi-display work.

## The release gates

Gates are enforced by the release tooling, not by good intentions. A candidate stops at the first one it cannot clear.

| Gate | What must be true |
| --- | --- |
| Candidate build | Every package builds and signs, and the descriptor lists each archive with its digest |
| Fresh-install acceptance | A run passes and its record is bound to that exact candidate identity |
| Hardware evidence | Required whenever a boot package moves |
| Promotion | The promoted release is a byte-identical copy of the accepted candidate |
| Channel publication | The sequence strictly increases and every published object is read back |
| Catalog signature | The owner signs, with a key that never leaves their Keychain |

A **boot package** is a kernel, m1n1, U-Boot, the Asahi firmware and script tools, the boot package or the Limine hook, or a DKMS module. One counts as moved when the release would publish a different version, or when its recipe changed, or when its payload differs file by file including mode, owner and content. A comparison that cannot be made also counts as moved, which is the safe direction. The tooling states outright that virtual-machine acceptance boots a generic kernel and cannot clear this gate.

Clearing it means testing on a real Mac and handing the release a record whose lines match exactly what the release will publish: the candidate hash, each boot package with its version, and the kernel pin.

## Evidence

Every acceptance run writes a directory under `~/vm-evidence/`, holding the identities it ran against, the result, the logs with their hashes, a checksum file and a screenshot of the desktop it reached. A passing fresh-install run deletes its own 23 GB disk image; a failing one keeps it for inspection. Acceptance records are committed alongside the release they belong to, and a valid record for the same candidate already on the main branch counts in place of running it again.

The hardware evidence record is plain text: date, model, pass or fail or not-tested, the command, its output and where any artefact lives.

## Where the release tooling runs tests

| Workflow | Trigger | What it runs |
| --- | --- | --- |
| Source tests | Push and pull request | The shell suite across four shards, with the command-line suite on the last |
| Packages | Push, pull request, weekly | Manifest resolution for both architectures, a recipe audit, an install transaction |
| Optional packages | Pull request, weekly | The command-line suite, four named shell tests, and a live optional-package check |
| Release | Manual only | Seven named shell tests again, immediately before signing |

The package repository has its own 43 test scripts covering the release machinery: the incremental planner's input classification, candidate assembly, promotion binding, channel pointers, the image builder, the encryption path and first boot. Its verification tools are separate commands, so the same check can run in a workflow and by hand: the image checker has five modes, and there are verifiers for candidates, channels, edge releases and the signing subkey.

## What is not tested

Stated plainly, because a reader deciding whether to trust this with a disk deserves it.

- **No virtual machine boots the kernel you will boot.** The Aurora kernel cannot run under QEMU's virtual machine, so every automated boot test substitutes a generic kernel.
- **No automated test touches Apple hardware.** The graphics, Wi-Fi, audio, suspend and power behaviour of a Mac are covered by a person following a checklist, on two machines.
- **Two Macs are not every Mac.** The catalog admits far more identifiers than the lab owns. Models beyond the two reference machines rely on Asahi's support for that chip and on the fork's fail-closed behaviour, not on having been tried here.
- **The hardware evidence gate checks the paperwork, not the testing.** It verifies that the record matches what the release publishes. It cannot verify that the tests behind it were actually performed.
- **The graphical suite never runs in CI**, so a desktop regression is caught only when someone runs it.
- **Some test scripts run in no workflow.** In the package repository, 13 of the 43, including the one covering the encryption path, are run by hand rather than on every change.
- **The source tests are contract tests.** All 316 of them assert what a script would do against a fixture. Passing them says nothing about an installed system, which is what the rungs above exist for.
- **Unified kernel images are not inspected** by the fresh-install harness, which matters more as the Limine path lands.
