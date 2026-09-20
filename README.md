![Omarchy MX Mac](docs/images/omarchy-mx-mac-hero.png)

# Omarchy for Apple Silicon Macs

Run Omarchy on Apple Silicon through Arch Linux ARM and Asahi Linux.

[![License](https://img.shields.io/github/license/maralcbr/omarchy-mx-mac)](LICENSE)
[![Stars](https://img.shields.io/github/stars/maralcbr/omarchy-mx-mac?style=social)](https://github.com/maralcbr/omarchy-mx-mac/stargazers)

See the [changelog](CHANGELOG.md) for release history and validation notes.

Omarchy 4 (Quattro) is the maintained release.

| What you have | What to do |
| --- | --- |
| A Mac with no Omarchy on it | Download the app below and install. It defaults to **Stable**. Run `omarchy update` afterwards. |
| A Mac you want on the Aurora kernel | Same app, choose **RC** in *Release Channel*. |
| An existing Omarchy 4 install | Run `omarchy update`. |
| An existing Omarchy 3 install | Run `omarchy update`. It moves you to Omarchy 4. |

> [!NOTE]
> **Stable vs RC is a kernel choice, not a quality ladder.** Stable installs the
> Asahi Linux kernel; its package candidate passed a native ARM64 VM
> installation, recovery, reboot, all 23 optional application installs, and
> completed-installer rerun checks. Hardware support follows Asahi Linux support
> for each model.
>
> RC installs the Aurora kernel (`aurora-silicon/linux`), pinned to a commit
> qualified on real hardware. That qualification was done on the 14-inch M1 Pro
> and the 16-inch M2 Max; other models are untested rather than excluded, so try
> RC on yours and report what you find.
>
> A Mac keeps the kernel it was installed with: an Asahi Mac stays on Stable and
> an Aurora Mac stays on RC. Pick the channel at install time.

<details>
<summary>Version numbers</summary>

Two things carry versions here, and they do not move together:

- **Packages** — the current stable version is `4.0.4-mac.1`. This is what
  `omarchy update` gives you, and it advances with every release.
- **Fresh-install images** — what the macOS app writes to disk. Currently
  `4.0.3-mac.1` (Stable, Asahi kernel) and `4.0.3-mac.2` (RC, Aurora kernel).
  Each image is rebuilt and re-qualified only when it needs to be, so images
  trail the package version. The first `omarchy update` after an install closes
  the gap.

The `-mac.N` suffix on an image names the build lane, not the maturity:
`-mac.1` and `-mac.2` are the same upstream Omarchy 4.0.3 built against
different kernels. A higher suffix is not a newer release.

Omarchy `3.8.4-mac.4` is the last Omarchy 3 release. It is no longer developed;
existing installations update to Omarchy 4 in place.

</details>

## Download For Apple Silicon

Download the ZIP, extract it, and open **Omarchy MX Mac Installer.app**.
You can run it directly from Downloads; no PKG or Applications-folder installation is required.

**[Download Omarchy MX Mac Installer for macOS](https://downloads.aicodelabs.com.au/installer/previews/20260918-e1b8abc05135/Omarchy-MX-Mac-Installer.zip)**

The app (version 2.0.5) is signed with Developer ID, notarized by Apple, and
stapled. It defaults to **Stable**; choose **RC** from *Release Channel* in the
menu bar to follow release candidates. It fetches the latest signed release from
the selected channel each time you prepare an installation. Matching cached files are verified and
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

Hardware support still depends on Asahi Linux. Omarchy Mac runs on M1 and M2
systems, and on M3 systems with GPU limitations. External displays, speakers,
cameras, suspend, and power management can vary by model.

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

The RC app currently installs signed image `os-v4.0.3-mac.1.20260913` (Omarchy
4.0.3, Asahi). It follows the latest signed catalog for the channel you select; cached
files are reused only when their size and SHA-256 match that catalog.

Omarchy 4.0.3 brings upstream security fixes and AI integrations, Apple Silicon
migration support, and ARM OpenClaw/Perplexity integration while retaining Mac
boot, package, and network protections. The signed runtime and packages are now
published to the shared Stable update feed. Existing Omarchy Macs receive them
through `omarchy update`.

[Stable packages](https://github.com/maralcbr/omarchy-pkgs/releases/tag/asahi-packages-stable-83973903b7deb9b56ce75f02b432fba0561d6293)
and [runtime channel 32](https://github.com/maralcbr/omarchy-pkgs/releases/tag/asahi-quattro-channel-32)
carry the accepted `4.0.3.r6962.ga67d7f7-1` runtime/settings pair embedded in
this RC image. The release includes greeter password masking and focus fixes,
Apple DRM readiness handling, and the initramfs static-device race fix.

See [4.0.3 release notes](docs/releases/v4.0.3-mac.1.md).

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
- [Current signed installer and package channel](https://github.com/maralcbr/omarchy-pkgs/releases/tag/asahi-quattro-channel-35)
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
