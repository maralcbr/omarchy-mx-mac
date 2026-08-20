---
name: update-omarchy-quattro
description: Update final Omarchy Quattro on Apple Silicon, including stable Mac source, signed release metadata, the exact six-package Asahi bundle, local installation, reboot validation, and retirement of legacy release 3 and alpha channels.
---

# Update Final Omarchy Quattro

Omarchy Quattro is final. Maintain one product line: upstream final Quattro feeds
the Mac fork's `main` branch and the stable Apple Silicon package bundle. Do not
restore the former dual-track `main` plus alpha `quattro` workflow.

## Release Model

- Confirm a stable upstream `v4.x` release and use its tagged commit as the
  immutable merge target. Follow upstream `quattro` only after confirming it is
  the source of that stable tag.
- The Mac fork's `main` branch is the sole maintained source branch.
- Release 3 is legacy. Do not update, package, or promote 3.x after the final
  Quattro release is published and validated.
- Stable Mac tags use `vUPSTREAM_VERSION-mac.N` and signed monotonic stable
  descriptors.
- Apple Silicon bundles are built from the exact Mac `main` commit and contain
  exactly `omarchy-keyring`, `omarchy-settings-dev`, `omarchy-dev`,
  `omarchy-nvim`, `quickshell-git`, and `ttf-jetbrains-mono-nerd-basic`.
- Replace alpha/prerelease naming with a stable Asahi Quattro channel only after
  the replacement has passed local installation and reboot validation.

## Safety Invariants

Do not proceed past a failed invariant.

- Target only validated `aarch64` Apple hardware, currently `apple,j314s`.
- Preserve `linux-asahi`, GRUB, `/boot/vmlinuz-linux-asahi`, `[asahi-alarm]`,
  `[core]`, `[extra]`, `[alarm]`, `[aur]`, NetworkManager with `wifi.backend=iwd`,
  and disabled swap, zram, and zswap.
- Never activate x86 kernels, Limine, mkinitcpio boot policy, NVIDIA/Intel GPU
  policy, multilib, zram, zswap, reclaim tuning, or USB autosuspend on Asahi.
- Review every new migration and explicitly mark its Asahi disposition as
  `run`, `handled`, or `skipped`; unknown migrations fail closed.
- Never resolve conflicts by moving protected boot, pacman, GRUB, mkinitcpio,
  or NetworkManager paths.
- Do not retire a 3.x release, alpha branch, or alpha channel until the final
  replacement source, signed assets, local install, and reboot all pass.

## Workflow

1. Inspect all worktrees, remotes, tags, releases, and installed package state.
   Fetch `origin`, upstream branches, and tags. Record the upstream stable tag,
   tagged commit, Mac main tip, package pin, and installed bundle sequence.
2. Update `main` from the immutable upstream final tag. Merge without committing
   first, resolve conflicts semantically, and preserve all Apple-specific paths.
   Review migrations, package lists, boot/initramfs/kernel changes, pacman,
   NetworkManager, GPU policy, systemd units, installers, and update recovery.
3. Update stable release metadata and documentation to `v4.x-mac.N`. Keep the
   dedicated release key fingerprint and monotonic descriptor sequence.
4. Run the full source suite plus focused Apple hardware, package, migration,
   update, conflict-recovery, zram, systemd, and config-contract tests. Record
   optional environmental gaps rather than reporting them as passing.
5. Pin both package recipes to the same full Mac `main` commit. Keep aarch64
   exclusions and use a package version greater than the installed version.
6. Build and verify exactly six packages. Check architecture, source identity,
   checksums, package metadata, protected-path exclusions, and `vercmp`.
7. Create a root-owned recovery backup of `/boot`, pacman, NetworkManager,
   package inventory, failed units, and user Omarchy state. Install exactly the
   verified six-package transaction and run reviewed migrations.
8. Validate packages, ownership, pending state, failed units, protected config
   hashes, kernel/GRUB/repositories/iwd, swap policy, hardware, shell runtime,
   and visual output. Capture and inspect a fullscreen screenshot for visual
   changes.
9. Reboot only after pre-reboot checks pass, then repeat package, platform,
   service, network, hardware, and failed-unit checks.
10. Publish signed stable source and bundle assets through protected workflows.
    Verify fresh public downloads, checksums, signatures, immutable tag/source
    binding, stable channel monotonicity, and installer `--verify-only`.
11. After source/package/release updates and their automated gates pass, ask the
    user whether to run the disposable VM installation test described below.
    Do not start it automatically. If the user agrees, run it before reporting
    the release as fully validated.
12. Mark release 3 and alpha Quattro assets as legacy only after all replacement
    checks pass. Keep immutable historical releases available unless explicit
    deletion is requested; remove them from latest/recommended documentation.
13. Remove temporary privilege and prove non-interactive sudo is revoked.

## Preferred VM Validation

The proven post-update process is the disposable direct-Asahi-install VM
harness, not a generic desktop acceptance run:

```bash
test/vm/asahi-fresh/run
```

Run it after publishing the release when the user approves the VM check. Use
`--rebuild-base` when the base image or package/bootstrap behavior changed; use
`--keep` only when interactive investigation of the retained Docker VM is
needed. The normal run removes the VM container automatically.

This harness intentionally uses a generic aarch64 KVM guest with only the Apple
hardware predicates adapted in a retained test copy. It verifies the unchanged
public signed stable and Asahi assets, then exercises the local fresh installer
candidate and the real Asahi package closure. Its successful lifecycle covers:

- exact six-package installation and pinned source builds
- lock-collision, build-account, sudo-rule, and package-cache collision safety
- hard-kill interruption recovery during package builds, including repeated
  recovery attempts
- completion recovery, user/system finalization, migrations, and reboot
- protected boot files, package integrity, repositories, NetworkManager/iwd,
  disabled swap/zswap, enabled services, and absence of pending migrations
- rejection of a completed fresh-install rerun without package or release-state
  changes
- cleanup of the temporary VM SSH firewall allowance and temporary build
  account/sudo rule

Inspect the run output and the artifacts under
`test/vm/asahi-fresh/test-runs/<run>/`, especially `install.log`,
`serial.log`, `verify.log`, `rerun.log`, `vm-adapter.log`, and `desktop.ppm`.
Report the VM result separately from physical Apple hardware validation: the VM
cannot prove Apple GPU, Wi-Fi, audio, suspend, device-tree, or Mac-control
behavior.

## Completion Report

Report the upstream final version/tag/commit, Mac main commit/tag, package
commit/version, migration dispositions, tests and gaps, backup path, install and
reboot checks, screenshots, public release URLs, legacy status changes, branch
retirement, and temporary-privilege removal.
