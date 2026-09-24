---
title: Channels and updates
description: What stable and rc deliver, which kernel each carries, and how updates reach an installed Mac.
section: Using it
---

A channel decides two things: which signed image a new install writes, and which kernel an installed Mac follows. Macs are offered two, `stable` and `rc`.

| Channel | What a new install gets today | Who it is for |
| --- | --- | --- |
| `stable` | `os-v4.0.4-mac.1.20260924-rc`, the Aurora kernel on the stable lane | Daily drivers |
| `rc` | `os-v4.0.4-mac.1.20260924-rc`, the Aurora kernel on the release-candidate pin | Macs that should take new Aurora kernels first |

<div class="note" markdown="1">
Both channels write the same image and differ only in the kernel lane the Mac follows afterwards. Since 2026-09-24 that image is `os-v4.0.4-mac.1.20260924-rc`, and it admits the 22 M1 and M2 models the earlier Asahi image did; only the 14-inch M1 Pro (`apple,j314s`) and the 16-inch M2 Max (`apple,j416c`) are qualified on hardware. The installer refuses any other model, including every M3 and M4, before touching the disk. The previous images, `os-v4.0.3-mac.5.20260923-rc` (two models) and the Asahi `os-v4.0.3-mac.1.20260913`, are kept for rollback but are no longer offered.
</div>

## Kernels

Two kernels exist. `linux-asahi` comes from the Asahi Linux project through the `[asahi-alarm]` repository. `linux-aurora` is built here from [aurora-silicon/linux](https://github.com/aurora-silicon/linux) and adds DisplayPort alt-mode and USB4 external monitors, variable refresh rate, the camera signal processor and the always-on processor.

An installed Mac is therefore in one of three states, and the updater refuses any other combination:

| Channel | Kernel | Meaning |
| --- | --- | --- |
| `stable` | `linux-asahi` | A legacy Asahi Mac, installed from the stable image before 2026-09-23 |
| `stable` | `linux-aurora` | An Aurora Mac on the stable lane, which carries rc's hardware-qualified kernel; includes new Stable installs |
| `rc` | `linux-aurora` | An Aurora Mac on the release-candidate pin |

The fork is moving the stable channel onto Aurora and retiring the Asahi kernel once Aurora has had enough hardware time. Existing Macs are migrated rather than stranded. Until that finishes, "stable" describes a channel, not a single kernel.

There is a third Aurora lane, `edge`, which floats on the upstream branch head. It is for lab Macs. The installer does not offer it and `omarchy-channel-set` refuses it on a Mac.

## Picking a channel

The installer opens on **Stable** at every launch. To install on `rc`, choose it in the **Release Channel** menu before the download starts; the choice lasts until the app quits.

**Choose at install time, because the kernel family stays.** A Mac installed on the Asahi kernel stays on it, and the switch command refuses: moving between kernel families is not available. A Mac on the Aurora kernel can move between the Aurora lanes, `stable` and `rc`, with the ordinary Omarchy command, which records the request, takes the update lock and runs an update that moves the kernel and proves it boots:

```bash
omarchy-channel-set rc
```

The Mac's own record lives in `/var/lib/omarchy/apple-silicon-channel`, and the installed kernel is named in `/usr/share/omarchy/apple-silicon-kernel`. A lane switch is a request until an update has proven the new kernel boots; only then is it recorded as done.

## How an update arrives

`omarchy update` behaves as it does on x86, with three Apple-specific steps in front:

1. **Runtime bundle.** `omarchy-update-asahi-bundle` reads the runtime channel pointer, verifies the release descriptor, the six-package manifest, the checksums and the signatures, then installs `omarchy-keyring`, `omarchy-settings-dev`, `omarchy-dev`, `omarchy-nvim`, `quickshell-git` and `ttf-jetbrains-mono-nerd-basic` as one transaction. It refuses to downgrade any of them, with one exception: a package the retired `[omarchy-aarch64]` repository built, proven by its name, version and build date in that repository's sync database.
2. **Legacy repository cleanup.** On a Mac that came from the omarchy-mac project, `omarchy-update-asahi-legacy-repository` removes its unsigned `[omarchy-aarch64]` repository from `/etc/pacman.conf` (backup under `/var/lib/omarchy/backups/`), keeps `[omarchy]` ahead of what that repository shadowed, and replaces `obsidian-appimage` and `hyprland-preview-share-picker-git` with the `[omarchy]` packages. On other Macs it does nothing. A step that cannot finish keeps the section, or the legacy package, in place and the next update tries again; the update carries on either way.
3. **Package repository.** `omarchy-update-asahi-repository` points `[omarchy]` at the current promoted package channel. Rollbacks of the package or release sequence are refused.
4. **Everything else** comes from the live Arch Linux ARM and Asahi mirrors, as upstream.

A snapper snapshot is taken before the package sync. `snapper list` shows it. On a lab Mac with `/var/lib/omarchy/snapshot-restore.enabled`, `omarchy-snapshot restore <number>` reboots into a writable clone of a snapshot.

When a new kernel is installed the updater rebuilds the initramfs, refreshes m1n1 and the device trees, runs the boot check and offers a reboot.

## What is signed, and by what

| Artefact | Key |
| --- | --- |
| Packages in `[omarchy]` | The ARM repository signing subkey |
| Runtime bundle and release descriptors | The Omarchy MX Mac release key, `5983B1CA…5959` |
| Channel catalogs read by the installer | One Ed25519 key that never leaves the owner's Keychain |
| Installer app and `.pkg` | Apple Developer ID `T2C384FJBD`, notarized |

Only four keys on the download host are ever rewritten: each channel's `catalog.signed.json` and `channel.json`, and each channel's installer `.pkg` and `installer.json`. Everything under `releases/` is immutable and held by a bucket lock.
