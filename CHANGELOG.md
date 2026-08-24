# Changelog

Release notes for the maintained Apple Silicon line are version-controlled in
[`docs/releases/`](docs/releases/). GitHub Releases publish those files
verbatim.

## [4.0.0-mac.15] - 2026-08-24

- Published and configured an immutable signed Apple Silicon package repository,
  restoring native package availability for supported Omarchy applications.
- Added continuous aarch64 package resolution and installation audits across
  every package manifest and optional transaction.
- Repaired UTF-8 locale generation, PipeWire realtime scheduling, and GNOME
  Keyring unlock for fresh and existing Apple Silicon installations.

[Release notes](docs/releases/v4.0.0-mac.15.md) | [Full diff](https://github.com/maralcbr/omarchy-mx-mac/compare/v4.0.0-mac.14...v4.0.0-mac.15)

## [4.0.0-mac.14] - 2026-08-24

- Added version-controlled release notes and a maintained Apple Silicon
  changelog.
- Validated parallel native-ARM package preparation, signed immutable package
  reuse, and GitHub Actions builder caching.
- Restricted package signing and release writes to the final protected publish
  job after exact six-package fan-in verification.

[Release notes](docs/releases/v4.0.0-mac.14.md) | [Full diff](https://github.com/maralcbr/omarchy-mx-mac/compare/v4.0.0-mac.13...v4.0.0-mac.14)

## [4.0.0-mac.13] - 2026-08-24

- Rebuilt `quickshell-git` against Qt 6.11.2 and raised its package release to
  ensure existing installations receive the ABI-compatible binary.
- Published signed Apple Silicon bundle sequence 17 from source commit
  `59c188fa`.
- Superseded `4.0.0-mac.12` after real-hardware reboot validation exposed the
  Quickshell/Qt ABI mismatch.

[Release notes](docs/releases/v4.0.0-mac.13.md) | [Full diff](https://github.com/maralcbr/omarchy-mx-mac/compare/v4.0.0-mac.12...v4.0.0-mac.13)

## [4.0.0-mac.12] - 2026-08-23

- Added complete optional-package transaction manifests shared by menu guards,
  tests, and CI.
- Added scheduled native-aarch64 package resolution, download, and AUR build
  validation.
- Extended the disposable Asahi VM to install and verify all 20 required
  optional transactions.

[Release notes](docs/releases/v4.0.0-mac.12.md) | [Full diff](https://github.com/maralcbr/omarchy-mx-mac/compare/v4.0.0-mac.11...v4.0.0-mac.12)

## [4.0.0-mac.11] - 2026-08-22

- Retired the legacy seamless-login service before enabling SDDM.
- Added migration repair for affected installations and corrected Quattro
  upgrade cleanup ordering.

[Release notes](docs/releases/v4.0.0-mac.11.md) | [Full diff](https://github.com/maralcbr/omarchy-mx-mac/compare/v4.0.0-mac.10...v4.0.0-mac.11)

## Historical Releases

- [4.0.0-mac.10](https://github.com/maralcbr/omarchy-mx-mac/compare/v4.0.0-mac.9...v4.0.0-mac.10) - 2026-08-21
- [4.0.0-mac.9](https://github.com/maralcbr/omarchy-mx-mac/compare/v4.0.0-mac.8...v4.0.0-mac.9) - 2026-08-20
- [4.0.0-mac.8](https://github.com/maralcbr/omarchy-mx-mac/compare/v4.0.0-mac.7...v4.0.0-mac.8) - 2026-08-20
- [4.0.0-mac.7](https://github.com/maralcbr/omarchy-mx-mac/compare/v4.0.0-mac.6...v4.0.0-mac.7) - 2026-08-19
- [4.0.0-mac.6](https://github.com/maralcbr/omarchy-mx-mac/compare/v4.0.0-mac.5...v4.0.0-mac.6) - 2026-08-17
- [4.0.0-mac.5](https://github.com/maralcbr/omarchy-mx-mac/compare/v4.0.0-mac.4...v4.0.0-mac.5) - 2026-08-16
- [4.0.0-mac.4](https://github.com/maralcbr/omarchy-mx-mac/compare/v4.0.0-mac.3...v4.0.0-mac.4) - 2026-08-16
- [4.0.0-mac.3](https://github.com/maralcbr/omarchy-mx-mac/compare/v4.0.0-mac.1...v4.0.0-mac.3) - 2026-08-15
- [4.0.0-mac.1](https://github.com/maralcbr/omarchy-mx-mac/compare/v3.8.4-mac.4...v4.0.0-mac.1) - 2026-08-15

[4.0.0-mac.13]: https://github.com/maralcbr/omarchy-mx-mac/releases/tag/v4.0.0-mac.13
[4.0.0-mac.14]: https://github.com/maralcbr/omarchy-mx-mac/releases/tag/v4.0.0-mac.14
[4.0.0-mac.15]: https://github.com/maralcbr/omarchy-mx-mac/releases/tag/v4.0.0-mac.15
[4.0.0-mac.12]: https://github.com/maralcbr/omarchy-mx-mac/releases/tag/v4.0.0-mac.12
[4.0.0-mac.11]: https://github.com/maralcbr/omarchy-mx-mac/releases/tag/v4.0.0-mac.11
