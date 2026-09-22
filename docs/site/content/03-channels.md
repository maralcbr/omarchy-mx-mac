---
title: Channels and updates
description: What stable, rc and edge mean, which kernel each carries, and how updates reach an installed Mac.
section: Using it
---

Omarchy MX Mac uses the upstream channel names. A channel decides two things: which signed OS image a new install gets, and which kernel lane and package pointers an installed Mac follows.

| Channel | Kernel | Who it is for | Shown in the installer |
| --- | --- | --- | --- |
| `stable` | `linux-asahi` from `[asahi-alarm]` | Daily drivers on one display | yes |
| `rc` | `linux-aurora`, pinned to a hardware-qualified commit | Users who need external displays, USB4 and newer hardware support | yes |
| `edge` | `linux-aurora`, floating on the `aurora-wip` branch head | Lab Macs and kernel testing | no, updater only |

The Aurora kernel comes from [aurora-silicon/linux](https://github.com/aurora-silicon/linux). It adds DisplayPort alt-mode and USB4 external monitors, variable refresh rate, the camera ISP and the always-on processor. Fixes the fork needs are sent upstream to `aurora-wip` rather than carried as patches.

The plan is to promote the Aurora lane into `stable` once it has been through enough hardware time, and retire the Asahi lane after that.

## Picking a channel

New installs pick the channel in the installer app's **Release Channel** menu. The default is `stable`. From a terminal:

```bash
defaults write com.omarchy.mx.installer ReleaseChannel rc
```

An installed Mac records its lane in `/var/lib/omarchy/apple-silicon-channel` and the kernel marker `/usr/share/omarchy/apple-silicon-kernel`. Moving between lanes is an explicit, signed downgrade or upgrade of the kernel package:

```bash
omarchy-channel-set rc
omarchy update
```

## How an update arrives

`omarchy update` works as on x86, with two Apple-specific steps in front of it:

1. **Runtime bundle.** `omarchy-update-asahi-bundle` reads the runtime channel pointer, verifies the release descriptor, the six-package manifest, checksums and signatures, then installs `omarchy-keyring`, `omarchy-settings-dev`, `omarchy-dev`, `omarchy-nvim`, `quickshell-git` and `ttf-jetbrains-mono-nerd-basic` as one transaction.
2. **Package repository.** `omarchy-update-asahi-repository` repoints `[omarchy]` at the current promoted package channel. Rollbacks of the package or release sequence are refused.
3. **Everything else** comes live from the Arch Linux ARM and Asahi mirrors, exactly as upstream.

A snapshot is taken before the package sync. `snapper list` shows it, and `omarchy-snapshot restore <number>` reboots into a writable clone of that snapshot when the lab gate `/var/lib/omarchy/snapshot-restore.enabled` is present.

When a new kernel is installed the updater rebuilds the initramfs, refreshes m1n1 and the device trees, runs the boot check and offers a reboot.

## What is signed, and by what

| Artefact | Key |
| --- | --- |
| Packages in `[omarchy]` | ARM repository signing subkey of the omarchy-pkgs release key |
| Runtime bundle and release descriptors | Omarchy MX Mac release key (`5983B1CA…5959`) |
| Channel catalogs read by the installer | One Ed25519 key that never leaves the owner's Keychain |
| Installer app and `.pkg` | Apple Developer ID `T2C384FJBD`, notarized |

Only four keys on the download host are ever rewritten: each channel's `catalog.signed.json` and `channel.json`, and each channel's installer `.pkg` and `installer.json`. Everything under `releases/` is immutable and protected by a bucket lock.
