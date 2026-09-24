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

The gate a full release cannot skip. It exercises the Linux installation lifecycle in a throwaway virtual machine on one of the test Macs: install from the candidate, interrupt it and resume, reboot, check the result, run the installer again to check it refuses, and work through the optional package transactions.

It is an adapted environment, not a Mac. The installers' device-tree checks are patched out of copies made for the VM, the Apple Silicon hardware helper is stubbed during the install and put back afterwards, and the guest boots a generic kernel.

Run the way the release tooling runs it, with the optional-package checks enabled, a pass prints 25 `ok` lines in 10 to 15 minutes. Read that carefully: 23 of the 25 are optional-package transactions, and the whole verification stage collapses into one line. Those checks are off by default. Every other check is silent when it passes and stops the run when it fails, so the full list is in [every check in a fresh-install run](#every-check-in-a-fresh-install-run) rather than in the log.

Packages come from a dated, immutable mirror snapshot rather than live mirrors, so a mirror mid-update cannot fail an unrelated run.

### Image acceptance

The image harness verifies the image signature and every member digest, unpacks the payload, then boots it three times: a plain first boot, an encrypted first boot that converts the root to LUKS2 in place, and a second boot that must unlock and reach a login rather than an emergency shell. Seven milestones for a full release-backed run. The full list is in [every check in an image run](#every-check-in-an-image-run).

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

## Every check in a fresh-install run

The harness is `test/vm/asahi-fresh/`: `run` on the host, the scripts in `container/` that build and start the VM, and the scripts in `guest/` that run inside it. Each row below is a check that ends the run as a failure when it does not hold. Plumbing that can also fail (a download, a copy, an SSH connection) is left out unless it decides something.

### Setup and base image

| Check | What it proves | Script |
| --- | --- | --- |
| The run ID, CPU and memory counts, mirror address and channel addresses are well formed | The run starts from inputs it can trust, before anything is created | `run` |
| The evidence directory is not inside the VM state directory | Deleting a finished run's disk can never delete its evidence | `run` |
| A candidate is named in full: 40-character commit tag, 64-character descriptor checksum, 40-character signing fingerprint, a package count and a readable key; a pinned runtime also needs its manifest checksum and source commit | The run tests one exact candidate, not "the latest" | `run` |
| The host lock is a regular file owned by this user, is taken (or waited for with `--wait-for-lease`), and still names the same file afterwards; the state directory is owned by this user and leased | Two runs never share the Docker daemon, ports, KVM or state directory | `run` |
| The run ID has no existing run directory, evidence directory or container, and no running container already forwards the SSH or VNC port | A run never reuses or overwrites another run's files or VM | `run` |
| The package channel resolves to an `asahi-packages-channel-N` tag, and that channel names exactly one `asahi-packages-stable-<commit>` set | The package set verification expects is fixed before the install, so it is never learned from the system being checked | `run` |
| The Arch Linux ARM root file system's signature verifies with the Arch Linux ARM build key, whose fingerprint must match | The VM starts from genuine upstream Arch Linux ARM | `container/build-base` |
| The Asahi keyring package matches a pinned SHA-256 | The Asahi repository is trusted through a known key, not whatever was downloaded | `container/build-base` |
| The base holds exactly one generic kernel before the Asahi kernel is added, and its loop device is released before conversion | The cached base disk is complete and consistent | `container/build-base` |
| The run directory lies under `/work` and the CPU count is a positive integer | The VM's disk and logs land where the run expects them | `container/start-vm` |
| The guest answers SSH within about four minutes | The base VM boots; if not, the serial log is shown | `run` |
| After the mirror is rewritten, no Arch Linux ARM server except the dated snapshot is left in the pacman configuration | Every Arch Linux ARM package comes from the snapshot. Repeated before the candidate install, before every installer run and before the optional packages | `guest/alarm-snapshot` |

### Candidate repository and signatures

Release runs always name a candidate. Without one, the install uses the published channel instead (last table in this group).

| Check | What it proves | Script |
| --- | --- | --- |
| The candidate's inputs are well formed and its key file is readable | The guest checks the same exact candidate the host was given | `guest/candidate-repository` |
| The downloaded `CANDIDATE` descriptor's SHA-256 matches the checksum given | This is the exact descriptor the release built | `guest/candidate-repository` |
| The descriptor says `format=1` and `channel=candidate`, and names this tag, its commit, the signing fingerprint and the package count, with that many `package=` lines | The descriptor describes this candidate and nothing else | `guest/candidate-repository` |
| `CANDIDATE.sig` verifies, signed by exactly the expected fingerprint; the key's primary fingerprint is well formed and is locally trusted by pacman | The descriptor was signed by the Apple Silicon repository key | `guest/candidate-repository` |
| Every package line has a valid name and a version; the names are unique and their number matches the count | The package list is complete and unambiguous | `guest/candidate-repository` |
| Every candidate package installs from a first-place `[omarchy]` repository that requires signatures | The candidate's packages install together, signed, from the candidate release | `guest/candidate-repository` |
| `linux-asahi`, its headers, `m1n1` and `grub` keep their versions, and the VM kernel, its initramfs, the Asahi kernel and `grub.cfg` keep their hashes | Installing the candidate leaves the VM's own boot files alone (these four packages are held back) | `guest/candidate-repository` |
| Each installed package's version equals the descriptor's | pacman installed the candidate, not a newer or older copy | `guest/candidate-repository` |
| Every mkinitcpio preset builds when run directly, names at least one image, and writes each one non-empty | The candidate's initramfs hooks work; pacman alone would hide a failed hook | `guest/candidate-repository` |
| When the vendor firmware drop-in is present, each image contains the vendor firmware script, its service and the link that starts it | The initramfs carries the hook that loads Apple's vendor firmware | `guest/candidate-repository` |
| The protected boot files still match their hashes after the presets are built | mkinitcpio's post hooks leave the VM's boot files alone too | `guest/candidate-repository` |
| The log ends `Installed exact signed package candidate <tag>` | The release command can tell this candidate was installed | `guest/candidate-repository` |

With a pinned runtime, which is how releases run, the install is fed from the candidate's own signed runtime bundle:

| Check | What it proves | Script |
| --- | --- | --- |
| The installed descriptor still matches its recorded checksum, and its tag and signer are well formed | The runtime is taken from the candidate already verified | `guest/candidate-runtime` |
| The bundle manifest's SHA-256 matches the pinned checksum and its signature is by the candidate's signer | The manifest is the one the release pinned | `guest/candidate-runtime` |
| The manifest says `format=2` and `bundle=asahi-quattro`, names the expected source commit, and lists exactly six packages | The bundle is the complete runtime from the expected source | `guest/candidate-runtime` |
| Each of the six packages matches its manifest digest, carries the signer's signature, and reports the name and version the manifest gives | Every runtime package is the signed one | `guest/candidate-runtime` |
| `omarchy-dev` carries this repository's version | The runtime is the version being released | `guest/candidate-runtime` |
| The fresh installer inside the signed `omarchy-dev` is byte-identical to `bin/omarchy-install-asahi-fresh` in the checkout | The installer the VM runs is the installer that ships | `guest/candidate-runtime` |

Without a pinned runtime, the install checks the published channel instead:

| Check | What it proves | Script |
| --- | --- | --- |
| The channel pointer has the exact expected form (else the GitHub release listing is used), and the tag is `asahi-quattro-channel-N` | The run tests one published channel | `guest/install` |
| The release key's fingerprint matches, and the bootstrap installer, the release record and the channel installer all verify against it | Everything fetched is signed by the release key | `guest/install` |
| The published release record names this repository's version | The published release is the version being tested | `guest/install` |
| No device-tree check survives in the VM copy of the channel installer, and its `--verify-only` pass produces a verified directory | Only the hardware check was changed, and the channel's own verification passes | `guest/install` |

### Install

| Check | What it proves | Script |
| --- | --- | --- |
| The version is `X.Y.Z-mac.N`, a mirror is set and the package channel address points at `maralcbr/omarchy-pkgs` | The guest got the same inputs the host resolved | `guest/install` |
| No device-tree check ending in a failure survives in the VM copy of the candidate installer | The VM's only change to the installer is the hardware boundary | `guest/install` |
| While another process holds the install lock, the installer exits with an error, says `Another fresh installation is already running`, and leaves no checkpoint | Two installs can never run at once | `guest/install` |

### Interruption and resume

| Check | What it proves | Script |
| --- | --- | --- |
| The installer's whole process tree is killed at the moment it sets the password, within three attempts | The install is really cut off mid-way, after packages and the user exist | `guest/install` |
| The checkpoint then holds the release, the Asahi kernel and GRUB hashes, the owner token and the target user; the home has its owner marker; completion has not started; the stock `alarm` account is still an administrator | Recovery state is written before the risky steps, and the only other administrator is not removed too early | `guest/install` |
| With the user's home moved, the installer refuses with `The target user is not owned by this installation` | A resume never adopts a user it cannot prove it created | `guest/install` |
| The installer is killed a second time, inside the completion step, then run again (up to three times) until it exits cleanly with no checkpoint left, and that second kill really happened | An install killed while finishing still completes on the next run | `guest/install` |
| The checkpoint and the owner marker are gone, the user's temporary comment is cleared, and `alarm` is out of `wheel` and locked | A completed install leaves no recovery state and no second way in | `guest/install` |
| The resumed install never showed an `Install anyway?` prompt | Resuming needs no manual override | `guest/install` |
| `linux-asahi`, its headers and `m1n1` keep their versions, and the VM kernel and the Asahi kernel are byte-identical to before | The install did not replace the kernels | `guest/install` |
| The `grub.cfg` Omarchy generated boots `vmlinuz-linux-asahi` with `initramfs-linux-asahi.img` | Omarchy's boot configuration points at the Asahi kernel. It is kept for verification, and the VM's own configuration is put back for the reboot | `guest/install` |

### Reboot

| Check | What it proves | Script |
| --- | --- | --- |
| After `systemctl reboot`, SSH answers with a new boot ID within about four minutes | The installed system comes back up and accepts logins | `run` |

### Post-boot verification

All of these run in one script and print a single `ok` line when every one holds.

| Check | What it proves | Script |
| --- | --- | --- |
| The installed version, release sequence and release tag equal what was recorded before the install | The system is the release that was installed | `guest/verify` |
| The `omarchy` user exists; `alarm` is not in `wheel` and is locked | The owner account replaced the stock one | `guest/verify` |
| SDDM remembers `omarchy` and the Omarchy session, and its PAM file unlocks and starts GNOME Keyring | The login screen and keyring are set up for the owner | `guest/verify` |
| The user finalization marker exists | Per-user setup finished | `guest/verify` |
| `omarchy-dev`, `omarchy-settings-dev`, `linux-asahi`, `networkmanager`, `iwd` and `rtkit` are installed | The core packages are present | `guest/verify` |
| `[omarchy]` is configured with `SigLevel = Required DatabaseOptional`, points at the expected immutable release, and comes before every other repository | Omarchy packages come only from the signed, pinned set and take precedence | `guest/verify` |
| For a candidate run no promoted set is recorded; otherwise the recorded set is the stable set the host resolved | The installer kept the repository it was meant to keep | `guest/verify` |
| The release signing key is in pacman's keyring, and for a stable set the ARM repository subkey too | pacman can verify the packages it will be asked to update | `guest/verify` |
| For a candidate: the descriptor's checksum, channel, tag, count and inventory still match, its signing certificate is trusted, and every package is at its descriptor version | The installed system runs exactly the candidate's packages | `guest/verify` |
| NetworkManager, SDDM and systemd-resolved are enabled | Networking, name resolution and the login screen start at boot | `guest/verify` |
| The old seamless-login unit, its enablement link and its helper are gone | A retired login path cannot come back | `guest/verify` |
| NetworkManager uses iwd for Wi-Fi | The Wi-Fi backend Apple Silicon needs is configured | `guest/verify` |
| The system locale is UTF-8 | The locale was set | `guest/verify` |
| The `asahi-alarm` repository is configured | Asahi packages can be updated | `guest/verify` |
| The VM kernel, the Asahi kernel and `grub.cfg` exist, and the kept Omarchy `grub.cfg` boots the Asahi kernel and initramfs | The boot files survived the reboot | `guest/verify` |
| No swap is active and zswap is off | Swap is disabled as intended | `guest/verify` |
| The VM adapter audit log is not empty | The record of what the VM changed in the installers was kept | `guest/verify` |
| `pacman -Qkk omarchy-dev` reports no altered files | The hardware helper stubbed for the VM was restored, and the package's files are intact | `guest/verify` |
| The temporary package-build sudo rule and account are gone | The install cleaned up its build access | `guest/verify` |
| The VM's SSH firewall rule is present | The firewall came up with the test's rule, which rerun removes | `guest/verify` |
| `omarchy-migrate --pending` finds nothing | No migration is left to run on a fresh install | `guest/verify` |
| The updater candidate's `--check` exits 0 or 1 | The updater accepts the fresh install's release state instead of rejecting it | `guest/verify` |

### Rerun rejection

| Check | What it proves | Script |
| --- | --- | --- |
| Running the installer again exits with an error and says `User already exists outside this release installation: omarchy` | A completed install cannot be run over | `guest/rerun` |
| The installed package list and the release record are byte-identical before and after | The refused rerun changed nothing | `guest/rerun` |

### Optional packages

Only with `--optional-packages`, which the release command always passes.

| Check | What it proves | Script |
| --- | --- | --- |
| The dated snapshot is restored first | Optional packages come from the same snapshot | `guest/optional-packages` |
| Every transaction in `install/optional-packages-aarch64-required` exists in `install/optional-packages.tsv` | The required list and the recipes agree | `guest/optional-packages` |
| Each transaction installs, and every package in it is then registered with pacman; one `ok` line each, 23 today | Each optional package the menu offers on aarch64 really installs | `guest/optional-packages` |
| The summary reports 0 failed | No transaction failed | `guest/optional-packages` |

### Evidence export

| Check | What it proves | Script |
| --- | --- | --- |
| The container is confirmed gone before anything is copied; if not, no evidence is exported and the run fails | Evidence is never copied from a VM still writing to it | `run` |
| The logs and the desktop screenshot are hashed, copied, and the copy checked against the hashes before the directory loses its `.partial` suffix; a failed check fails the run and keeps the disk | An evidence directory always matches the run it came from | `run` |
| `run.txt` records passed or failed, the exit status, the identities the run used and each log's hash | The result can be matched to the candidate without the disk | `run` |

The screenshot is captured, not inspected.

### What the release command adds

`bin/asahi-release` in `omarchy-pkgs` runs the harness on a test Mac with a candidate, a pinned runtime and `--optional-packages`, then accepts the run only if:

- the harness exited 0 and exported its evidence;
- `run.txt` names this run, `status=passed`, exit status 0, the candidate's tag and checksum, the runtime manifest and source, and the harness's default mirror;
- all six logs exist and each matches its hash in `run.txt`;
- the candidate log shows the candidate was installed;
- no log has a `not ok` line, and verify and rerun each have an `ok` line;
- the optional `ok` count equals the number of required transactions, and the summary says 0 failed.

Its record sums this up as install, interruption recovery, reboot, verify and rerun rejection, plus optional packages.

### What VM acceptance cannot prove

The VM is not a Mac, so some things need hardware evidence instead:

- **The real kernel.** The VM boots a generic Arch Linux ARM kernel. The Asahi kernel is installed but never booted, and the candidate install holds `linux-asahi`, its headers, `m1n1` and `grub` back.
- **Boot packages.** m1n1, U-Boot, Limine and GRUB never run on Apple firmware. Omarchy's boot configuration is only read for the right kernel names, then set aside.
- **Displays.** The guest has one virtual GPU. A screenshot is saved but nothing checks it.
- **Audio.** The guest has no sound device.
- **Cold boot.** The only reboot is a warm restart of the VM.
- **Apple hardware in general.** The device tree is faked and the hardware helper stubbed, so Wi-Fi, Bluetooth, firmware loading, power and suspend are not exercised.

This is why the release command asks for a hardware evidence record whenever a kernel or boot package moves.

## Every check in an image run

`test/vm/mac-image/run` boots a built Mac image in a VM. It is run separately from the release command.

| Check | What it proves |
| --- | --- |
| The inputs are well formed, the host is aarch64 with readable KVM, the tools and passwordless sudo are present, the signing key exists, and evidence lies outside the state directory | The run can start safely |
| With `--release`: `IMAGE.sig` verifies with the repository key, and `IMAGE` names a lane | The image record is signed |
| With `--release`: `PROVENANCE` names this lane's payload, and the payload (reassembled from its parts if needed) has the recorded size and digest | The downloaded payload is the one built |
| With `--release`: every member `IMAGE` lists is an expected file, is present and matches its digest; at least four are listed, and `IMAGE` has an input digest | Every file that will be written to disk is the signed one |
| The ESP boot files, `boot.img` and `root.img` are present, and the two images carry the fixed UUIDs | The payload has the layout the boot chain expects |
| The snapshot lists a generic kernel, which is signed by an Arch Linux ARM key from the image's own keyring | The stand-in kernel is genuine |
| The image root holds exactly one kernel, and mkinitcpio builds an initramfs there that runs the `omarchy-mac-encrypt` and `asahi` hooks and contains the encryption units and the key-mount ordering drop-in | The image's own initramfs hooks work |
| Plain first boot: the serial log shows `encrypt=0` read, first boot finished and owner provisioning started, with no failure, each within 15 minutes by default | A first boot without encryption completes |
| After it: the root is still plain btrfs, the pending marker and last error are absent, `install.conf` is kept on the root and removed from the ESP, a per-Mac pacman key is recorded, provisioning is armed, and the boot partition records `phase=declined` | First boot left the right state behind |
| Encrypted first boot: the serial log shows the conversion start and finish, the root repointed to `/dev/mapper/root`, first boot finished and provisioning started, with no encryption, GRUB or initramfs failure | In-place LUKS2 conversion completes on first boot |
| After it: the root is LUKS, the boot partition records `phase=configured` with that LUKS UUID, the key file is 64 bytes and mode 600, and `grub.cfg` unlocks with it | The encrypted system is set up to boot |
| Second boot: the root unlocks and a login prompt appears, with no emergency mode, failed key mount or failed encryption unit | The encrypted system boots again |

The limits of the fresh-install run apply here too, plus one of its own: the second boot unlocks with the throwaway key file, not an owner passphrase.

## What is not tested

- **The installer's own tests are not in CI.** The engine's run when the engine is built, which is a real gate; the Swift tests are run by hand.
- **No test boots a Mac on an owner passphrase.** Enrolment and recovery have fixture tests with a stubbed `cryptsetup`, and the image harness unlocks with a throwaway key file, so the two halves are never joined.
- **No automated test touches Apple hardware.** Graphics, Wi-Fi, audio, suspend and power are a person with a checklist, on two machines.
- **The graphical suite never runs in CI**, so a desktop regression waits for someone to run it.
- **Some suites run in no workflow at all.** In the package repository, 13 of 43 test scripts, including the one covering the encryption path.
- **A green headless run can contain skips**, because the runtime probes pass when no compositor is present.
- **Unified kernel images are not inspected** by the fresh-install harness, which matters now that the current image boots through Limine.
