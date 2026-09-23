---
title: Decided, not yet shipped
description: Changes that are settled and in progress, so the manual and the code can be read together.
section: Reference
---

This manual describes what installs today. The items below are decided and being built. Each one changes a page above when it ships.

## Limine boot loader

Decided 2026-09-22, after comparing the two on hardware. U-Boot loads Limine, `limine-mkinitcpio-hook` builds unified kernel images, snapshots come through `limine-snapper-sync`, and activating Limine removes GRUB. The image both channels install since 2026-09-23 boots through Limine. Still to do: move Macs installed from earlier images off GRUB. Affects [Boot chain and kernels]({{page:boot}}).

## Aurora kernel in stable

New installs on both channels get the Aurora kernel since the 2026-09-23 promotion. Still to do: migrate Macs installed from the earlier Asahi stable image and retire the Asahi lane. Existing Macs are migrated, not stranded. Affects [Channels and updates]({{page:channels}}).

## Portable installer

The next installer is a portable app in a ZIP with a temporary root worker, replacing the `.pkg` and its LaunchDaemon. A preview build exists. Affects [Install on a Mac]({{page:install}}) and [How an install works]({{page:install-flow}}).

## Retiring omarchy-iso

The Mac image is now built in omarchy-pkgs from packages. The earlier payload builder, omarchy-iso, is being archived rather than deleted once nothing references it. Affects [Architecture]({{page:architecture}}).

## Edge as a channel

`edge` exists for the updater and the lab Macs. It stays out of the installer's channel picker; Mac users see `stable` and `rc` only.

## Known issues being worked on

- Fullscreen windows on very wide displays next to a scaled internal display are clipped. Upstream Hyprland.
- The fourth external display on an M2 Max can stay dark after an HDMI unplug. Kernel side.
- A few seconds of text console between Plymouth and the greeter.
