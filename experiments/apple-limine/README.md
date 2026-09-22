# Limine on Apple Silicon (experiment)

Tried on the M1 Pro on 2026-09-22 against the project invariant that Apple
Silicon boots GRUB. Limine 12.9 (Arch Linux ARM `limine`, aarch64) placed as
`/EFI/BOOT/BOOTAA64.EFI` on the ESP, GRUB kept beside it as
`grub-aa64.efi` (and a copy under `/var/lib/omarchy/backups`) with a
chainload entry in the Limine menu. The kernel and initramfs are copies on
the ESP under `/omarchy/` because Limine reads FAT and ISO 9660 only, not
the ext4 Boot partition. U-Boot's device tree reaches the kernel through the
EFI configuration table (Limine's aarch64 Linux protocol copies it and
enters the kernel directly, bypassing the EFI stub).

Result: boots. `/proc/cmdline` is the Limine one, `efi: EFI v2.11 by Das
U-Boot`, the initrd is handed over through the EFI table, no failed units.

What a real integration would need beyond this experiment:
- keep the ESP copies in step with `/boot` on every kernel and initramfs
  rebuild (a pacman hook, or UKIs through `limine-mkinitcpio-hook` if
  `systemd-stub` for aarch64 boots under U-Boot's UEFI);
- the encrypt flow, provisioning re-key and boot check write GRUB's
  `/etc/default/grub` (`rd.luks.*`, `root=`); they would write Limine entries;
- snapshot entries (`limine-snapper-sync` expects UKIs and x86 paths);
- the Asahi `update-grub` pacman hook keeps regenerating GRUB and copies its
  EFI over `/EFI/BOOT/BOOTAA64.EFI` on kernel updates, so Limine must be
  restored after it or installed under another path that U-Boot boots first;
- U-Boot's own console text is unaffected either way.

`deploy-m1.sh install|rollback` stages or reverts the experiment on the Mac
where it runs; `~/omarchy-lab/serve/g` is the macOS-side rescue.
