# Omarchy

Omarchy is a beautiful, modern & opinionated Linux distribution by DHH.

Read more at [omarchy.org](https://omarchy.org).

## Apple Silicon Preview

This fork currently supports one experimental path: upgrading an existing,
working `omarchy-mac` installation on the maintainer's MacBook Pro with M1 Pro.
Other Apple Silicon models and fresh Asahi installations are untested.

The upgrade requires a six-package aarch64 bundle built from the matching
`dev` source commit and accompanied by `asahi-quattro-bundle.manifest`. The
upgrade preserves the Arch Linux ARM repositories, `linux-asahi`, GRUB, and the
NetworkManager iwd backend. It fails closed when a package, migration, or
network configuration has not been reviewed for Apple Silicon.

Before upgrading, keep Ethernet available and back up `/boot`, `/etc/pacman.conf`,
`/etc/pacman.d`, `/etc/NetworkManager`, and `~/.local/state/omarchy`. Do not
reboot if the upgrade reports an error. This repository is not a fresh Asahi
installer.

The first public bundle is limited to the tested 14-inch 2021 MacBook Pro with
M1 Pro (`apple,j314s`). Download and checksum the bootstrap using the
[pinned release instructions](https://github.com/maralcbr/omarchy-pkgs/tree/asahi-quattro#apple-silicon-quattro-preview).

## License

Omarchy is released under the [MIT License](https://opensource.org/licenses/MIT).
