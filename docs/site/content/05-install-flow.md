---
title: How an install works
description: What the installer app, the Asahi engine and the first boot each do.
section: How it is built
---

The install is three programs handing over to each other: the macOS app decides what to install and proves it is genuine, the Asahi installer engine does the disk work Apple requires, and `omarchy-mac-boot` finishes the job on the first Linux boot.

{{diagram:install-flow}}

## The app

The app ships as a signed and notarized `.pkg` that installs the app bundle and a LaunchDaemon helper. The helper is the only part that runs as root, and the app talks to it over a Mach service whose code-signing requirement is pinned to the same Developer ID.

The bundle carries `Release/release.json`: the channel list, the default channel and the SHA-256 of the Ed25519 trust root that every catalog must be signed by. Because the trust root is in the app, rotating the signing key means shipping a new app.

On launch the app:

1. downloads `channels/<channel>/catalog.signed.json` and verifies the signature against the bundled trust root;
2. refuses a catalog whose `sequence` is not larger than the last one it accepted;
3. checks its own version against the catalog's `installer.minimum_version`, so an old app stops before downloading a release it cannot install;
4. downloads the image parts and the engine overlay named by the catalog, verifying each SHA-256, and reuses cached files only when size and hash match.

## The engine

The engine is the upstream [Asahi Linux installer](https://github.com/AsahiLinux/asahi-installer), pinned by digest in the catalog and built from that checkout with one Omarchy patch and a Python overlay on top. Omarchy MX Mac does not reimplement Apple's boot process: APFS resizing, partition creation, m1n1, the boot policy and recoveryOS remain the Asahi project's work.

The layout is the engine's four partitions: an APFS stub holding a stub macOS that owns the boot object, a 500 MiB EFI system partition, a 2 GiB boot partition and a root partition that expands into the space the user chose. The engine prepares the target, writes `boot.img` and `root.img` with m1n1 and the device trees, and only then asks the user to finish the boot policy step in recoveryOS. The disk is already written when that prompt appears.

The bundled engine in the app only inspects the Mac. The engine that performs the install always comes from the catalog, so an engine fix can ship without a new app.

## The image

The Mac image is built in omarchy-pkgs by `bin/build-mac-image` from a promoted package channel, a runtime channel and a dated Arch Linux ARM snapshot. It is a complete Omarchy installation with no user yet: kernel, initramfs, vendor firmware hooks, the Omarchy runtime pair and the whole default package set, recorded package by package in `PROVENANCE`. The payload is split into parts under GitHub's 2 GiB asset limit and signed as a set (`IMAGE` and `IMAGE.sig`).

Before it can reach a channel, the image is installed and booted in KVM on a test Mac, once plain and once encrypted. The Aurora kernel cannot boot on QEMU's virtual machine, so the harness boots a generic Arch Linux ARM kernel with an initramfs built from the image's own mkinitcpio hooks. The evidence of that run is kept with the release.

## First boot

`omarchy-mac-boot` is the package that owns everything Apple-specific about booting. It is in the image both channels install. Macs installed from the earlier Asahi stable image carry its two predecessors, `omarchy-apple-boot` and `omarchy-first-boot`, which it replaces on the Mac's first `omarchy update`.

On the first boot it:

- copies the Apple vendor firmware the Asahi installer extracted from macOS into the running system and the initramfs;
- loads the Apple keyboard and trackpad drivers early, so the LUKS prompt and the greeter both have input;
- converts the root file system to LUKS if the installer asked for it, from the initramfs and before the root is mounted, then rebuilds the boot loader configuration and the initramfs;
- runs owner provisioning: user, password, re-keying the volume to the owner's passphrase, and any deferred steps;
- records the channel, the kernel marker and the boot check that later updates rely on.

Every one of those files is owned by the package, so a fix to the boot path reaches installed Macs through `omarchy update`. The previous design left some of them behind by the image with no owner, which is why `omarchy-mac-boot` replaced it.
