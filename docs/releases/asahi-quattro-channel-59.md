# Runtime channel 59 (Omarchy MX Mac 4.0.4-mac.1)

Published 2026-09-25 (Brisbane) for installed Macs. The release version stays
`4.0.4-mac.1`: this is an update within 4.0.4, not a new Omarchy release, so
there is no new tag. It moves the runtime from `omarchy-mx-mac` `16eaa2fb` to
[`b8ed3951`](https://github.com/maralcbr/omarchy-mx-mac/commit/b8ed395133a318cd58cbaf1c15de325f1195e0d7).

## Install

- **Existing Mac:** run `omarchy update`.
- **New Mac:** the installer still writes image `os-v4.0.4-mac.1.20260924-rc`
  (runtime channel 57). The first `omarchy update` after the install brings it
  to channel 59.

## What was published

| | |
| --- | --- |
| Runtime channel | [`asahi-quattro-channel-59`](https://github.com/maralcbr/omarchy-pkgs/releases/tag/asahi-quattro-channel-59), release `asahi-quattro-b8ed3951`; `pointers/asahi-quattro-channel` names 59 |
| Package channel | [`asahi-packages-channel-15`](https://github.com/maralcbr/omarchy-pkgs/releases/tag/asahi-packages-channel-15) |
| Promoted packages | [`asahi-packages-stable-7e2f6cfe…`](https://github.com/maralcbr/omarchy-pkgs/releases/tag/asahi-packages-stable-7e2f6cfec1b3e412ad4fd6ed9611be275a246b30), byte-identical to candidate `7e2f6cfe` (CANDIDATE SHA-256 `888d9a2375b19c8ed13a920bbdf6e81d281a38d141294f0fb1ca36faca05c90b`) |
| Runtime packages | `omarchy-dev` and `omarchy-settings-dev` `4.0.4.r7099.gb8ed395-1` (were `4.0.4.r7094.g16eaa2f-1`) |

The runtime pin is omarchy-pkgs #209 (merged as `7e2f6cfe`). The candidate was
a **full** rebuild, not incremental: omarchy-pkgs #208 changed the repository
definition (`pkgbuilds/asahi-source-outputs`), which the planner treats as a
rebuild-all input. Every package in the repository was rebuilt. New in the
repository:

- `ghostty`, `ghostty-shell-integration`, `ghostty-terminfo` and
  `ghostty-nautilus` 1.3.1-3, built from source for aarch64 (omarchy-pkgs #208).
- `openai-codex-desktop` 26.915.31945-1, the ChatGPT desktop app repacked
  from OpenAI's arm64 build (omarchy-pkgs #208).

Three boot packages were rebuilt at the versions installed Macs already have:

- `limine-mkinitcpio-hook` 1.36.0-4 and `uboot-asahi` 2026.07.asahi2-3 have
  different payloads under the same version. `pacman -Syu` does not reinstall
  a package whose version is unchanged, so installed Macs keep the copy they
  have.
- `omarchy-mac-boot` 20260921-10 has an unchanged recipe and payload.

## Changes

- **Ghostty and ChatGPT.** The Install menu offers Ghostty and ChatGPT on
  Apple Silicon now that `[omarchy]` carries `ghostty` and
  `openai-codex-desktop` (omarchy-pkgs #208, refs #125). No runtime change was
  needed: the menu rows appear once the packages are in the repository.
- **Legacy repository.** Macs that came from the omarchy-mac project lose its
  unsigned `[omarchy-aarch64]` repository. `omarchy update` (and migration
  `1790256699`) removes the section from `/etc/pacman.conf`, keeping a backup,
  and replaces `obsidian-appimage` and `hyprland-preview-share-picker-git` with
  the `[omarchy]` packages. The runtime bundle may downgrade a bundle package
  only when that repository's sync database proves it built it. A cleanup that
  cannot finish is retried on the next update. A Mac with neither the
  repository nor those two packages is unaffected (#260, refs #238).
- **Manual.** The testing page lists every VM acceptance check, and the VM
  harness now fails a run when a resumed install asks "Install anyway?"
  (#258).

### Not in this runtime

- **Installer error details.** The installer explains why the install engine
  refused a plan, says when no disk changes were made, and names a Mac the
  release does not support along with the families it does (#259). This is
  installer-app code: it reaches users only with a new signed installer build.
  Installer 2.0.9, the current download, does not have it.
- **Headset buttons.** The edge kernel lane carries a patch that maps 3.5mm
  headset buttons to media keys on M1 Macs with the CS42L83 codec
  (omarchy-pkgs #207, refs #226). It is not built or published yet, and it
  does not reach rc or stable until a hardware-qualified pin takes it.

Full list: `git log 16eaa2fb..b8ed3951`.

## Validation

The M1 Pro was offline, so VM acceptance and hardware testing used only the
M2 Max.

- **VM acceptance** of candidate `7e2f6cfe` on the M2 Max. The first run,
  `candidate-7e2f6cfe-20260924T151215Z-1`, failed on a corrupted GitHub
  download of `ufw-docker`; the published asset matched its database entry.
  The second run, `candidate-7e2f6cfe-20260924T151433Z-2`, was accepted:
  install, interruption recovery, reboot, verify and rerun rejection, 23
  optional packages, 25 ok lines. Record:
  [`asahi-packages-candidate-7e2f6cfe-acceptance.txt`](asahi-packages-candidate-7e2f6cfe-acceptance.txt).
- **Hardware** (boot packages rebuilt with new payloads): the M2 Max with a
  LUKS2 root and Limine reinstalled `limine-mkinitcpio-hook` and `uboot-asahi`
  from the candidate. `update-m1n1` rewrote the ESP's `m1n1/boot.bin`, whose
  U-Boot matches the package's byte for byte. The runtime pair, Ghostty (which
  runs) and ChatGPT installed from the candidate; migration `1790256699` ran
  clean and the boot check passed. After the owner's cold boot, U-Boot handed
  over to Limine, the passphrase was accepted and the desktop came up; the boot
  check passed, no system or user units failed, `speakersafetyd` was active and
  the J416 speaker sink was the default. Record:
  [`asahi-packages-candidate-7e2f6cfe-hardware-evidence.txt`](asahi-packages-candidate-7e2f6cfe-hardware-evidence.txt).

## Known limitations

- **#235 (Danish layout lockout)** and **#238 (legacy 4.0.2 → 4.0.4
  migration)** remain open.
- **#173 (J293 audio) and #86 (dock keyboard at the disk prompt)** still need
  their reporters to confirm on their Macs.
- **No physical fresh install** of the current image,
  `os-v4.0.4-mac.1.20260924-rc`, is recorded yet.

**Full diff**: https://github.com/maralcbr/omarchy-mx-mac/compare/16eaa2fb...b8ed3951
