---
title: Hardware support
description: Which Macs are supported, what works on each kernel lane, and the known limitations.
section: Reference
---

Hardware support is the Asahi Linux project's, plus what the Aurora kernel adds. New installs on both channels get the Aurora kernel; Macs installed from the earlier Asahi stable image keep `linux-asahi`. The fork qualifies each release on real Macs and records the evidence with the release. Nothing below claims more than what has been exercised.

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
| MacBook Pro 14" 2021, M1 Pro, `apple,j314s` | Full regression on every release. Aurora kernel, Limine integration testing. |
| MacBook Pro 16" 2023, M2 Max, `apple,j416c` | Multi-display work: five displays through HDMI and USB4. VM acceptance host for packages and images (images are built on GitHub). |

## What works

<span class="status ok">works</span> on both kernels unless noted. <span class="status partial">Aurora only</span> needs the Aurora kernel, which every new install has; Macs on the legacy Asahi kernel lack it. The `stable` lane carries rc's hardware-qualified kernel, so both lanes have these; `rc` gets new kernels first. <span class="status wip">known issue</span> is tracked.

| Area | Status | Notes |
| --- | --- | --- |
| Apple GPU | <span class="status ok">works</span> | Mesa `vulkan-asahi`, hardware acceleration. `llvmpipe` is a failed install. |
| Internal display, brightness | <span class="status ok">works</span> | |
| Keyboard, backlight, trackpad | <span class="status ok">works</span> | Early-loaded HID modules; MTP trackpads on M2 need the fork's fix |
| Wi-Fi, Bluetooth | <span class="status ok">works</span> | NetworkManager with the iwd backend. 5 GHz occasionally times out right after first boot; retry connects. |
| Speakers, microphone, headphones | <span class="status ok">works</span> | WirePlumber convolver chain, `speakersafetyd` active |
| Suspend and resume | <span class="status ok">works</span> | Verified per release from a local session |
| Battery, lid, power profiles | <span class="status ok">works</span> | Apple SMC through the fork's integration |
| One external display | <span class="status ok">works</span> | HDMI on models that have it |
| Several external displays, USB4 / DisplayPort alt-mode | <span class="status partial">Aurora only</span> | Aurora kernel. Five displays on the M2 Max. |
| Variable refresh rate, camera (ISP), always-on processor | <span class="status partial">Aurora only</span> | Aurora kernel |
| Fullscreen window on a very wide display | <span class="status wip">known issue</span> | Hyprland paints only a band of a fullscreen window on a 5120×1440 output next to a scaled internal display. Upstream Hyprland issue. |
| Fourth external display after HDMI unplug | <span class="status wip">known issue</span> | A stale DisplayPort link on the M2 Max after unplugging HDMI; replug or reboot |
| Text console between Plymouth and the greeter | <span class="status wip">known issue</span> | Cosmetic, a few seconds |
| Widevine DRM in browsers | <span class="status ok">works</span> | When the package is available from the Asahi repositories |
| Steam | <span class="status ok">works</span> | Optional, through the Asahi FEX environment |

## What Asahi supports on your chip

Everything below the desktop is the Asahi Linux project's work, and the authoritative, current list of what each Apple chip supports is theirs:

- [M1 feature support](https://asahilinux.org/docs/platform/feature-support/m1/)
- [M2 feature support](https://asahilinux.org/docs/platform/feature-support/m2/)
- [Overview across chips](https://asahilinux.org/docs/platform/feature-support/overview/)

Anything marked work-in-progress there, Thunderbolt device support among them, is work-in-progress here too. The Aurora kernel adds the display, camera and USB4 work described above on top of that.

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
