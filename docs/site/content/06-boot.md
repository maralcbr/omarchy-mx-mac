---
title: Boot chain and kernels
description: From Apple firmware to the Omarchy root, and the three kernel lanes.
section: How it is built
---

An Apple Silicon Mac has no UEFI of its own. Everything up to U-Boot comes from the Asahi Linux project. The fork uses it as Asahi ships it, except that U-Boot is built with a silent console. Omarchy's part starts at the boot loader, Limine.

{{diagram:boot-chain}}

## Stages

| Stage | Owner | What it does |
| --- | --- | --- |
| iBoot | Apple | Apple firmware. Enforces the boot policy set in recoveryOS and starts the chosen boot object. |
| m1n1 | Asahi | Stage 1 is the boot object iBoot starts. Stage 2 initialises the hardware Apple firmware leaves alone and passes a Linux device tree on. |
| U-Boot | Asahi, packaged as `uboot-asahi` | The only UEFI implementation on Apple Silicon. Loads the EFI boot loader from the EFI system partition. |
| Boot loader | Omarchy | Limine on new installs from both channels. Macs installed from earlier images boot through GRUB. |
| Kernel and initramfs | omarchy-pkgs and `omarchy-mac-boot` | `linux-asahi` or `linux-aurora`, with a systemd initramfs built by mkinitcpio carrying the vendor firmware and Apple HID hooks. |
| Root | Omarchy | A btrfs root with the `@` subvolume, snapper snapshots and, optionally, LUKS. |

The boot check that `omarchy update` runs before offering a reboot verifies the kernel, the initramfs hooks, the m1n1 payload and the boot loader configuration against what the packages say they should be, and refuses the reboot on a mismatch.

## Boot loader

Earlier releases boot through GRUB with a themed menu and `grub-btrfs` entries for snapshots. On 2026-09-22 the fork settled on Limine, upstream Omarchy's boot loader, after comparing the two on hardware:

- U-Boot loads Limine from `BOOTAA64.EFI` on the EFI system partition.
- `limine-mkinitcpio-hook` builds a unified kernel image (UKI) on every kernel or initramfs change. Kernel copies must live on the EFI system partition, so the hook keeps them there.
- `limine-snapper-sync` lists snapper snapshots in the boot menu, and `limine-snapper-restore` restores one.
- GRUB does not survive the switch. Activating Limine removes the experiment's `GRUB (recovery)` entry, so the menu is Omarchy's and its snapshots and nothing else.
- U-Boot is made silent: no banner, no logo, no boot delay. The menu the user sees is Limine's.

The Limine packages are in the `[omarchy]` repository and every image built from `main` writes the `/var/lib/omarchy/limine.enabled` gate. The image both channels install today, `os-v4.0.3-mac.5.20260923-rc`, boots through Limine. It passed VM acceptance; a physical install has not been recorded yet. Macs installed from earlier images still boot through GRUB.

## Kernel lanes

| Package | Source | Where it comes from | Used by |
| --- | --- | --- | --- |
| `linux-asahi` | Asahi Linux project | the `[asahi-alarm]` repository, not built here | Macs installed from the earlier Asahi `stable` image (before 2026-09-23) |
| `linux-aurora` | `aurora-silicon/linux` | built here from a pinned commit | the `stable` and `rc` lanes, including every new install |
| `linux-aurora` | `aurora-silicon/linux` branch head | built here, floating | the `edge` lane, lab Macs only |

`linux-aurora` provides `linux-asahi`, so nothing above the kernel cares which is installed. The lane is the choice of the `[omarchy-aurora]` repository, and moving between lanes is an explicit signed upgrade or downgrade rather than a version comparison, because versions are not ordered across lanes.

The three recipes in omarchy-pkgs are `linux-aurora-rc`, `linux-aurora-stable` and `linux-aurora-edge`, all with `pkgbase` `linux-aurora`. The edge recipe rebuilds when the upstream branch head moves, gated by an input digest so an unchanged tree never rebuilds. The patches the fork used to carry have been merged upstream, so the recipes carry none.

## Initramfs

The initramfs is systemd-based. `omarchy-mac-boot` drops in:

- `MODULES` entries for `hid_apple`, `hid_magicmouse`, `dockchannel-hid` and `usbhid`, added only when the running kernel really has them as modules, so a kernel that builds a driver in does not break later `mkinitcpio -P` runs;
- the vendor firmware service that copies Apple firmware onto the root, and a second copy that runs before `cryptsetup-pre.target` on encrypted Macs so Wi-Fi and input work at the passphrase prompt;
- a Plymouth drop-in so the passphrase prompt is graphical;
- the `kmod-static-nodes` ordering fix that btrfs roots need on Apple hardware.

## Encryption

Encryption is chosen in the installer and performed on the first boot. The conversion runs in the initramfs before `sysroot.mount`, shrinks the file system, re-encrypts in place, then regenerates the boot loader configuration and the initramfs with `sd-encrypt`. A second boot unlocks the volume with the owner's passphrase. Installed Macs that were not asked to encrypt are never touched: the unit requires a pending marker written by the installer and refuses to run without it.

## Snapshots

The root is btrfs. `omarchy update` creates a snapper snapshot before the package sync and keeps the five most recent. Creating and listing snapshots needs nothing special.

Restoring one is a different matter and is deliberately hard to reach. On a GRUB Mac, `omarchy-mac-snapshot-restore` swaps the root subvolume from the running system, and that rename pair is not crash-safe: losing power between the two renames leaves no root until it is repaired from a rescue system. So it refuses to run unless the machine has opted in:

```bash
sudo touch /var/lib/omarchy/snapshot-restore.enabled
```

It also refuses on a Mac that boots Limine, because restoring a root from before the Limine migration would put GRUB's defaults back underneath a Limine boot. Those Macs use `omarchy-snapshot restore` instead, which goes through `limine-snapper-restore`.

Because the kernel on the boot partition stays where it is, only snapshots carrying the modules for the running kernel are accepted.
