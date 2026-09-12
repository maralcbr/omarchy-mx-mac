![Omarchy MX Mac](docs/images/omarchy-mx-mac-hero.png)

# Omarchy for Apple Silicon Macs

Run Omarchy on Apple Silicon through Arch Linux ARM and Asahi Linux.

[![License](https://img.shields.io/github/license/maralcbr/omarchy-mx-mac)](LICENSE)
[![Stars](https://img.shields.io/github/stars/maralcbr/omarchy-mx-mac?style=social)](https://github.com/maralcbr/omarchy-mx-mac/stargazers)

See the [changelog](CHANGELOG.md) for release history and validation notes.

Omarchy 4 (Quattro) is the maintained release:

| Version | Status | Installation |
| --- | --- | --- |
| Omarchy `4.0.3-mac.1` | Prepared update (unpublished) | Accepted test candidate; qualification and release details below |
| Omarchy `4.0.2-mac.1` | Current RC fresh-install image | Install from macOS using the app below |
| Omarchy `3.8.4-mac.4` | Legacy | Existing installations can update to Omarchy 4 |

> [!NOTE]
> The portable macOS app’s end-to-end installation was confirmed by the owner
> on an M2 Max. Runtime 4.0.3 passed a signed M1 Pro upgrade and a fresh generic
> ARM64 VM reboot with all 23 optional application installations passing. The
> final runtime pair has not been physically reboot-qualified. These are
> separate checks; they do not establish that a 4.0.3 fresh-install image has
> shipped. Hardware support depends on Asahi Linux support for each model.

## Download For Apple Silicon

Download the ZIP, extract it, and open **Omarchy MX Mac Installer.app**.
You can run it directly from Downloads; no PKG or Applications-folder installation is required.

**[Download Omarchy MX Mac Installer for macOS](https://downloads.aicodelabs.com.au/installer/previews/20260912-55064ca4f708/Omarchy-MX-Mac-Installer.zip)**

The app is signed with Developer ID, notarized by Apple, and stapled. It defaults
to **RC** and fetches the latest signed release from the selected existing channel
each time you prepare an installation. Matching cached files are verified and
reused instead of downloaded again. The existing installation screens remain the
same, and the privileged worker runs only for the installation session.

The owner confirmed an end-to-end installation on the M2 Max. The app also saves
credential-free diagnostic logs across reboots in
`~/Library/Logs/Omarchy MX Mac Installer/` and root-worker diagnostics in
`/var/db/com.omarchy.mx.installer/diagnostics/`.

After extracting the ZIP, you can verify the app with:

```bash
codesign --verify --deep --strict ~/Downloads/"Omarchy MX Mac Installer.app"
spctl -a -vv -t execute ~/Downloads/"Omarchy MX Mac Installer.app"
```

Gatekeeper should report `Notarized Developer ID`. The signing identity is
`MARCELO DE BARROS ALCANTARA (T2C384FJBD)`.

> [!IMPORTANT]
> Installers older than `2.0.0` were pinned to a single Omarchy release and
> stop working on 2026-12-01. Replace them with the download above.

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
- ARM64-native application paths and the Omarchy Quickshell desktop.
- Asahi-aware updates that track `linux-asahi` changes and offer a reboot when
  a new kernel is installed.

Hardware support still depends on Asahi Linux. Omarchy Mac has been tested on
M1, M2, and M3 systems; external displays, speakers, cameras, suspend, and
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

## Release Details

The RC app currently installs signed image `os-v4.0.2-mac.1.20260907` (Omarchy
4.0.2). It follows the latest signed catalog for the channel you select; cached
files are reused only when their size and SHA-256 match that catalog.

Omarchy 4.0.3 brings upstream security fixes and AI integrations, Apple Silicon
migration support, and ARM OpenClaw/Perplexity integration while retaining Mac
boot, package, and network protections. The signed runtime candidate passed its recorded qualification, but public
promotion is pending. The published runtime channel remains sequence 30. A
4.0.3 OS payload has not yet been built and qualified.

See [4.0.3 release notes](docs/releases/v4.0.3-mac.1.md).

## Alternative: Install From Asahi Arch Minimal

The signed installer takes a prepared Asahi Arch Minimal system directly to
Omarchy 4. It verifies immutable release metadata and never installs moving
`main` or an intermediate Omarchy 3 release.

The `vX.Y.Z-mac.N` tag records the product source and release notes. Installer,
channel, and package assets are published separately as immutable releases in
[`maralcbr/omarchy-pkgs`](https://github.com/maralcbr/omarchy-pkgs). The Linux bootstrap channel is separate from the macOS app’s RC image catalog.

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
pacman -Syu --needed curl gnupg linux-asahi-headers networkmanager iwd
```

### 3. Install The Latest Stable Mac Release

Download the stable-channel installer, verify its signing key and detached
signature, then run it. No downloaded code runs before these checks pass:

```bash
release=https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-quattro-channel-25
curl -fLO "$release/install-asahi-quattro"
curl -fLO "$release/install-asahi-quattro.sig"
curl -fLO https://raw.githubusercontent.com/maralcbr/omarchy-mx-mac/main/default/omarchy-release.gpg
test "$(gpg --show-keys --with-colons omarchy-release.gpg | awk -F: '$1 == "fpr" { print $10; exit }')" = \
  5983B1CA32CB778F4D74D24ECFF35022CA5B5959
gpgv --keyring ./omarchy-release.gpg install-asahi-quattro.sig install-asahi-quattro
bash install-asahi-quattro --verify-only
bash install-asahi-quattro --fresh
```

The former `asahi-quattro-channel` release is an immutable sequence-21
bootstrap and cannot be repointed. Existing sequence-21 installations must use
the same verified sequence-25 installer once before returning to normal
updates:

```bash
release=https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-quattro-channel-25
curl -fLO "$release/install-asahi-quattro"
curl -fLO "$release/install-asahi-quattro.sig"
curl -fLO https://raw.githubusercontent.com/maralcbr/omarchy-mx-mac/main/default/omarchy-release.gpg
test "$(gpg --show-keys --with-colons omarchy-release.gpg | awk -F: '$1 == "fpr" { print $10; exit }')" = \
  5983B1CA32CB778F4D74D24ECFF35022CA5B5959
gpgv --keyring ./omarchy-release.gpg install-asahi-quattro.sig install-asahi-quattro
bash install-asahi-quattro --verify-only --release-tag asahi-quattro-fe8d2bf8
bash install-asahi-quattro --yes --release-tag asahi-quattro-fe8d2bf8
omarchy update
```

The installer verifies and installs the exact immutable sequence-25 release;
the final `omarchy update` then uses numbered-channel discovery normally.

The signed installer will:

- Verify the stable channel, release descriptor, exact six-package manifest,
  checksums, signatures, architecture, and source identity before mutation
- Install the complete Apple Silicon package set without replacing
  `linux-asahi`, GRUB, or the Arch Linux ARM and Asahi repositories
- Install final Omarchy 4 directly, with no intermediate Omarchy 3 release
- Create the regular Omarchy user and run the Quattro system and user setup
- Build packages unavailable from Asahi repositories from the package-source
  commit pinned by the signed release
- Configure NetworkManager with iwd while preserving the Asahi boot stack

Enter the requested username and passwords carefully. Do not interrupt package
transactions.

### 4. Reboot Into Omarchy 4

After the installer completes successfully:

```bash
reboot
```

Confirm that the display, keyboard, touchpad, Wi-Fi, audio, brightness, and
power controls work. Future releases are delivered through `omarchy update`.

### Stable Support Boundary

The complete automated release regression runs on:

| Component | Validated configuration |
| --- | --- |
| Model | MacBook Pro 14-inch, 2021 |
| SoC | Apple M1 Pro |
| Device tree | `apple,j314s` |
| Architecture | `aarch64` |
| Kernel | `linux-asahi` |
| Bootloader | GRUB |
| Wi-Fi backend | NetworkManager with iwd |

Validation includes a real six-package installation and reboot, package
integrity and protected-file checks, Wi-Fi, DNS, audio, microphone, camera,
brightness, power profiles, and desktop screenshots. M1, M2, and M3 Macs have
also been tested, with model-specific capabilities determined by Asahi Linux.

### Final Verification

```bash
uname -r
pacman -Q linux-asahi omarchy-dev omarchy-settings-dev networkmanager iwd
NetworkManager --print-config | grep 'wifi.backend=iwd'
nmcli device status
omarchy-migrate --pending
cat /usr/share/omarchy/version
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

### Quickshell Fails After A Partial Update

Do not replace the signed `quickshell-git` package with `quickshell` or rebuild
it from the AUR. Those workarounds move the machine outside the validated Apple
Silicon package bundle and can block later updates.

Switch to a TTY, preserve the package and journal evidence, then use the normal
signed updater:

```bash
pacman -Q quickshell-git qt6-base 2>&1 || true
pacman -Qm | grep -E '^quickshell' || true
journalctl --user -b | grep -i quickshell || true
omarchy update
```

If the update fails, do not reboot or remove packages manually. Preserve the
complete output and open a verified bug report with the commands above.

### An Installation Or Upgrade Failed

- Do not reboot during or after a failed package transaction.
- Preserve the complete terminal output.
- Check `/var/log/pacman.log` and the backup path printed by the installer.
- Open a verified bug report with hardware and package information.

## Releases And Support

- [Latest product release and validation notes](https://github.com/maralcbr/omarchy-mx-mac/releases/latest)
- [Current signed installer and package channel](https://github.com/maralcbr/omarchy-pkgs/releases/tag/asahi-quattro-channel-25)
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

## Contributors

| Contributor | Contact |
| --- | --- |
| Yann Renard | [yannrenard1025@gmail.com](mailto:yannrenard1025@gmail.com) |

## Acknowledgements

Thanks to Asahi Linux and Asahi Alarm for enabling Linux on Apple Silicon, DHH
and the Omarchy contributors for Omarchy, Malik NA for the original Omarchy Mac
work, and everyone testing the Apple Silicon path.

## License

Omarchy is released under the [MIT License](LICENSE).
