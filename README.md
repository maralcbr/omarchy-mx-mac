![Omarchy running on Apple Silicon](https://github.com/user-attachments/assets/86b2651c-4b49-4ec5-ae78-023b01e46a15)

# Omarchy Mac: Quattro on Apple Silicon

An experimental compatibility project for running Omarchy Quattro on Apple
Silicon through Arch Linux ARM and Asahi Linux.

[![License](https://img.shields.io/github/license/maralcbr/omarchy-mx-mac)](LICENSE)
[![Stars](https://img.shields.io/github/stars/maralcbr/omarchy-mx-mac?style=social)](https://github.com/maralcbr/omarchy-mx-mac/stargazers)

> [!IMPORTANT]
> The current public release is an upgrade for an existing, working
> `omarchy-mac` installation. It is not a fresh Asahi Linux installer.

## Project Direction

This project is moving from a general Apple Silicon installation guide to a
tested compatibility and release path for Omarchy Quattro on Mac hardware. The
focus is preserving the platform components supplied by Asahi while adopting
the current package-backed Omarchy architecture.

The upgrade is designed to preserve:

- The `linux-asahi` kernel and initramfs
- GRUB and the existing Asahi boot configuration
- Arch Linux ARM and Asahi package repositories
- NetworkManager with the iwd Wi-Fi backend
- Apple-specific audio, camera, display, power, and input support

Unsafe boot, repository, networking, and migration changes fail closed instead
of being applied speculatively.

## Tested Hardware

The first public Quattro preview was tested on this machine:

| Component | Tested configuration |
| --- | --- |
| Model | MacBook Pro 14-inch, 2021 |
| SoC | Apple M1 Pro |
| Device tree | `apple,j314s` |
| Architecture | `aarch64` |
| Kernel package | `linux-asahi` |
| Network stack | NetworkManager with iwd |
| Bootloader | GRUB |

Validation included a real Quattro upgrade, a complete `omarchy update`, two
successful reboots, suspend and resume, Wi-Fi, DNS, audio, microphone, camera,
brightness controls, and power profiles.

The public bootstrap currently rejects every other Apple Silicon model. A
different M1 Pro MacBook, an M1/M2/M3 desktop, or a newer Mac may be similar,
but it is not considered supported until it is tested explicitly.

## Install Omarchy Quattro

### Requirements

You need all of the following:

- The exact `apple,j314s` MacBook Pro described above
- An existing, working `omarchy-mac` desktop
- Arch Linux ARM with the Asahi repositories still configured
- The `linux-asahi`, `networkmanager`, and `iwd` packages
- NetworkManager configured with `wifi.backend=iwd`
- A current backup and at least one reliable network connection
- AC power connected during the upgrade

Before starting, back up important data and, at minimum, `/boot`,
`/etc/pacman.conf`, `/etc/pacman.d`, `/etc/NetworkManager`, and
`~/.local/state/omarchy`. Keeping Ethernet available is recommended.

### Download And Verify

Run these commands as your regular Omarchy user, not as root:

```bash
mkdir -p ~/Downloads/omarchy-quattro
cd ~/Downloads/omarchy-quattro

release=https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-quattro-bf71823f
curl -fLO "$release/install-asahi-quattro"
curl -fLO "$release/SHA256SUMS"
sha256sum --ignore-missing --check SHA256SUMS
```

You can verify the complete 291 MB release without changing the system:

```bash
bash install-asahi-quattro --verify-only
```

A successful check ends with:

```text
Verified asahi-quattro-bf71823f for the tested apple,j314s MacBook Pro.
```

### Run The Upgrade

Start the interactive upgrade:

```bash
bash install-asahi-quattro
```

Read the preflight summary and confirmation carefully. The upgrader downloads
and validates the six-package aarch64 bundle before mutation, creates a
root-owned recovery backup, and then performs the reviewed Apple Silicon
transition.

Do not reboot if the upgrade reports an error. Save the terminal output and
open an issue with the failure and relevant logs.

### After The Upgrade

Reboot when the upgrade completes successfully, then confirm the core state:

```bash
uname -r
pacman -Q linux-asahi omarchy-dev omarchy-settings-dev networkmanager iwd
NetworkManager --print-config | grep 'wifi.backend=iwd'
nmcli device status
omarchy-migrate --pending
```

The expected Quattro packages for this preview are:

```text
omarchy-dev 4.0.0.r5665.gbf71823-1
omarchy-settings-dev 4.0.0.r5665.gbf71823-1
```

## What The Bootstrap Checks

Before invoking the upgrader, the public bootstrap verifies:

- `aarch64` architecture and the exact `apple,j314s` device tree
- An existing Omarchy command and required Asahi packages
- The `[asahi-alarm]`, `[core]`, `[extra]`, `[alarm]`, and `[aur]` repositories
- NetworkManager's effective iwd backend
- The release manifest and embedded upgrader checksum
- Exactly one valid archive for each of the six required packages
- Every package checksum before the upgrade script runs

The upgrader performs deeper package metadata, architecture, dependency,
forbidden-path, migration, and source-bundle checks before asking for final
confirmation.

## Current Limitations

- Fresh installations are not supported by the Quattro preview.
- Only `apple,j314s` has completed the full validation sequence.
- The release is experimental and published as a GitHub prerelease.
- Parallels, virtual machines, and non-Asahi ARM systems are unsupported.
- Downgrading from Quattro is not supported; use backups for recovery.

## Releases And Development

- [Apple Silicon Quattro preview release](https://github.com/maralcbr/omarchy-pkgs/releases/tag/asahi-quattro-bf71823f)
- [`dev` source branch](https://github.com/maralcbr/omarchy-mx-mac/tree/dev)
- [`asahi-quattro` package branch](https://github.com/maralcbr/omarchy-pkgs/tree/asahi-quattro)
- [Issues](https://github.com/maralcbr/omarchy-mx-mac/issues)
- [Discussions](https://github.com/maralcbr/omarchy-mx-mac/discussions)

`main` remains the stable integration branch. Apple Silicon Quattro changes are
developed and validated on `dev`, then packaged from an immutable source commit.
The first release bundle is pinned to source commit `bf71823f`.

## Roadmap

- Collect validation reports from the exact supported model
- Add explicit support only for Apple Silicon models tested end to end
- Automate reproducible package release and verification workflows
- Design a separate, safe fresh-install path without replacing Asahi platform
  repositories, kernels, or boot configuration

## Repository Name

The repository is moving from `maralcbr/omarchy-mac` to
`maralcbr/omarchy-mx-mac`. The Omarchy Mac product and existing command names
remain unchanged for compatibility. GitHub redirects existing clone and web
URLs, but legacy Git checkouts can update their remote explicitly:

```bash
git -C ~/.local/share/omarchy remote set-url origin \
  https://github.com/maralcbr/omarchy-mx-mac.git
```

See the operational [rename plan](REPOSITORY_RENAME_PLAN.md) for integration
and rollback details.

## Support

Search existing issues before opening a new one. Include the output of:

```bash
uname -a
cat /proc/device-tree/model 2>/dev/null
tr '\0' '\n' </proc/device-tree/compatible 2>/dev/null
pacman -Q linux-asahi networkmanager iwd omarchy-dev omarchy-settings-dev
pacman-conf --repo-list
NetworkManager --print-config
```

Do not include passwords, Wi-Fi credentials, private keys, or complete network
connection profiles.

## Acknowledgements

Thanks to Asahi Linux and Asahi Alarm for enabling Linux on Apple Silicon, DHH
and the Omarchy contributors for Omarchy, Malik NA for the original Omarchy Mac
work, and everyone who has tested and improved the Apple Silicon path.

## License

Omarchy is released under the [MIT License](LICENSE).
