---
title: Hardware support
description: Which Macs are supported, what Asahi provides and Aurora adds, and the known issues.
section: Reference
---

Omarchy MX Mac runs the Aurora kernel, which builds on the Asahi Linux kernel. Hardware support is what Asahi provides, plus what Aurora adds on top. The fork qualifies each release on real Macs and records the evidence with the release. Nothing below claims more than what has been exercised.

Macs installed from the earlier Asahi stable image, before 2026-09-23, still run `linux-asahi`: they have what Asahi provides, without Aurora's additions, until they are migrated.

## Supported Macs

A Mac is admitted by its device-tree identifier, never by its marketing name. The
identifier is what the installer catalog lists and what the fork qualifies against, because
one marketing name can cover boards with different hardware. Read yours with:

```bash
cat /proc/device-tree/model
tr '\0' '\n' < /proc/device-tree/compatible
```

The catalog on both channels admits 22 identifiers today, every M1 and M2 model the
earlier Asahi image admitted: `apple,j274`, `j293`, `j313`, `j314s`, `j314c`, `j316s`,
`j316c`, `j375c`, `j375d`, `j413`, `j414s`, `j414c`, `j415`, `j416s`, `j416c`, `j456`,
`j457`, `j473`, `j474s`, `j475c`, `j475d` and `j493`. The Aurora kernel was qualified on
two of them, the MacBook Pro 14" M1 Pro (`apple,j314s`) and the MacBook Pro 16" M2 Max
(`apple,j416c`); the other 20 are admitted without their own hardware qualification. An
identifier that is not in the catalog is refused before anything on the disk is touched.

The current image admits no M3 or M4 Mac.

## Reference machines

| Machine | Role |
| --- | --- |
| MacBook Pro 14" 2021, M1 Pro, `apple,j314s` | Full regression on every release; when it is offline the M2 Max stands in, as for runtime channels 58 and 59. Aurora kernel, Limine integration testing. |
| MacBook Pro 16" 2023, M2 Max, `apple,j416c` | Multi-display work: five displays through HDMI and USB4. VM acceptance host for packages and images (images are built on GitHub). |

## What Asahi provides

Aurora builds on the Asahi Linux kernel, so everything Asahi supports on your chip works here. Its feature-support pages are the authoritative, current list:

- [M1 feature support](https://asahilinux.org/docs/platform/feature-support/m1/)
- [M2 feature support](https://asahilinux.org/docs/platform/feature-support/m2/)
- [Overview across chips](https://asahilinux.org/docs/platform/feature-support/overview/)

That covers the GPU, the internal display, keyboard, trackpad, Wi-Fi, Bluetooth, speakers and microphone, suspend, battery and one external display over HDMI. Anything marked work-in-progress there, Thunderbolt device support among them, is work-in-progress here too.

## What Aurora adds

| Area | Notes |
| --- | --- |
| Several external displays, USB4 / DisplayPort alt-mode | Five displays on the M2 Max |
| Variable refresh rate | |
| Camera (ISP) | |
| Always-on processor | |

New Aurora kernels reach `rc` first; `stable` carries the one rc qualified on hardware. See [Channels and updates]({{page:channels}}).

## How Omarchy sets it up

| Area | Notes |
| --- | --- |
| Apple GPU | Mesa `vulkan-asahi`, hardware acceleration. `llvmpipe` is a failed install. |
| Keyboard, backlight, trackpad | Early-loaded HID modules; media keys on the top row as in macOS (`fnmode=3`); MTP trackpads on M2 need the fork's fix |
| Wi-Fi | NetworkManager with the iwd backend. 5 GHz occasionally times out right after first boot; retry connects. |
| Speakers, microphone, headphones | WirePlumber convolver chain, `speakersafetyd` active |
| Suspend and resume | Verified per release from a local session |
| Battery, lid, power profiles | Apple SMC through the fork's integration |
| Widevine DRM in browsers | When the package is available from the Asahi repositories |
| Steam | Optional, through the Asahi FEX environment |

## Known issues

| Issue | Notes |
| --- | --- |
| Fullscreen window on a very wide display | Hyprland paints only a band of a fullscreen window on a 5120×1440 output next to a scaled internal display. Upstream Hyprland issue. |
| Fourth external display after HDMI unplug | A stale DisplayPort link on the M2 Max after unplugging HDMI; replug or reboot |
| Text console between Plymouth and the greeter | Cosmetic, a few seconds |

## Validation

Every release goes through the checklist in [apple-silicon-hardware-validation.md](https://github.com/maralcbr/omarchy-mx-mac/blob/main/docs/apple-silicon-hardware-validation.md): platform identity, desktop and graphics, networking, audio, power and suspend, update safety and snapshots. Boot-critical changes additionally require a cold boot on a test Mac, never a warm reboot, before the release proceeds.

## Reporting a problem

Include the output of:

```bash
uname -a
cat /proc/device-tree/model
tr '\0' '\n' </proc/device-tree/compatible
pacman-conf --repo-list
cat /var/lib/omarchy/apple-silicon-channel /usr/share/omarchy/apple-silicon-kernel
```

Never post passwords, Wi-Fi credentials, private keys or complete connection profiles. Issues go to [maralcbr/omarchy-mx-mac](https://github.com/maralcbr/omarchy-mx-mac/issues).
