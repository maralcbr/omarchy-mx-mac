---
title: Welcome to Omarchy MX Mac
description: Omarchy for Apple Silicon Macs, installed from macOS with a signed installer.
section: Using it
---

Omarchy MX Mac runs [Omarchy](https://omarchy.org) on Apple Silicon Macs. It keeps Omarchy's desktop, keybindings and update experience, and replaces the parts that Apple hardware needs: a macOS installer instead of an ISO, Arch Linux ARM and the Asahi Linux stack instead of x86 Arch, and a boot chain that lives next to macOS.

It is a community fork of [omacom/omarchy](https://github.com/omacom/omarchy). Everything that is not Mac-specific is upstream Omarchy, so the [Omarchy manual](https://omarchy.org/manual/) applies unchanged. This manual covers only what is different on a Mac and how the fork is built.

## Who this is for

- Owners of an M1, M2 or M3 Mac who want Omarchy as a daily driver next to macOS.
- People who want to know how the fork is put together before trusting it with a disk.
- Contributors who need the map of repositories, channels and release gates.

## Current state

| | |
| --- | --- |
| Omarchy release | 4.0.3, on both channels |
| Installer app | 2.0.8 (defaults to Stable; choose RC from the Release Channel menu) |
| Stable channel | `os-v4.0.3-mac.1.20260913`, Asahi kernel |
| Release candidate channel | `os-v4.0.3-mac.5.20260923-rc`, Aurora kernel, Limine boot menu |
| Reference Mac | MacBook Pro 14" 2021, M1 Pro (`apple,j314s`) |
| Also exercised | MacBook Pro 16" 2023, M2 Max (`apple,j416c`), five displays |

Apple Silicon support depends on the Asahi Linux project and, for the `rc` channel, on the Aurora kernel. See [Hardware support]({{page:hardware}}) before installing.

The two channels are at different points in the fork's history: `rc` comes from the current image pipeline, `stable` from an older one. This manual describes what each channel installs today and says so where they differ. Work that is decided but not yet in either channel is on [Decided, not yet shipped]({{page:roadmap}}), never stated here as if it shipped.

## Where to start

1. [Install on a Mac]({{page:install}}): download, verify and run the installer.
2. [Channels and updates]({{page:channels}}): what `stable` and `rc` mean and how updates arrive.
3. [Architecture]({{page:architecture}}): how the three repositories, the signed channels and the installer fit together.

<div class="note" markdown="1">
This project is not affiliated with Apple, the Asahi Linux project or the Omarchy Foundation. It is not intended for Parallels, virtual machines or non-Asahi ARM systems.
</div>
