---
title: Welcome to Omarchy MX Mac
description: Omarchy for Apple Silicon Macs, installed from macOS with a signed installer.
section: Using it
---

Omarchy MX Mac runs [Omarchy](https://omarchy.org) on Apple Silicon Macs. It keeps Omarchy's desktop, keybindings and update experience, and replaces the parts that Apple hardware needs: a macOS installer instead of an ISO, Arch Linux ARM and the Asahi Linux stack instead of x86 Arch, and a boot chain that lives next to macOS.

It is a community fork of [omacom/omarchy](https://github.com/omacom/omarchy). Everything that is not Mac-specific is upstream Omarchy, so the [Omarchy manual](https://omarchy.org/manual/) applies unchanged. This manual covers only what is different on a Mac and how the fork is built.

## Who this is for

- Owners of a MacBook Pro 14" M1 Pro or 16" M2 Max who want Omarchy as a daily driver next to macOS.
- People who want to know how the fork is put together before trusting it with a disk.
- Contributors who need the map of repositories, channels and release gates.

## Current state

| | |
| --- | --- |
| Omarchy release | 4.0.4 (`4.0.4-mac.1`), on both channels |
| Installer app | 2.0.9 (opens on Stable at every launch; choose RC from the Release Channel menu) |
| Stable channel | `os-v4.0.4-mac.1.20260924-rc`, Aurora kernel, Limine boot menu (since 2026-09-24) |
| Release candidate channel | `os-v4.0.4-mac.1.20260924-rc`, the same image |
| Macs a new install admits | The 22 M1 and M2 models; hardware-qualified on the MacBook Pro 14" M1 Pro (`apple,j314s`) and 16" M2 Max (`apple,j416c`) |
| Reference Mac | MacBook Pro 14" 2021, M1 Pro (`apple,j314s`) |
| Also exercised | MacBook Pro 16" 2023, M2 Max (`apple,j416c`), five displays |

Apple Silicon support depends on the Asahi Linux project and the Aurora kernel. See [Hardware support]({{page:hardware}}) before installing.

Both channels install the same image today. Macs installed from the earlier Asahi stable image keep the Asahi kernel, and this manual says so where that differs. Work that is decided but not yet in either channel is on [Decided, not yet shipped]({{page:roadmap}}), never stated here as if it shipped.

## Where to start

1. [Install on a Mac]({{page:install}}): download, verify and run the installer.
2. [Channels and updates]({{page:channels}}): what `stable` and `rc` mean and how updates arrive.
3. [Architecture]({{page:architecture}}): how the three repositories, the signed channels and the installer fit together.

<div class="note" markdown="1">
This project is not affiliated with Apple, the Asahi Linux project or the Omarchy Foundation. It is not intended for Parallels, virtual machines or non-Asahi ARM systems.
</div>
