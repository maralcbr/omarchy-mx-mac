---
title: Install on a Mac
description: Download the signed installer, verify it, and install Omarchy next to macOS.
section: Using it
---

Installation starts in macOS. The installer app downloads the current signed Omarchy release for the channel you pick, resizes the APFS container, writes the Omarchy image and hands over to a first boot that finishes the setup on the Mac itself.

## Before you begin

- Back up macOS and anything you care about. The installer shrinks your macOS volume.
- Check your model on the [Hardware support]({{page:hardware}}) page and the [Asahi Linux device list](https://asahilinux.org/fedora/#device-support).
- The release carries firmware for macOS 13.5 and 14.8.3, and the installer picks one for the Omarchy volume. A Mac running a newer macOS than the release knows about cannot install until the release is updated.
- Keep at least 50 GB free on the internal SSD. 100 GB is comfortable.
- Plug in power and use a reliable Internet connection. The image is a multi-gigabyte download.
- Expect model-specific limits around external displays, speakers, cameras and power management.

## Download

The link never changes and always serves the current installer:

<a class="button" href="https://downloads.aicodelabs.com.au/installer/stable/Omarchy-MX-Mac-Installer.pkg">Download Omarchy MX Mac Installer</a>

Verify the download before opening it. Both commands must report an Apple Developer ID for `MARCELO DE BARROS ALCANTARA (T2C384FJBD)`:

```bash
pkgutil --check-signature ~/Downloads/"Omarchy-MX-Mac-Installer.pkg"
spctl -a -vv -t install ~/Downloads/"Omarchy-MX-Mac-Installer.pkg"
```

<div class="note warn" markdown="1">
Installers older than 2.0.0 were pinned to a single Omarchy release and stop working on 2026-12-01. Replace them with the download above.
</div>

## Run the installer

1. Open the `.pkg`. It installs **Omarchy MX Mac Installer** into `/Applications` together with a privileged helper that performs the disk work.
2. Open the app. It fetches the signed catalog for the selected channel and checks the catalog signature, the sequence number and the SHA-256 of every file it downloads.
3. Choose a channel explicitly in the **Release Channel** menu, even if the banner already names the one you want: `rc` for the Aurora kernel and its external-display support, `stable` for the Asahi kernel. Choosing saves it, and the kernel family is fixed at install. See [Channels and updates]({{page:channels}}).
4. Choose how much space to give Omarchy. The APFS container is shrunk and three partitions are created: an EFI system partition, a boot partition and a root partition that grows into the free space.
5. Choose whether to encrypt the root file system. Encryption is set up on the first Linux boot and asks for a passphrase on every boot afterwards.
6. Follow the prompt to complete the boot policy step in recoveryOS. This is Apple's own step and requires your macOS password.

The Mac reboots into Omarchy. The [first boot]({{page:install-flow}}) installs vendor firmware, converts the root to LUKS if you asked for it, creates your user and lands on the desktop.

## Switch back and forth

Hold the power button at startup to pick macOS or Omarchy. In macOS, System Settings → General → Startup Disk selects the default. On the Omarchy side, `asahi-bless` does the same.

## Verify the app instead of the package

If you unpack the app yourself:

```bash
codesign --verify --deep --strict ~/Downloads/"Omarchy MX Mac Installer.app"
spctl -a -vv -t execute ~/Downloads/"Omarchy MX Mac Installer.app"
```

Gatekeeper must report `Notarized Developer ID`.
