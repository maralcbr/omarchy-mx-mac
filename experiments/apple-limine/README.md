# Limine on Apple Silicon

Status (2026-09-22): integrated on the branch behind an opt-in gate and
running on the M1 Pro. The M2 Max stays on GRUB until the owner picks one.

## How it boots

m1n1 → U-Boot (the Mac's UEFI) → `ESP:/EFI/BOOT/BOOTAA64.EFI`, which is
Limine 12.9 (Arch Linux ARM `limine`). Limine chainloads the UKI that
`limine-mkinitcpio-hook` builds with the aarch64 systemd-stub into
`ESP:/EFI/Linux/omarchy_<kernel>.efi`; U-Boot's device tree reaches the
kernel through the EFI configuration table. GRUB stays on the ESP as
`grub-aa64.efi` (the Asahi `update-grub` is retargeted to it through
`/etc/default/update-grub`) and as the last menu entry, `GRUB (recovery)`.

## Pieces

- `install/hardware/apple/limine-boot.sh`: activation, idempotent. Runs
  from `install/hardware/all.sh` on Macs carrying
  `/var/lib/omarchy/limine.enabled` with the `limine`,
  `limine-mkinitcpio-hook` (omarchy-pkgs build, aarch64-enabled) and
  `limine-snapper-sync` packages installed. GRUB is regenerated into the
  recovery slot first, Limine's defaults and menu written, the UKI and
  entries built, and only then is Limine copied into the U-Boot slot.
- `bin/omarchy-mac-limine-cmdline`: `/etc/default/grub` stays the one
  source of the kernel command line; this derives `KERNEL_CMDLINE[default]`
  from it (root=UUID of the root filesystem, one `rootflags=` with
  `subvol=@`) and runs before every UKI rebuild as
  `/etc/boot/hooks/pre.d/20-omarchy-mac-cmdline`.
- `bin/omarchy-mac-boot-update`: `update-grub`, then on a Limine Mac
  `limine-update` and the ESP's Limine. The encrypt flow (omarchy-pkgs,
  `omarchy-mac-encrypt`), the owner's re-key, the fresh installer and the
  factory reset call it.
- `bin/omarchy-mac-limine-deploy` and the pacman hook
  `81-omarchy-mac-limine-deploy.hook`: `limine-install` deploys nothing on
  aarch64, so the packaged Limine is copied to the ESP when it changes.
- `bin/omarchy-snapshot`: on a Limine Mac the x86 tooling (the
  `limine-snapper-sync` watcher writes the entries, `limine-snapper-restore`
  restores). `bin/omarchy-mac-boot-sync` (+ unit) rebuilds the ext4 `/boot`
  for the GRUB recovery entry when a Limine restore leaves it behind the
  running kernel.
- `bin/omarchy-apple-silicon-boot-check`: verifies the UKI, the entry's
  root and LUKS mapping, and that the ESP carries the installed Limine.
- omarchy-pkgs `uboot-omarchy`: the Asahi U-Boot with a silent console and
  no logo (`silent=1` in the default environment, `CONFIG_SILENT_CONSOLE`).
  An `uboot.env` on the ESP overrides the default environment, so it must
  carry `silent=1` or not exist.

## Verified on the M1 Pro (2026-09-22)

Activation leaf (idempotent, 10 s), boot check, snapshot entry written by
the watcher, a snapshot booted from the Limine menu under the tmpfs
overlay, `limine-snapper-restore` from inside it (root swapped, previous
root kept as snapshot 9 with its own entry), reboot into the restored root
with no failed units; `omarchy-mac-boot-sync` ran and found /boot current.

## Findings

- `default_entry` counts every entry in the menu tree, directories
  included, so `2` is the kernel entry under `/+Omarchy` as on x86; naming a
  directory leaves Limine waiting at the menu. Prefer entry paths for
  anything but the default. There is no one-shot boot from the OS: U-Boot's
  runtime SetVariable is volatile.
- `limine-snapper-sync.service` is a watcher; without it running, a
  snapshot gets no entry (the snapper plugin only notifies it).
- The tool preserves top-level entry order across `limine-update`; the
  leaf still re-places the recovery entry after the Omarchy block.
- Snapshots cannot roll back m1n1 or U-Boot: those live on the ESP.
- `deploy-m1.sh` and `limine-snapshots.sh` are the first-round hand
  experiment and are superseded by the leaf; `~/omarchy-lab/serve/g` is
  the macOS-side rescue (GRUB back into the U-Boot slot).
