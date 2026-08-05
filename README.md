![Omarchy MX Mac](docs/images/omarchy-mx-mac-hero.png)

# Omarchy Mac on Apple Silicon

Run Omarchy on Apple Silicon through Arch Linux ARM and Asahi Linux.

[![License](https://img.shields.io/github/license/maralcbr/omarchy-mx-mac)](LICENSE)
[![Stars](https://img.shields.io/github/stars/maralcbr/omarchy-mx-mac?style=social)](https://github.com/maralcbr/omarchy-mx-mac/stargazers)

This project currently offers two paths:

| Version | Status | Installation |
| --- | --- | --- |
| Omarchy `3.8.4` | Recommended stable version | Fresh installation on Asahi Arch Minimal |
| Omarchy Quattro | Experimental `quattro` preview | Upgrade from an existing working Omarchy Mac installation |

> [!NOTE]
> This project is currently running on and tested with a 14-inch 2021 MacBook
> Pro with M1 Pro (`apple,j314s`). Apple Silicon support still depends on the
> upstream Asahi Linux support available for each model.

## Before You Begin

- Back up macOS and important Linux data.
- Review the [Asahi Linux device support](https://asahilinux.org/fedora/#device-support)
  for your Mac.
- Keep at least 50 GB free on the internal SSD; 100 GB is recommended.
- Use AC power and a reliable Internet connection during installation.
- Expect model-specific limitations around external displays, speakers,
  cameras, power management, or other hardware.

This project is not intended for Parallels, virtual machines, or non-Asahi ARM
systems.

## Install Stable Omarchy 3.8.4

This is the recommended installation. The instructions pin the repository to
Mac release `v3.8.4-mac.1`, which is based on Omarchy `3.8.4`.

### 1. Install Asahi Arch Minimal

From macOS Terminal, run the Asahi Alarm installer:

```bash
curl https://asahi-alarm.org/installer-bootstrap.sh | sh
```

Follow the installer prompts and select **Asahi Arch Minimal**. Allocate enough
space for Linux, finish the installation, and boot into the new Arch system.

### 2. Prepare Arch Linux

Sign in as `root` using the credentials provided by the Asahi installer. If
networking is not active, connect through NetworkManager:

```bash
nmtui
```

Update the system and install Git:

```bash
pacman -Syu --needed git
```

### 3. Download The Stable Mac Release

Clone the pinned stable release instead of the moving `main` branch:

```bash
mkdir -p /root/.local/share
git clone --branch v3.8.4-mac.1 --depth 1 \
  https://github.com/maralcbr/omarchy-mx-mac.git \
  /root/.local/share/omarchy
```

### 4. Run The Stable Bootstrap

Keep the repository and version pin while the bootstrap creates the regular
user installation:

```bash
OMARCHY_REPO=maralcbr/omarchy-mx-mac \
OMARCHY_REF=v3.8.4-mac.1 \
bash /root/.local/share/omarchy/bootstrap.sh
```

The bootstrap will:

- Install required system packages and the `yay` AUR helper
- Create or configure a regular user with sudo access
- Clone the same stable tag into `~/.local/share/omarchy`
- Run the Omarchy Mac installer for that user

Enter the requested username and passwords carefully. Do not interrupt package
transactions.

### 5. Reboot And Check The Desktop

After the installer completes successfully:

```bash
reboot
```

Confirm that the display, keyboard, touchpad, Wi-Fi, audio, brightness, and
power controls work before making additional changes.

Verify the installed Omarchy Mac version:

```bash
cat ~/.local/share/omarchy/version
```

Expected output:

```text
3.8.4-mac.1
```

## Optional: Install Omarchy Quattro

> [!WARNING]
> Quattro is not the default or recommended installation. It is an experimental,
> one-way upgrade for adventurous users who understand the risk and are willing
> to recover from backups if it fails.

The Quattro preview is developed on the [`quattro` branch](https://github.com/maralcbr/omarchy-mx-mac/tree/quattro).
Do not clone `quattro` and run `install.sh` as a fresh installer. The reviewed
path uses a checksummed six-package aarch64 bundle built from `quattro` source
commit `6f5ac5a0`.

### Quattro Support Boundary

The current public Quattro bootstrap accepts only the machine used for complete
validation:

| Component | Validated configuration |
| --- | --- |
| Model | MacBook Pro 14-inch, 2021 |
| SoC | Apple M1 Pro |
| Device tree | `apple,j314s` |
| Architecture | `aarch64` |
| Kernel | `linux-asahi` |
| Bootloader | GRUB |
| Wi-Fi backend | NetworkManager with iwd |

Validation on this MacBook Pro included the real Quattro upgrade, a complete
`omarchy update`, two reboots, suspend and resume, Wi-Fi, DNS, audio,
microphone, camera, brightness, and power profiles.

Other M1 Pro configurations and other Apple Silicon models are intentionally
rejected until they complete equivalent testing.

### Quattro Requirements

- The exact `apple,j314s` MacBook Pro described above
- An existing, working Omarchy Mac installation
- Arch Linux ARM and the Asahi repositories still configured
- `linux-asahi`, `networkmanager`, and `iwd` installed
- NetworkManager using `wifi.backend=iwd`
- A current backup and preferably Ethernet available

Back up important data and, at minimum, `/boot`, `/etc/pacman.conf`,
`/etc/pacman.d`, `/etc/NetworkManager`, and `~/.local/state/omarchy`.

### 1. Download And Verify Quattro

Run these commands as the regular Omarchy user, not as root:

```bash
mkdir -p ~/Downloads/omarchy-quattro
cd ~/Downloads/omarchy-quattro

release=https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-quattro-6f5ac5a0
curl -fLO "$release/install-asahi-quattro"
curl -fLO "$release/SHA256SUMS"
sha256sum --ignore-missing --check SHA256SUMS
```

Verify the complete release without changing the system:

```bash
bash install-asahi-quattro --verify-only
```

A successful verification ends with:

```text
Verified asahi-quattro-6f5ac5a0 for the tested apple,j314s MacBook Pro.
```

### 2. Run The Quattro Upgrade

Start the interactive upgrade only after verification succeeds:

```bash
bash install-asahi-quattro
```

The bootstrap and upgrader verify the hardware, Asahi repositories, networking
backend, package identities, architectures, checksums, source bundle, migration
policy, and forbidden boot paths before mutation. The upgrader also creates a
root-owned recovery backup.

Do not reboot if the upgrade reports an error. Save the terminal output and
open an issue before proceeding.

### 3. Verify Quattro After Reboot

After a successful upgrade and reboot:

```bash
uname -r
pacman -Q linux-asahi omarchy-dev omarchy-settings-dev networkmanager iwd
NetworkManager --print-config | grep 'wifi.backend=iwd'
nmcli device status
omarchy-migrate --pending
```

The expected Quattro packages for this preview are:

```text
omarchy-dev 4.0.0.r5871.g6f5ac5a-1
omarchy-settings-dev 4.0.0.r5871.g6f5ac5a-1
```

## Troubleshooting

### Network Is Unavailable

Inspect NetworkManager without assuming a fixed interface name:

```bash
nmcli device status
nmcli device wifi list
sudo systemctl restart NetworkManager
sudo journalctl -u NetworkManager -b
```

### An Installation Or Upgrade Failed

- Do not reboot during or after a failed package transaction.
- Preserve the complete terminal output.
- Check `/var/log/pacman.log` and the backup path printed by the installer.
- Open a verified bug report with hardware and package information.

## Releases And Support

- [Stable `v3.8.4-mac.1` source](https://github.com/maralcbr/omarchy-mx-mac/tree/v3.8.4-mac.1)
- [Quattro prerelease](https://github.com/maralcbr/omarchy-pkgs/releases/tag/asahi-quattro-6f5ac5a0)
- [`quattro` source branch](https://github.com/maralcbr/omarchy-mx-mac/tree/quattro)
- [Issues](https://github.com/maralcbr/omarchy-mx-mac/issues)
- [Discussions](https://github.com/maralcbr/omarchy-mx-mac/discussions)

When requesting support, include:

```bash
uname -a
cat /proc/device-tree/model 2>/dev/null
tr '\0' '\n' </proc/device-tree/compatible 2>/dev/null
pacman-conf --repo-list
```

Never post passwords, Wi-Fi credentials, private keys, or complete connection
profiles.

## Repository Name

The repository was renamed from `maralcbr/omarchy-mac` to
`maralcbr/omarchy-mx-mac`. GitHub redirects legacy repository and Git URLs, and
a compatibility shim preserves the old GitHub Pages `boot.sh` URL.

Legacy installations can update their remote explicitly:

```bash
git -C ~/.local/share/omarchy remote set-url origin \
  https://github.com/maralcbr/omarchy-mx-mac.git
```

## Acknowledgements

Thanks to Asahi Linux and Asahi Alarm for enabling Linux on Apple Silicon, DHH
and the Omarchy contributors for Omarchy, Malik NA for the original Omarchy Mac
work, and everyone testing the Apple Silicon path.

## License

Omarchy is released under the [MIT License](LICENSE).
