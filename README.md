# Omarchy

Omarchy is a beautiful, modern & opinionated Linux distribution by DHH.

Read more at [omarchy.org](https://omarchy.org).

## Apple Silicon Beta

This fork currently supports one beta path: upgrading an existing,
working `omarchy-mac` installation on the maintainer's MacBook Pro with M1 Pro.
Other Apple Silicon models and fresh Asahi installations are untested.

The upgrade requires a six-package aarch64 bundle built from the matching
`quattro` source commit and accompanied by `asahi-quattro-bundle.manifest`. The
upgrade preserves the Arch Linux ARM repositories, `linux-asahi`, GRUB, and the
NetworkManager iwd backend. It fails closed when a package, migration, or
network configuration has not been reviewed for Apple Silicon.

Before upgrading, keep Ethernet available and back up `/boot`, `/etc/pacman.conf`,
`/etc/pacman.d`, `/etc/NetworkManager`, and `~/.local/state/omarchy`. Do not
reboot if the upgrade reports an error. This repository is not a fresh Asahi
installer.

The current public bundle is limited to the tested 14-inch 2021 MacBook Pro
with M1 Pro (`apple,j314s`). It was built from source commit `d3c9064f` as
`omarchy-dev` and `omarchy-settings-dev` version
`4.0.0.r5890.gd3c9064-1`. Download and checksum the bootstrap using the
[release instructions](https://github.com/maralcbr/omarchy-pkgs/blob/asahi-quattro/README.md#apple-silicon-quattro-beta),
or inspect the [exact prerelease](https://github.com/maralcbr/omarchy-pkgs/releases/tag/asahi-quattro-d3c9064f).

## Apple Silicon Adaptations

This branch carries the Quattro desktop onto the tested Asahi platform while
preserving its native `linux-asahi` kernel, Arch Linux ARM and Asahi package
repositories, GRUB boot path, and NetworkManager `iwd` backend. The upgrade
also retains MacBook keyboard-backlight, lid, display-brightness, battery, and
Apple GPU integration. Apple-specific migration policy fails closed when new
upstream system changes have not been reviewed for the platform.

## Mac Screenshot Shortcuts

These additional shortcuts include `Control` so Quattro's existing
`Command+Shift+3/4/5` workspace controls are not changed. On Apple keyboards,
Command is Hyprland's `SUPER` modifier.

| Shortcut | Action |
| --- | --- |
| `Control+Shift+Command+3` | Capture the focused display |
| `Control+Shift+Command+4` | Select a region or click a window to capture it |
| `Control+Shift+Command+5` | Open screenshot and screen-recording controls |

## License

Omarchy is released under the [MIT License](https://opensource.org/licenses/MIT).
