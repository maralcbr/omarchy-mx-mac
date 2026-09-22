# Limine on Apple Silicon

Decision (2026-09-22): Limine is the boot loader for Omarchy on Apple
Silicon. GRUB is no longer part of the boot; the Asahi `update-grub` still
runs on kernel updates (asahi-scripts pacman hook) and is retargeted to an
unused file under `/boot/grub`.

## How it boots

m1n1 → U-Boot (`uboot-asahi` from the [omarchy] repository: the Asahi U-Boot with a silent console, no
banner, no logo, no boot delay) → `ESP:/EFI/BOOT/BOOTAA64.EFI`, which is
Limine (Arch Linux ARM `limine`). Limine shows the Omarchy Bootloader menu
for 3 s (`Omarchy › linux-aurora`, `Snapshots`) and chainloads the UKI that
`limine-mkinitcpio-hook` builds with the aarch64 systemd-stub into
`ESP:/EFI/Linux/omarchy_<kernel>.efi`; U-Boot's device tree reaches the
kernel through the EFI configuration table.

Emergency shell, as on x86: highlight the kernel entry, press `E`, append
`systemd.unit=emergency.target` (or `rescue.target`), Enter. Or boot a
snapshot from `Snapshots`.

## Pieces

- `install/hardware/apple/limine-boot.sh`: activation, idempotent, from
  `install/hardware/all.sh`, gated on `/var/lib/omarchy/limine.enabled`
  with the `limine`, `limine-mkinitcpio-hook` (omarchy-pkgs build,
  aarch64-enabled) and `limine-snapper-sync` packages installed.
  `update-grub` is retargeted, Limine's defaults and menu written, the UKI
  and entries built, and only then is Limine copied into the U-Boot slot.
  A failed activation restores GRUB's target and regenerates GRUB.
- `bin/omarchy-mac-limine-cmdline`: `/etc/default/grub` stays the one file
  the encrypt flow, the re-key and the console leaf write the kernel
  command line to; this derives `KERNEL_CMDLINE[default]` from it
  (root=UUID of the root filesystem, one `rootflags=` with `subvol=@`) and
  runs before every UKI rebuild as
  `/etc/boot/hooks/pre.d/20-omarchy-mac-cmdline`.
- `bin/omarchy-mac-boot-update`: on a Limine Mac `limine-update` and the
  ESP's Limine; on a GRUB Mac `update-grub`. The encrypt flow (omarchy-pkgs,
  `omarchy-mac-encrypt`), the owner's re-key, the fresh installer and the
  factory reset call it.
- `bin/omarchy-mac-limine-deploy` and the pacman hook
  `81-omarchy-mac-limine-deploy.hook`: `limine-install` deploys nothing on
  aarch64, so the packaged Limine is copied to the ESP when it changes.
- `bin/omarchy-snapshot`: on a Limine Mac the x86 tooling (the
  `limine-snapper-sync` watcher writes the entries, `limine-snapper-restore`
  restores). `omarchy-mac-snapshot-menu` (grub-btrfs) is a no-op there.
- `bin/omarchy-apple-silicon-boot-check`: on a Limine Mac verifies the UKI,
  the entry's root and LUKS mapping, and that the ESP carries the installed
  Limine; the grub.cfg checks apply to GRUB Macs only.
- omarchy-pkgs `uboot-asahi`: Asahi's package name with a higher pkgrel, so pacman installs it from [omarchy].
  An `uboot.env` on the ESP overrides the default environment, so it must
  carry `silent=1` or not exist.

## Verified on the M1 Pro (2026-09-22)

Activation leaf (idempotent, 10 s), boot check, snapshot entry written by
the watcher, a snapshot booted from the Limine menu under the tmpfs
overlay, `limine-snapper-restore` from inside it (root swapped, previous
root kept as a snapshot with its own entry), reboot into the restored root
with no failed units, silent U-Boot with no banner and no delay.

## Findings

- `default_entry` counts every entry in the menu tree, directories
  included, so `2` is the kernel entry under `/+Omarchy` as on x86; naming
  a directory leaves Limine waiting at the menu. There is no one-shot boot
  from the OS: U-Boot's runtime SetVariable is volatile.
- `limine-snapper-sync.service` is a watcher; without it running, a
  snapshot gets no entry (the snapper plugin only notifies it).
- `limine-snapper-restore` reads its answers from a terminal; piping them
  does not work.
- Snapshots cannot roll back m1n1 or U-Boot: those live on the ESP.
- U-Boot's silent console also mutes EFI text output (GRUB's text mode);
  Limine's graphical menu and the kernel are unaffected.
