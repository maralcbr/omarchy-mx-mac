---
title: Packages and releases
description: How aarch64 packages are built, accepted, promoted and turned into a channel.
section: How it is built
---

Omarchy's own packages are built on GitHub's arm64 runners from the `asahi-quattro` branch of omarchy-pkgs, signed, published as immutable GitHub releases and only then pointed at by a channel. The rest of an installed system comes from Arch Linux ARM and the Asahi repositories, as it does upstream. Nothing is built on the test Macs, and no package of ours reaches a user without passing the acceptance gates.

{{diagram:release-pipeline}}

## What is packaged

- **Runtime pair**: `omarchy-dev` and `omarchy-settings-dev`, built from a pinned omarchy-mx-mac commit. They are the same two packages upstream builds, with `arch` widened to aarch64. `omarchy-settings` carries everything that must be on the target before `useradd` and the boot loader install; `omarchy` carries the binaries, install scripts, migrations, themes and the Quickshell desktop.
- **Boot**: `omarchy-mac-boot` (vendor firmware, HID modules, first-boot gates, encryption), `uboot-asahi`, `limine-mkinitcpio-hook`, `limine-snapper-sync`.
- **Kernels**: `linux-aurora-rc`, `linux-aurora-stable` and `linux-aurora-edge`, all with `pkgbase` `linux-aurora`. `linux-asahi` is not packaged here; it comes from `[asahi-alarm]`.
- **Default set**: about 60 packages that Omarchy's default install needs but Arch Linux ARM does not carry, from Hyprland and aquamarine to Obsidian, 1Password and the libretro cores. The list is `pkgbuilds/asahi-repository-packages`.

Recipes that are useful to every aarch64 Omarchy user are contributed to omacom/omarchy-pkgs as plain PKGBUILDs.

## Incremental builds

A release starts with the planner. It compares the inputs of every package group with the previous candidate and rebuilds only the groups whose inputs changed: a PKGBUILD, a patch, a source pin, a kernel input digest. Changes it cannot classify, or changes to the builder, the toolchain, the signing key or the package inventory, fail closed to a full rebuild. Appending a package to a list is classified as no rebuild of the existing packages.

Unchanged packages are carried forward byte for byte from the predecessor release, with their digests verified against the predecessor's descriptor.

## Gates

| Gate | Where | What it proves |
| --- | --- | --- |
| Candidate build | GitHub Actions, environment `asahi-quattro-release` | Every package builds and signs; the descriptor lists each archive with its digest |
| VM acceptance | KVM on a test Mac, because GitHub's arm64 runners have no KVM | A fresh install from the candidate boots, updates and passes its checks |
| Hardware gate | A test Mac, cold boot | Required when a boot package moves, meaning a kernel, m1n1, U-Boot, `asahi-fwextract`, `asahi-scripts`, the boot package, the Limine hook or a DKMS module, or when the qualified kernel pin changes. VM acceptance boots a generic kernel and cannot clear it. |
| Image acceptance | KVM on a test Mac | The Mac image installs, boots plain and encrypted, and survives a second boot |
| Catalog signature | The owner's Mac | The channel catalog is signed with the Keychain key |

A candidate that passes is promoted byte-identically to `asahi-packages-stable-<sha>`. The runtime channel `asahi-quattro-channel-<N>` then names the six-package bundle installed Macs pull. The image lane builds from the promoted channel, and the catalog names the image.

## One release command

`bin/asahi-release` in omarchy-pkgs runs the package path: plan, candidate, wait for acceptance, promote and runtime channel, stopping at any gate that needs a human and resuming with the evidence. The fresh-install image is a separate lane: built by `release-mac-image.yml`, VM-accepted, then staged, signed by the owner and promoted by hand. It refuses to publish an older build over a newer one, and the publisher checks the asset set before it marks a release complete.

There is a fast path too. It needs two things at once: the candidate rebuilt only runtime packages, and its package set is exactly what the live package channel already publishes, name, version and archive hash for every package. Then a new runtime channel is published in about fifteen minutes and nothing else moves. Anything else takes the full path, including a candidate whose set matches but which rebuilt a non-runtime package.

## Mirrors

Image builds and VM acceptance read a dated Arch Linux ARM snapshot on R2 (`mirror/alarm/<date>/`), so a build is reproducible and never depends on a mirror's state that day. Installed Macs use live mirrors, exactly as an upstream Omarchy install does.

## Versioning

Two version lines, separate since 2026-09-04:

- **Installer**: `installer-vX.Y.Z` tags plus an integer build number. The catalog carries `installer.minimum_version`, so a too-old app stops before downloading.
- **OS**: `os-v4.0.4-mac.1.20260924-rc`: the Omarchy version, a Mac release counter, the build date and the lane.

The runtime version string, `4.0.4-mac.1` today, is what `omarchy --version` and the greeter show.
