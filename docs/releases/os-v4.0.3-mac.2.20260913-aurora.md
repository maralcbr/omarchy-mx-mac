# Aurora RC 4.0.3-mac.2 — 2026-09-13

Corrects the Aurora RC fresh-install image with the bootloader and login fixes qualified on the M2 Max.

## Changes

- Restore USB-C display initialization with the m1n1 1.6.1 Aurora device-tree alias backport. The kernel remains Aurora `tb` commit `38c14f6107dfdb3366dee3cdfc3226cf4cda9ca2`, packaged as `linux-aurora 7.1.12.aurora2-2`.
- Restrict ARM64 GRUB video loading to `efi_gop`, removing the missing `efi_uga.mod` warning.
- Show password dots in SDDM and restore keyboard focus when external monitors register after the internal display. Preserve a prompt the user has already selected.
- Include the shared 4.0.3 runtime fixes for early Apple DRM readiness and initramfs device-node ordering.
- Install the complete Aurora boot chain in the first package transaction. Confine native image-builder boot hooks to the image ESP and include repository-normalization timestamps in checkpoint identity.

## Validation

Both USB-C monitors displayed content on the M2 Max, and the owner confirmed the boot warning was gone. The exact signed m1n1 package regenerated the hardware-qualified boot image. Real SDDM testing showed six dots for six dummy characters on each of three displays; two service starts selected the internal prompt. No password was captured or submitted during those tests.

The final shared runtime passed native ARM64 VM installation, interruption/recovery, reboot, all 23 optional installations, and completed-installer rerun rejection. This VM evidence covers the runtime; the Aurora kernel and display evidence comes from physical hardware.

Focused image, boot, login and checkpoint tests passed. Source shell CI passed 277 of 278 test files; the existing engine-source-lock platform contract check remains a known failure. The verified engine 15 artifact is unchanged.

The final image build, installed-content contract, archive CRC and member hashes, and signed 22-model catalog passed. The installed SDDM theme and compositor configuration match the hardware-tested fixes. The image contains runtime channel 32 (`asahi-quattro-a67d7f78`) and uses `efi_gop`.

- Image source: `8d21512497a21144378cd1c748175099f6bce6eb` (`omarchy-iso`, `aurora/rc-channel`).
- Runtime source: `a67d7f787c3cc2a3c1247a1bdb4c36732f07b465`.
- Archive: `omarchy-2026.09.13-aarch64-apple-silicon-aurora-os-package.zip`, 4,227,720,850 bytes.
- Archive SHA-256: `45b7189cee030f89f8523c389023bdfc7c465f1712ef3da3357a59ad429e7931`.
- Assembled m1n1 SHA-256: `68512baecd1dba57198d1ebd64508a1d304dbee9bfc3ebcea582902d79e529a6`, identical to the qualified M2 boot image.
- Catalog SHA-256: `5c9548982ef235016b17dea5ef33d3eae977aab81ff53484db53368e14e9c2f9`.

This is the first publication of these image bytes; no independent second-build reproducibility match is claimed.

## Scope

The installer’s RC Aurora selection receives this image after channel promotion. A physical fresh installation of this exact final archive is not claimed. Existing installations consume shared runtime updates separately; their immutable Aurora kernel repository requires an explicit repoint for a kernel/bootloader package update.
