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

Run the way the release tooling runs it, with the optional-package checks enabled, a pass prints 25 `ok` lines in about 15 minutes. Read that carefully: 23 of the 25 are optional-package transactions, and the whole verification stage collapses into one line. Those checks are off by default. Almost every other check is silent when it passes and stops the run when it fails, so the full list is in [every check in a fresh-install run](#every-check-in-a-fresh-install-run) rather than in the log.

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

The harness is `test/vm/asahi-fresh/`: `run` on the host, the scripts in `container/` that build and start the VM, and the scripts in `guest/` that run inside it. Each row below is a check that ends the run as a failure when it does not hold, unless the row says otherwise. Steps that can only fail by not working (a download, a copy, a package transaction in the base image) are left out. The tables follow the order a run takes.

A few words used below: the **lease** is a lock that lets only one run use the host at a time; a **checkpoint** is the state the installer writes so an interrupted install can resume; a **preset** is the recipe mkinitcpio uses to build an initramfs, the small system that starts the boot.

### Setup and base image

| Check | What it shows | Script |
| --- | --- | --- |
| Options are known; the run ID, CPU and memory counts, evidence path, mirror address and channel addresses are well formed; `flock` is installed | The run starts from inputs it can use, before anything is created | `run` |
| The evidence directory is not inside the VM state directory | Deleting a finished run's disk can never delete its evidence | `run` |
| A candidate is named in full: 40-character commit tag, 64-character descriptor checksum, 40-character signing fingerprint, a package count and a readable key; a pinned runtime also needs its manifest checksum and source commit | The run tests one exact candidate, not "the latest" | `run` |
| The host lock is not a symlink, opens for writing, is a regular file owned by this user, is taken (or waited for with `--wait-for-lease`) and still names the same file afterwards; the state directory is owned by this user and its lease is free | Two runs never share the Docker daemon, ports, KVM or state directory | `run` |
| The run ID has no run directory, evidence directory or half-exported evidence yet, no container has its name, and no running container already forwards the SSH or VNC port | A run never reuses or overwrites another run's files or VM | `run` |
| The package channel resolves to an `asahi-packages-channel-N` tag, and that channel names exactly one `asahi-packages-stable-<commit>` set | The package set verification expects is fixed before the install, so it is never learned from the system being checked | `run` |
| The Arch Linux ARM root file system's signature verifies with the Arch Linux ARM build key, whose fingerprint must match | The VM starts from genuine upstream Arch Linux ARM | `container/build-base` |
| The Asahi keyring package matches a pinned SHA-256 | The Asahi repository is trusted through a known key | `container/build-base` |
| The loop device's partitions appear within two seconds; the base holds exactly one generic kernel before the Asahi kernel is added, and its loop device is released before the disk is converted | The generic kernel the VM boots is unambiguous, and the disk is not converted while still attached | `container/build-base` |
| The run directory lies under `/work` and the CPU count is a positive integer | The VM's disk and logs land where the run expects them | `container/start-vm` |
| The guest answers SSH within 120 attempts two seconds apart (a few minutes) | The base VM boots; if not, the serial log is shown | `run` |
| After the mirror is rewritten, no `archlinuxarm.org` server line other than the dated snapshot is left in `pacman.conf` or the mirror list | The Arch Linux ARM mirror configuration points only at the snapshot. Checked on the fresh VM, before the target-replacement run and each resume attempt, and before the optional packages | `guest/alarm-snapshot` |

The base image is built once and cached. Its checks run only when it is rebuilt, which happens when the build script, the SSH key, the root file system address or the mirror changes, or with `--rebuild-base`.

### Candidate repository and signatures

Release runs always name a candidate. Without one, the install uses the published channel instead (last table in this group).

| Check | What it shows | Script |
| --- | --- | --- |
| The candidate's inputs are well formed and its key file is readable | The guest checks the same exact candidate the host was given | `guest/candidate-repository` |
| The downloaded `CANDIDATE` descriptor's SHA-256 matches the checksum given | This is the exact descriptor the release built | `guest/candidate-repository` |
| The descriptor contains `format=1`, `channel=candidate`, this tag, its commit, the signing fingerprint and the package count, with that many `package=` lines | The descriptor names this candidate | `guest/candidate-repository` |
| `CANDIDATE.sig` verifies, signed by exactly the expected fingerprint, and the key's primary fingerprint is well formed; pacman then trusts that key | The descriptor was signed by the Apple Silicon repository key | `guest/candidate-repository` |
| Every package line has a valid name and a version; the names are unique and their number matches the count | The package list is unambiguous | `guest/candidate-repository` |
| All the candidate's packages install in one transaction, with `[omarchy]` first, signatures required and the server set to the candidate release | The candidate's packages install together | `guest/candidate-repository` |
| `linux-asahi`, its headers, `m1n1` and `grub` keep their versions, and the VM kernel, its initramfs, the Asahi kernel and `grub.cfg` keep their hashes | Installing the candidate leaves the VM's own boot files alone. These four packages are held back | `guest/candidate-repository` |
| Each installed package's version equals the descriptor's | pacman ended up at the candidate's versions | `guest/candidate-repository` |
| At least one preset exists; each one builds when mkinitcpio is run directly, can be read, names at least one image, and writes each one non-empty | The candidate's initramfs hooks work. pacman alone would hide a failed hook | `guest/candidate-repository` |
| Only when the vendor firmware drop-in is present: each image contains the vendor firmware script, its service and the link that starts it | The initramfs carries the hook that loads Apple's vendor firmware. The 2026-09-24 release run had no drop-in, so this check did not run | `guest/candidate-repository` |
| The protected boot files still match their hashes after the presets are built | mkinitcpio's post hooks leave the VM's boot files alone too | `guest/candidate-repository` |

The script ends by printing `Installed exact signed package candidate <tag>`. The harness does not check that line; the release command does.

With a pinned runtime, which is how releases run, the install is fed from the candidate's own signed runtime bundle:

| Check | What it shows | Script |
| --- | --- | --- |
| The runtime checksum and source commit are well formed; the installed descriptor still matches its recorded checksum; its tag and signer are well formed | The runtime is taken from the candidate already verified | `guest/candidate-runtime` |
| The bundle manifest's SHA-256 matches the pinned checksum and its signature is by the candidate's signer | The manifest is the one the release pinned | `guest/candidate-runtime` |
| The manifest contains `format=2`, `bundle=asahi-quattro`, the expected source commit and `package_count=6`, with six package lines | The bundle comes from the expected source. The six names are not checked against a fixed list | `guest/candidate-runtime` |
| Each package line is well formed; each package file matches its manifest digest, carries the signer's signature, and reports the name and version the manifest gives | Every runtime package is the signed one | `guest/candidate-runtime` |
| `omarchy-dev` carries this repository's version | The runtime is the version being released | `guest/candidate-runtime` |
| The fresh installer inside the signed `omarchy-dev` is byte-identical to `bin/omarchy-install-asahi-fresh` in the checkout | The installer under test is the one that ships. The VM then runs a copy with the device-tree checks patched out | `guest/candidate-runtime` |

Without a pinned runtime, the install checks the published channel instead:

| Check | What it shows | Script |
| --- | --- | --- |
| The channel pointer has the exact expected form (else the GitHub release listing is used), and the tag is `asahi-quattro-channel-N` | The run tests one published channel | `guest/install` |
| The release key's fingerprint matches, and the bootstrap installer, the release record and the channel installer each verify against it | The three files the install runs from are signed by the release key | `guest/install` |
| The published release record names this repository's version | The published release is the version being tested | `guest/install` |
| No device-tree check survives in the VM copy of the channel installer, and its `--verify-only` pass produces a verified directory | The hardware check is out, and the channel's own verification passes. The VM copy also keeps its working files instead of deleting them | `guest/install` |

### Install

| Check | What it shows | Script |
| --- | --- | --- |
| The version is `X.Y.Z-mac.N`, a mirror is set and the package channel address is an `asahi-packages-channel-N` asset of `maralcbr/omarchy-pkgs` | The guest got the same inputs the host resolved | `guest/install` |
| No device-tree check ending in a failure survives in the VM copy of the candidate installer | The hardware check is out of the copy the VM runs | `guest/install` |
| While another process holds the install lock, the installer exits with an error, says `Another fresh installation is already running`, and leaves no checkpoint | Two installs cannot run at once | `guest/install` |
| `ufw` installs and allows SSH | The test can still reach the VM once the installer turns on the firewall | `guest/install` |

### Interruption and resume

| Check | What it shows | Script |
| --- | --- | --- |
| Within three attempts, the installer reaches the point where it sets the password, and the harness kills its process tree there | The install is cut off mid-way, after packages and the user exist | `guest/install` |
| The checkpoint then has its release, Asahi kernel hash, GRUB hash, owner token and target user files; the home has its owner marker; completion has not started; the stock `alarm` account is still in `wheel` | Recovery state exists before the risky steps, and the stock administrator is not removed too early | `guest/install` |
| With the account's home directory changed to another path, the installer refuses with `The target user is not owned by this installation` | A resume does not adopt a user whose home does not match | `guest/install` |
| Before the target-replacement run and each resume attempt, the dated snapshot is restored; for a candidate run, the candidate tag and key fingerprint are well formed, the candidate repository is restored, its key trusted again and the databases sync | Every resume of a candidate run installs from the candidate | `guest/install` |
| The installer is killed a second time, inside the completion step, then run again, up to three attempts in all, until it exits cleanly with no checkpoint left; the second kill must have happened | An install killed while finishing completes on a later run | `guest/install` |
| The checkpoint and the owner marker are gone, the account's temporary comment is cleared, and `alarm` is out of `wheel` and locked | A completed install leaves no recovery state, and the stock account cannot log in | `guest/install` |
| The resumed install's log has no `Install anyway?` prompt | Resuming needs no manual override | `guest/install` |
| `linux-asahi`, its headers and `m1n1` keep their versions, and the VM kernel and the Asahi kernel are byte-identical to before | The install did not replace the kernels | `guest/install` |
| The `grub.cfg` Omarchy generated boots `vmlinuz-linux-asahi` with `initramfs-linux-asahi.img` | Omarchy's boot configuration names the Asahi kernel. It is kept for verification, and the VM's own configuration is put back for the reboot | `guest/install` |
| The SSH firewall rule is added, or is already there | The VM stays reachable after the reboot | `guest/install` |

### Reboot

| Check | What it shows | Script |
| --- | --- | --- |
| After `systemctl reboot`, SSH answers with a new boot ID within 120 attempts two seconds apart | The installed system comes back up and accepts logins | `run` |

### Post-boot verification

All of these run in one script and print a single `ok` line when every one holds.

| Check | What it shows | Script |
| --- | --- | --- |
| The installed version, release sequence and release tag equal what was recorded before the install | The system is the release that was installed | `guest/verify` |
| The `omarchy` user exists; `alarm` is not in `wheel` and is locked | The owner account replaced the stock one | `guest/verify` |
| SDDM remembers `omarchy` and the Omarchy session, and its PAM file has GNOME Keyring's unlock and auto-start lines | The login screen and keyring are configured for the owner | `guest/verify` |
| The user finalization marker exists | Per-user setup reached its end | `guest/verify` |
| `omarchy-dev`, `omarchy-settings-dev`, `linux-asahi`, `networkmanager`, `iwd` and `rtkit` are installed | The core packages are present | `guest/verify` |
| `pacman.conf` has an `[omarchy]` section, a `SigLevel = Required DatabaseOptional` line and a server line for the expected immutable release, and `omarchy` is the first repository | The expected server and signature policy lines are present and `omarchy` comes first. The lines are not tied to the `[omarchy]` section itself | `guest/verify` |
| For a candidate run no promoted set is recorded; otherwise the recorded set is the stable set the host resolved | The installer kept the repository it was meant to keep | `guest/verify` |
| The release signing key is in pacman's keyring, and for a stable set the ARM repository subkey too | pacman has the keys for the packages it will be asked to update | `guest/verify` |
| For a candidate: the descriptor's checksum, channel, tag, count and inventory still match, its signing key is in pacman's keyring, and every package is at its descriptor version | The installed system still has the candidate's package versions after the reboot | `guest/verify` |
| NetworkManager, SDDM and systemd-resolved are enabled | They are set to start at boot. Whether they started is not checked | `guest/verify` |
| The old seamless-login unit, its enablement link and its helper are gone | A retired login path is not left behind | `guest/verify` |
| NetworkManager uses iwd for Wi-Fi | The Wi-Fi backend Apple Silicon needs is configured | `guest/verify` |
| The system locale is UTF-8 | The locale was set | `guest/verify` |
| `asahi-alarm` is in the repository list | The Asahi repository is configured | `guest/verify` |
| The VM kernel, the Asahi kernel and `grub.cfg` exist, and the kept Omarchy `grub.cfg` boots the Asahi kernel and initramfs | The boot files survived the reboot | `guest/verify` |
| No swap is active and zswap is off | Swap is disabled as intended | `guest/verify` |
| The VM adapter audit log is not empty | The record of which installer copies the VM ran was kept | `guest/verify` |
| `pacman -Qkk omarchy-dev` reports no altered files | The hardware helper stubbed for the VM was restored, and the package's files are intact | `guest/verify` |
| The temporary package-build sudo rule and account are gone | The install cleaned up its build access | `guest/verify` |
| The VM's SSH firewall rule is listed | The firewall kept the test's rule, which rerun removes | `guest/verify` |
| `omarchy-migrate --pending`, run as the owner, reports nothing pending and prints nothing | No migration is left to run on a fresh install | `guest/verify` |
| The updater candidate's `--check` exits 0 or 1 | The updater accepts the fresh install's release state instead of rejecting it | `guest/verify` |

### Optional packages

Only with `--optional-packages`, which the release command always passes.

| Check | What it shows | Script |
| --- | --- | --- |
| The dated snapshot is restored first | The Arch Linux ARM mirror configuration points only at the snapshot; `[omarchy]` and `asahi-alarm` stay as installed | `guest/optional-packages` |
| Every transaction in `install/optional-packages-aarch64-required` exists in `install/optional-packages.tsv` | The required list and the recipes agree | `guest/optional-packages` |
| Each transaction's packages install with pacman, and each is then registered; one `ok` line each, 23 today | Each required aarch64 optional package installs. The menu's own installers are not run | `guest/optional-packages` |
| The summary reports 0 failed | No transaction failed | `guest/optional-packages` |

### Rerun rejection

| Check | What it shows | Script |
| --- | --- | --- |
| Running the installer again exits with an error and says `User already exists outside this release installation: omarchy` | A completed install cannot be run over | `guest/rerun` |
| The installed package list and the release record are byte-identical before and after | The refused rerun did not change packages or the release record | `guest/rerun` |
| The test's SSH firewall rule is deleted | The test leaves no firewall hole behind | `guest/rerun` |

### Evidence export

| Check | What it shows | Script |
| --- | --- | --- |
| The container is removed and confirmed gone before anything is copied; if not, no evidence is exported and the run fails. A `--keep` run asks the VM to pause instead, without checking that it did | Evidence is not copied from a removed VM still writing to it | `run` |
| The logs and the desktop screenshot that exist are hashed, copied, and the copies checked against the hashes before the directory loses its `.partial` suffix; a failed check fails the run and keeps the disk | An exported evidence directory matches the run it came from. A missing log is not caught here | `run` |
| `run.txt` records passed or failed, the exit status, the identities the run used and each log's hash | The result can be matched to the candidate without the disk | `run` |

A cancelled run exits with status 130 or 143 and tries to export what it has, under the same conditions. The screenshot is captured, not inspected.

### What the release command adds

`bin/asahi-release` in `omarchy-pkgs` needs its SSH user and VM host settings, refuses a harness that predates the lease or has no default mirror, runs the harness on a test Mac with a candidate, a pinned runtime and `--optional-packages`, then accepts the run only if:

- the harness exited 0 and exported its evidence;
- `run.txt` is not empty and contains `format=1`, this run's ID, `status=passed`, exit status 0, the candidate's tag and checksum, the runtime manifest and source, and the harness's default mirror;
- the six logs (candidate repository, install, serial, verify, optional packages, rerun) exist, are not empty and each matches its hash in `run.txt`;
- the candidate log contains `Installed exact signed package candidate <tag>`;
- none of those logs except the serial log has a line starting `not ok`, and verify and rerun each have an `ok` line;
- the optional `ok` count equals the number of required transactions, and the summary says 0 failed.

A matching acceptance record already committed for the same candidate is accepted instead of a new run. The record sums a run up as install, interruption recovery, reboot, verify and rerun rejection, plus optional packages.

### What VM acceptance cannot prove

The VM is not a Mac, so some things need hardware evidence instead:

- **The real kernel.** The VM boots a generic Arch Linux ARM kernel. The Asahi kernel is installed but never booted, and the candidate install holds `linux-asahi`, its headers, `m1n1` and `grub` back.
- **Boot packages.** m1n1, U-Boot, Limine and GRUB never run on Apple firmware. Omarchy's boot configuration is only read for the right kernel names, then set aside.
- **Displays.** The guest has one virtual GPU. A screenshot is saved but nothing checks it.
- **Audio.** The guest has no sound device.
- **Cold boot.** The only reboot is a warm restart of the VM.
- **Apple hardware in general.** The device tree is faked and the hardware helper stubbed, so Wi-Fi, Bluetooth, firmware loading, power and suspend are not exercised.
- **A clean session.** A passing run can still log errors during user setup; the run checks the listed results, not that the logs are free of errors.

This is why the release command asks for a hardware evidence record whenever a kernel or boot package moves.

## Every check in an image run

`test/vm/mac-image/run` boots a built Mac image in a VM. It is run separately from the release command. Every wait below fails if the guest exits or the step takes longer than 15 minutes (the default).

| Check | What it shows |
| --- | --- |
| Options are known; the inputs are well formed; the host is aarch64 with readable KVM; the tools and passwordless sudo are present; the signing key exists; evidence lies outside the state directory | The run can start safely |
| With `--release`: `IMAGE.sig` verifies with the repository key, and `IMAGE` names a lane | The image record is signed |
| With `--release`: `PROVENANCE` names this lane's payload, and the payload (reassembled from at least two parts if needed) has the recorded size and digest | The payload is the one the unsigned provenance record names; the signed member digests below are what bind it |
| With `--release`: every member `IMAGE` lists is an expected file, is present and matches its digest; at least four are listed, and `IMAGE` has an input digest | Every member the signed record lists is intact. Files it does not list are not checked |
| Without `--release`: the payload file exists, and its lane is given or can be read from its name | The run knows which image it is booting |
| The ESP boot files, `boot.img` and `root.img` are present, and the two images carry the fixed UUIDs | The payload has the layout the boot chain expects |
| The snapshot lists a generic kernel, which is signed by an Arch Linux ARM key from the image's own keyring | The stand-in kernel is genuine |
| The image root's module listing is one line; the generic kernel yields a version; mkinitcpio builds an initramfs there that runs the `omarchy-mac-encrypt` and `asahi` hooks; the result has at least three `omarchy-mac-encrypt` entries and the key-mount ordering drop-in | The image's own initramfs hooks build |
| Plain first boot: the serial log shows `encrypt=0` read, first boot finished and owner provisioning started, and no `Failed to start Omarchy first boot`; the guest then stays up for 40 seconds | A first boot without encryption completes |
| After it: the root is still btrfs, the pending marker and last error are absent, `install.conf` is kept on the root and removed from the ESP, a per-Mac pacman key is recorded, provisioning is armed, and the boot partition records `phase=declined` | First boot left the right state behind |
| Encrypted first boot: the serial log shows the conversion start and finish, the root repointed to `/dev/mapper/root`, first boot finished and provisioning started, and none of three named encryption, GRUB or initramfs failure messages; the guest then stays up for 40 seconds | In-place encryption completes on first boot |
| After it: the root is LUKS, the boot partition records `phase=configured` with that LUKS UUID, the key file is 64 bytes and mode 600, `grub.cfg` unlocks with it, and the log reports the conversion time | The encrypted system is set up to boot |
| Second boot: the root unlocks and a login prompt appears, with no emergency mode, failed key mount or failed encryption unit | The encrypted system boots again |

Its limits differ from the fresh-install run's. It boots the generic kernel directly, with no display at all, and starts a new VM for each boot, so the Aurora kernel, the boot loaders, displays, audio and Apple hardware are all out of reach. The second boot unlocks with the throwaway key file, not an owner passphrase.

## What is not tested

- **The installer's own tests are not in CI.** The engine's run when the engine is built, which is a real gate; the Swift tests are run by hand.
- **No test boots a Mac on an owner passphrase.** Enrolment and recovery have fixture tests with a stubbed `cryptsetup`, and the image harness unlocks with a throwaway key file, so the two halves are never joined.
- **No automated test touches Apple hardware.** Graphics, Wi-Fi, audio, suspend and power are a person with a checklist, on two machines.
- **The graphical suite never runs in CI**, so a desktop regression waits for someone to run it.
- **Some suites run in no workflow at all.** In the package repository, 13 of 43 test scripts, including the one covering the encryption path.
- **A green headless run can contain skips**, because the runtime probes pass when no compositor is present.
- **Unified kernel images are not inspected** by the fresh-install harness, which matters now that the current image boots through Limine.
