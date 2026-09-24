# Runtime channel 58 (Omarchy MX Mac 4.0.4-mac.1)

Published 2026-09-24 (Brisbane) for installed Macs. The release version stays
`4.0.4-mac.1`: this is an update within 4.0.4, not a new Omarchy release, so
there is no new tag. It moves the runtime from `omarchy-mx-mac` `ca187b0a` to
[`16eaa2fb`](https://github.com/maralcbr/omarchy-mx-mac/commit/16eaa2fb5c00bd3926582302a07c792344fd5c7e).

## Install

- **Existing Mac:** run `omarchy update`.
- **New Mac:** the installer still writes image `os-v4.0.4-mac.1.20260924-rc`
  (runtime channel 57). The first `omarchy update` after the install brings it
  to channel 58.

## What was published

| | |
| --- | --- |
| Runtime channel | [`asahi-quattro-channel-58`](https://github.com/maralcbr/omarchy-pkgs/releases/tag/asahi-quattro-channel-58), release `asahi-quattro-16eaa2fb`; `pointers/asahi-quattro-channel` names 58 |
| Package channel | [`asahi-packages-channel-14`](https://github.com/maralcbr/omarchy-pkgs/releases/tag/asahi-packages-channel-14) |
| Promoted packages | [`asahi-packages-stable-a7b2a50a…`](https://github.com/maralcbr/omarchy-pkgs/releases/tag/asahi-packages-stable-a7b2a50aa42ccbf1a4dc4aa678e8ea9e44698ba1), byte-identical to candidate `a7b2a50a` (CANDIDATE SHA-256 `ce9a7f59b1fd0b6130578dcec7d8d66619a658957cc57bab2b2f110498fba006`) |
| Runtime packages | `omarchy-dev` and `omarchy-settings-dev` `4.0.4.r7094.g16eaa2f-1` (were `4.0.4.r7081.gca187b0-1`) |

The candidate was incremental. It rebuilt only the two runtime packages and
reused the rest, including four packages first built in the unpromoted
candidate `a27bf81f`:

- `limine-mkinitcpio-hook` 1.36.0-3 → 1.36.0-4 (omarchy-pkgs #203):
  mkinitcpio keeps `/boot`, and Limine stays quiet until it is active.
- `omarchy-mac-boot` 20260921-9 → 20260921-10 (omarchy-pkgs #202): the disk
  prompt's image carries the keyboard layout (`sd-vconsole`) and the
  Thunderbolt modules for dock keyboards.
- `qemu-user-static` and `qemu-user-static-binfmt` 10.0.11-1 → 10.0.11-2
  (omarchy-pkgs #204): 32-bit ARM binfmt rules.

The rebuilt `omarchy-settings-dev` also gives Apple Silicon the Omarchy bash
skeleton (omarchy-pkgs #201).

## Changes

- **Audio.** The `software-dsp.lua` WirePlumber overlay is no longer shipped,
  and copies Omarchy installed are removed when unmodified. On a 13" MacBook
  Pro (J293) it left WirePlumber spinning with no sound (#242, refs #173).
- **Shell.** A stock Arch `~/.bashrc` is replaced with Omarchy's, keeping a
  backup; any other `~/.bashrc` is left alone (#243, refs #124).
- **Screenshots.** The notification offers Edit only when the editor is
  installed, and Macs missing Tensaku get it (#244, refs #81).
- **Dictation.** Setting up dictation on a Mac installs the prebuilt
  `voxtype-bin` when the repositories carry it, instead of a 10-20 minute AUR
  build; a Voxtype already built from source is kept (#245, refs #114).
- **Fresh install.** A resume that cannot continue names each field that
  differs and says how to resume (#246, refs #85).
- **Boot check.** On an encrypted Mac (crypttab entry `root`) with a non-US
  Latin layout in `/etc/vconsole.conf`, the boot check verifies that the image
  the Mac boots carries that keyboard layout. A Limine Mac without `objcopy`
  skips this check with a note (#247, refs #235).
- **GRUB with busybox `encrypt`.** Macs installed before Omarchy's images keep
  `cryptdevice=` and a single `rootflags=`; a migration repairs Macs that lost
  them (#248, refs #238).
- **Limine migration.** Allows the reboot a new kernel still needs and says to
  reboot, activates Limine with the ESP at `/boot` as well as `/boot/efi`,
  drops `rootflags=subvol=@` on an ext4 root, and never picks the Aurora kernel
  on an M3 (#250, refs #235, #238, #151).
- **Manual.** Served at <https://omarchy-mx-mac.org/> (#252), with a package
  map regenerated from live data (#249); the install pages name the 22 M1 and
  M2 models (#240).
- **Tests.** Limine test stubs (#253) and the VM harness device-tree guard
  (#255).

Full list: `git log ca187b0a..16eaa2fb`.

## Validation

- **VM acceptance** of candidate `a7b2a50a` on the M2 Max (the M1 Pro was
  offline): run `candidate-a7b2a50a-20260924T102146Z-1`, install, interruption
  recovery, reboot, verify and rerun rejection, 23 optional packages, 25 ok
  lines. Record:
  [`asahi-packages-candidate-a7b2a50a-acceptance.txt`](asahi-packages-candidate-a7b2a50a-acceptance.txt).
- **Hardware** (boot packages changed): the M2 Max with a LUKS2 root and
  Limine installed the candidate's packages; the migrations ran clean and the
  boot check passed. After the owner's cold boot the passphrase was accepted,
  the desktop came up, the boot check passed, no system or user units failed,
  `speakersafetyd` was active and the J416 speaker sink was present and the
  default. Record:
  [`asahi-packages-candidate-a7b2a50a-hardware-evidence.txt`](asahi-packages-candidate-a7b2a50a-hardware-evidence.txt).

## Known limitations

- **#235 (Danish layout lockout) is not proven fixed.** The Mac's image carries
  the Danish layout, but the cold-boot passphrase did not tell the layouts
  apart. A follow-up test is in progress.
- **#173 (J293 audio) and #86 (dock keyboard at the disk prompt)** need their
  reporters to confirm on their Macs.
- **No physical fresh install** of the current image,
  `os-v4.0.4-mac.1.20260924-rc`, is recorded yet.

**Full diff**: https://github.com/maralcbr/omarchy-mx-mac/compare/ca187b0a...16eaa2fb
