---
title: Upstream and contributing
description: How the fork relates to Omarchy, Asahi, Aurora and Hyprland, and where a change belongs.
section: Reference
---

The fork's rule is that a change lives as close to upstream as it can. Every layer the fork touches has an upstream, and each has its own way of taking changes.

| Layer | Upstream | How changes flow |
| --- | --- | --- |
| Desktop runtime | [omacom/omarchy](https://github.com/omacom/omarchy) | Fork merges upstream regularly. General fixes are sent upstream; Apple-specific code stays behind `omarchy-hw-apple-silicon`. |
| Packages | [omacom/omarchy-pkgs](https://github.com/omacom/omarchy-pkgs) | aarch64 PKGBUILDs are contributed directly, as plain recipes with `arch=(aarch64)`. The fork's lanes, planner and image builder stay in the fork. |
| Kernel | [aurora-silicon/linux](https://github.com/aurora-silicon/linux), branch `aurora-wip` | Pull requests from the fork's kernel tree. The first two, a display crossbar selector fix and a stale DisplayPort link fix, are merged. |
| Boot, firmware, engine | [Asahi Linux](https://asahilinux.org) | m1n1 and `asahi-scripts` used unmodified. U-Boot is built with a silent console. The installer engine is Asahi's installer repackaged with downstream patches (`v0.9.2-omarchy.17`). |
| Compositor | [hyprwm/Hyprland](https://github.com/hyprwm/Hyprland), [hyprwm/aquamarine](https://github.com/hyprwm/aquamarine) | Issues and patches filed by the maintainer. |

## What stays in the fork

- The macOS installer app and its release tooling.
- The Mac image builder, the release lanes and the acceptance harness.
- `omarchy-mac-boot` and the Apple Silicon hardware fixes.
- The `linux-aurora` lane recipes and their pins.
- The signed channel model: catalogs, trust root, immutable releases.

## Naming

Identifiers the fork owns are named `mac`, not `asahi`: `omarchy-mac-boot`, `build-mac-image`, `mac-image-<n>`. Names that belong to the Asahi project keep their name: `linux-asahi`, `asahi-scripts`, `[asahi-alarm]`, `uboot-asahi`. Older `asahi-quattro` release names remain because their releases are immutable.

## Contributing

- **Bugs**: open an issue on [omarchy-mx-mac](https://github.com/maralcbr/omarchy-mx-mac/issues) with the details from [Hardware support]({{page:hardware}}).
- **Runtime changes**: pull requests against `main` on omarchy-mx-mac. Anything Apple-specific must run behind `omarchy-hw-apple-silicon` and come with a migration if it changes installed systems.
- **Packages**: pull requests against `asahi-quattro` on omarchy-pkgs. A recipe that every aarch64 user could want should go to omacom/omarchy-pkgs instead.
- **Reviews**: designs and code are reviewed before merge, and boot-critical changes need hardware evidence from a test Mac.

## Licence

Omarchy MX Mac is released under the same MIT licence as Omarchy. The Asahi installer engine, m1n1 and U-Boot keep their own licences.
