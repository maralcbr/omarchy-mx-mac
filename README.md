![Omarchy MX Mac](docs/images/omarchy-mx-mac-hero.png)

# Omarchy Mac on Apple Silicon

Run Omarchy on Apple Silicon through Arch Linux ARM and Asahi Linux.

[![License](https://img.shields.io/github/license/maralcbr/omarchy-mx-mac)](LICENSE)
[![Stars](https://img.shields.io/github/stars/maralcbr/omarchy-mx-mac?style=social)](https://github.com/maralcbr/omarchy-mx-mac/stargazers)

This project currently offers two paths:

| Version | Status | Installation |
| --- | --- | --- |
| Omarchy `3.8.4` | Recommended stable version | Fresh installation on Asahi Arch Minimal |
| Omarchy Quattro | Quattro Beta | Upgrade from an existing working Omarchy Mac installation |

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

## Fork Features

Omarchy MX Mac keeps Omarchy's desktop experience while adapting installation,
hardware integration, and updates for Apple Silicon:

- Bootstrap from a fresh Asahi Arch Minimal installation into a complete
  Omarchy desktop and regular user account.
- Native Arch Linux ARM and Asahi stack with `linux-asahi`, Asahi firmware,
  regional ARM mirrors, and the dedicated Asahi package repository.
- Hardware-accelerated Apple GPU graphics through the Mesa `vulkan-asahi`
  driver.
- MacBook keyboard-backlight controls, Apple SMC lid handling, display
  brightness integration, and low-battery notifications.
- Widevine support for DRM-protected browser streaming when the package is
  available from the configured Asahi repositories.
- Optional Steam installation through the Asahi ARM64/FEX compatibility
  environment.
- ARM64-native application paths, including Cursor, plus a Fuzzel-based app
  launcher suited to the platform.
- Asahi-aware updates that track `linux-asahi` changes and offer a reboot when
  a new kernel is installed.

Hardware support still depends on Asahi Linux. The stable release is tested on
the MacBook listed above; external displays, speakers, cameras, suspend, and
power management can vary by model.

## Mac Screenshot Shortcuts

The fork adds familiar number-row screenshot shortcuts with `Control` included
so Omarchy's existing `Command+Shift+3/4/5` workspace controls remain intact.
On Apple keyboards, the Command key is Hyprland's `SUPER` modifier.

| Shortcut | Action |
| --- | --- |
| `Control+Shift+Command+3` | Capture the focused display |
| `Control+Shift+Command+4` | Select a region or click a window to capture it |
| `Control+Shift+Command+5` | Open screenshot and screen-recording controls |

The existing Print Screen shortcuts and all Omarchy workspace bindings remain
available.

## Install Stable Omarchy

This is the recommended installation. The signed installer resolves the latest
validated, immutable Omarchy Mac release. It never installs moving `main`.

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

Update the system and install the release verification tools:

```bash
pacman -Syu --needed curl git gnupg
```

### 3. Install The Latest Stable Mac Release

Download and verify the installer from the latest stable GitHub release:

```bash
mkdir -p /root/omarchy-mx-mac-install
cd /root/omarchy-mx-mac-install
release=https://github.com/maralcbr/omarchy-mx-mac/releases/latest/download
curl -fLO "$release/install-omarchy-mx-mac"
curl -fLO "$release/install-omarchy-mx-mac.sig"
key_home=$(mktemp -d)
chmod 700 "$key_home"
GNUPGHOME="$key_home" gpg --keyserver hkps://keys.openpgp.org \
  --recv-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571
test "$(GNUPGHOME="$key_home" gpg --with-colons --fingerprint \
  40DFB630FF42BCFFB047046CF0134EE680CAC571 | awk -F: '$1 == "fpr" { print $10; exit }')" = \
  40DFB630FF42BCFFB047046CF0134EE680CAC571
GNUPGHOME="$key_home" gpg --verify install-omarchy-mx-mac.sig install-omarchy-mx-mac
rm -rf "$key_home"
bash install-omarchy-mx-mac
```

The signed installer and bootstrap will:

- Install required system packages and the `yay` AUR helper
- Create or configure a regular user with sudo access
- Verify the release signature against the pinned Omarchy signing fingerprint
- Clone the exact signed stable tag into `~/.local/share/omarchy`
- Run the Omarchy Mac installer for that user

Enter the requested username and passwords carefully. Do not interrupt package
transactions.

### 4. Reboot And Check The Desktop

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

Future validated releases are offered during `omarchy update`. The updater
shows the current and target releases and asks before changing immutable tags.

## Optional: Install Omarchy Quattro

> [!WARNING]
> Quattro is not the default or recommended installation. It is a Beta,
> one-way upgrade for adventurous users who understand the risk and are willing
> to recover from backups if it fails.

The Quattro Beta is developed on the [`quattro` branch](https://github.com/maralcbr/omarchy-mx-mac/tree/quattro).
Do not clone `quattro` and run `install.sh` as a fresh installer. The reviewed
path uses a signed six-package aarch64 bundle built from a validated `quattro`
source commit.

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

Validation on this MacBook Pro included a real six-package installation and
reboot, package integrity and protected-file checks, Wi-Fi, DNS, audio,
microphone, camera, brightness, power profiles, and desktop screenshots.

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

release=https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-quattro-channel
curl -fLO "$release/install-asahi-quattro"
curl -fLO "$release/install-asahi-quattro.sig"
gpgv --keyring /usr/share/pacman/keyrings/omarchy.gpg \
  install-asahi-quattro.sig install-asahi-quattro
```

Verify the complete release without changing the system:

```bash
bash install-asahi-quattro --verify-only
```

A successful verification ends with:

```text
Verified asahi-quattro-COMMIT for the tested apple,j314s MacBook Pro.
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

The expected Quattro packages for this Beta are:

```text
omarchy-dev 4.0.0.rRELEASE.gCOMMIT-1
omarchy-settings-dev 4.0.0.rRELEASE.gCOMMIT-1
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

- [Latest stable release](https://github.com/maralcbr/omarchy-mx-mac/releases/latest)
- [Latest signed Quattro channel](https://github.com/maralcbr/omarchy-pkgs/releases/tag/asahi-quattro-channel)
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
