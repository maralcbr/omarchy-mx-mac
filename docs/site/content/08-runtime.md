---
title: What is on the disk
description: Packages, the Apple Silicon gate, hardware fixes, migrations and the file layout on an installed Mac.
section: How it is built
---

An installed Omarchy MX Mac is an upstream Omarchy installation plus one boot package and a set of gated hardware fixes. The file layout is upstream's, documented in [file-layout.md](https://github.com/maralcbr/omarchy-mx-mac/blob/main/docs/file-layout.md).

## Packages

| Package | Contents |
| --- | --- |
| `omarchy-settings` | `/etc/skel`, `/etc` drop-ins, boot loader and snapper configuration, Plymouth and SDDM themes, branding. Installed before the user exists. |
| `omarchy` | `/usr/bin/omarchy-*`, `/usr/share/omarchy/{install,migrations,themes,shell,config}` |
| `omarchy-mac-boot` | Vendor firmware hooks, mkinitcpio drop-ins, first-boot and encryption units, boot check inputs |
| `omarchy-keyring` | The pacman keys for `[omarchy]`, upstream's package unchanged |
| `linux-asahi` or `linux-aurora` | The kernel, headers and device trees for the lane |

Three layers populate `$HOME`, as upstream: `omarchy-settings` seeds `/etc/skel`, `omarchy-finalize-user` runs once per user for what skel cannot do, and `omarchy-reinstall-configs` resets a user to shipped defaults on request.

## The Apple Silicon gate

`omarchy-hw-apple-silicon` is a tiny script: on aarch64 it looks for `apple,` in `/proc/device-tree/compatible`. An image build has no device tree to read, so it sets `OMARCHY_MAC_TARGET=generic-apple-silicon` and the script reports the generic Apple Silicon configuration instead. About fifteen files in `bin/` and `install/` call it. Whatever is behind it never runs on x86 or on a non-Apple ARM machine, which is what lets the fork merge upstream without conflicts and lets upstream take fork changes without a Mac.

## Hardware fixes

`install/hardware/apple/` holds one script per fix. Each one starts by asking `omarchy-hw-apple-silicon` whether it is on the right machine, so the same directory also carries fixes for Intel Macs that never run here.

| Fix | What it does |
| --- | --- |
| `fix-asahi-hid-race` | Early-loads the Apple keyboard and trackpad drivers, so input works at the greeter and at the passphrase prompt |
| `fix-asahi-btrfs-race` | Orders static device nodes before the root mount in the initramfs |
| `fix-speaker-pop` | Suppresses the pop the speakers make on resume |
| `fix-brcmfmac-supplicant` | Settles the Broadcom Wi-Fi supplicant |
| `snapshots-subvolume` | Prepares the btrfs subvolume that snapper snapshots live in |
| `grub-console` | Console settings for the GRUB boot path |
| `limine-boot` | Installs the Limine boot path, behind its own gate |

An image build runs only the two that write initramfs drop-ins, because those must exist before mkinitcpio runs. The rest are recorded as deferred steps and run on the Mac's first boot.

Each fix that changes an installed system also ships as a migration, so existing Macs get it on the next `omarchy update`.

## Channel state on disk

| Path | Meaning |
| --- | --- |
| `/var/lib/omarchy/apple-silicon-channel` | The channel and kernel this Mac is on, plus any hold |
| `/var/lib/omarchy/apple-silicon-aurora-lane` | Which Aurora lane an Aurora Mac follows, and any lane change in flight |
| `/usr/share/omarchy/apple-silicon-kernel` | `linux-asahi` or `linux-aurora` |
| `/var/lib/omarchy/asahi-quattro-release` | The runtime release this Mac is on |
| `/var/lib/omarchy/mac-first-boot/` | First-boot markers, the configuration it consumed and any errors |
| `/boot/omarchy/encrypt.state` | The encryption phase and its recovery journal |
| `/var/lib/omarchy/snapshot-restore.enabled` | Lab gate for snapshot restores |
| `/var/lib/omarchy/limine.enabled` | Gate for the Limine boot path (next release) |

## Screenshots on an Apple keyboard

The fork adds the macOS number-row screenshot shortcuts with Control held, so Omarchy's own `Super+Shift+3/4/5` workspace bindings stay intact. On an Apple keyboard, Command is Hyprland's `SUPER`.

| Shortcut | Action |
| --- | --- |
| `Control+Shift+Command+3` | Capture the focused display |
| `Control+Shift+Command+4` | Select a region, or click a window |
| `Control+Shift+Command+5` | Screenshot and recording controls |

## Things not to do

- Do not replace the signed `quickshell-git` with `quickshell` from the AUR. It moves the Mac outside the validated bundle and can block later updates.
- Do not reboot during or after a failed package transaction. Keep the output and `/var/log/pacman.log`, and open an issue.
- Do not hand-edit the boot loader configuration. The boot check will refuse the next reboot.
