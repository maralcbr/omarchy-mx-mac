![Omarchy MX Mac](docs/images/omarchy-mx-mac-hero.png)

# Omarchy for Apple Silicon Macs

Run Omarchy on Apple Silicon through Arch Linux ARM and Asahi Linux.

[![License](https://img.shields.io/github/license/maralcbr/omarchy-mx-mac)](LICENSE)
[![Stars](https://img.shields.io/github/stars/maralcbr/omarchy-mx-mac?style=social)](https://github.com/maralcbr/omarchy-mx-mac/stargazers)

Read the **[Omarchy MX Mac manual](https://maralcbr.github.io/omarchy-mx-mac/)** for
installation, channels, the architecture of the fork and how it is tested. See
the [changelog](CHANGELOG.md) for release history and validation notes.

Omarchy 4 (Quattro) is the maintained release.

| What you have | What to do |
| --- | --- |
| A MacBook Pro 14" M1 Pro or 16" M2 Max with no Omarchy on it | Download the app below and install; it opens on **Stable**. Run `omarchy update` afterwards. |
| Any other Mac | Not admitted by the current image; the app refuses it before touching the disk. |
| An existing Omarchy 4 install | Run `omarchy update`. |
| An existing Omarchy 3 install | Run `omarchy update`. It moves you to Omarchy 4. |

> [!NOTE]
> **Stable and RC install the same image today.** On 2026-09-23 the RC image
> (`os-v4.0.3-mac.5.20260923-rc`: Aurora kernel, Limine boot menu) was promoted
> to Stable. The channels now differ only in the kernel lane the Mac follows
> afterwards. The Aurora kernel (`aurora-silicon/linux`) is pinned to a commit
> qualified on the 14-inch M1 Pro and the 16-inch M2 Max, and the image admits
> only those two models.
>
> A Mac keeps the kernel family it was installed with: a Mac installed from the
> earlier Asahi stable image stays on Asahi, and an Aurora Mac can move only
> between the Aurora Stable and RC lanes.

<details>
<summary>Version numbers</summary>

Two things carry versions here, and they do not move together:

- **Packages** — the current stable version is `4.0.4-mac.1`. This is what
  `omarchy update` gives you, and it advances with every release.
- **Fresh-install images** — what the macOS app writes to disk. Currently
  `os-v4.0.3-mac.5.20260923-rc` on both channels (Aurora kernel, Limine). It
  already carries Omarchy 4.0.4 (`4.0.4.r7069.g59ee15f-1`); the `4.0.3` in its
  tag is a naming slip in the signed catalog, not the version inside. Images are
  rebuilt only when they need to be, and the first `omarchy update` after an
  install brings the Mac to the current packages.

The `-mac.N` suffix counts Mac builds of one upstream release; it does not name a
channel or a kernel. A higher suffix is a later Mac build, not a newer Omarchy.

Omarchy `3.8.4-mac.4` is the last Omarchy 3 release. It is no longer developed;
existing installations update to Omarchy 4 in place.

</details>

## Download For Apple Silicon

Download the installer package, open it, and launch **Omarchy MX Mac Installer**
from Applications.

**[Download Omarchy MX Mac Installer for macOS](https://downloads.aicodelabs.com.au/installer/stable/Omarchy-MX-Mac-Installer.pkg)**

That link always serves the current installer (2.0.9 today), signed with
Developer ID, notarized by Apple, and stapled. It opens on **Stable** at every
launch; choose **Release candidate** from *Release Channel* in the menu bar
before installing to follow the RC kernel lane instead. It fetches the latest signed release from
the selected channel each time you prepare an installation. Matching cached files are verified and
reused instead of downloaded again. The package also installs the app's
privileged helper, which performs the disk work.

The owner confirmed an end-to-end installation on the M2 Max with an earlier
installer and image. The current image, `os-v4.0.3-mac.5.20260923-rc`, passed VM
acceptance but has not had a physical install recorded yet. The app also saves
credential-free diagnostic logs across reboots in
`~/Library/Logs/Omarchy MX Mac Installer/` and root-worker diagnostics in
`/var/db/com.omarchy.mx.installer/diagnostics/`.

You can verify the downloaded package before opening it with:

```bash
pkgutil --check-signature ~/Downloads/Omarchy-MX-Mac-Installer.pkg
spctl -a -vv -t install ~/Downloads/Omarchy-MX-Mac-Installer.pkg
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
- Native Arch Linux ARM with the Aurora kernel (`linux-aurora`) on new installs,
  `linux-asahi` on Macs installed from the earlier Asahi image, Asahi firmware,
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
- Kernel-aware updates that follow the Mac's lane and offer a reboot when a new
  kernel is installed.

Hardware support depends on Asahi Linux and the Aurora kernel. The current image
admits only the MacBook Pro 14" M1 Pro and 16" M2 Max; Macs installed from the
earlier Asahi image cover more M1 and M2 models.

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

The current release is **Omarchy MX Mac 4.0.4-mac.1**, based on upstream
Omarchy 4.0.4. Both installer channels write signed image
`os-v4.0.3-mac.5.20260923-rc` (Aurora kernel, Limine boot menu), which carries
the 4.0.4 runtime; it was promoted from Release candidate to **Stable** on
2026-09-23. Existing Macs receive 4.0.4 through `omarchy update`. Macs installed
from the earlier Asahi Stable image, `os-v4.0.3-mac.1.20260913`, keep the Asahi
kernel.

[Stable packages](https://github.com/maralcbr/omarchy-pkgs/releases/tag/asahi-packages-stable-2949b88ccfc303e3c423106eafa68c9088ab6eea)
and [runtime channel 56](https://github.com/maralcbr/omarchy-pkgs/releases/tag/asahi-quattro-channel-56)
carry the `4.0.4.r7069.g59ee15f-1` runtime and settings embedded in the image.
The app follows the latest signed catalog for the channel you select; cached
files are reused only when their size and SHA-256 match that catalog.

See [4.0.4-mac.1 release notes](docs/releases/v4.0.4-mac.1.md).

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

- [Omarchy MX Mac manual](https://maralcbr.github.io/omarchy-mx-mac/)
- [Latest product release and validation notes](https://github.com/maralcbr/omarchy-mx-mac/releases/latest)
- [Installer download (Stable)](https://downloads.aicodelabs.com.au/installer/stable/Omarchy-MX-Mac-Installer.pkg)
- [Current runtime channel 56](https://github.com/maralcbr/omarchy-pkgs/releases/tag/asahi-quattro-channel-56) and [package channel 13](https://github.com/maralcbr/omarchy-pkgs/releases/tag/asahi-packages-channel-13)
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
