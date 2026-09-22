---
title: Hardware support
description: Which Macs are supported, what works on each kernel lane, and the known limitations.
section: Reference
---

Hardware support is the Asahi Linux project's, plus what the Aurora kernel adds on the `rc` channel. The fork qualifies each release on real Macs and records the evidence with the release. Nothing below claims more than what has been exercised.

## Supported Macs

The installer catalog admits the M1 and M2 family device identifiers below. M3 Macs install on the `stable` channel with the newer engine; GPU support on M3 is still limited upstream.

| Family | Models |
| --- | --- |
| M1 | MacBook Air, MacBook Pro 13", Mac mini, iMac 24" |
| M1 Pro / Max | MacBook Pro 14" and 16" (2021), Mac Studio |
| M1 Ultra | Mac Studio |
| M2 | MacBook Air 13" and 15", MacBook Pro 13", Mac mini |
| M2 Pro / Max | MacBook Pro 14" and 16" (2023), Mac mini, Mac Studio |
| M2 Ultra | Mac Studio, Mac Pro |
| M3 | `stable` only, GPU limitations |

## Reference machines

| Machine | Role |
| --- | --- |
| MacBook Pro 14" 2021, M1 Pro, `apple,j314s` | Full regression on every release. Aurora kernel, Limine integration testing. |
| MacBook Pro 16" 2023, M2 Max, `apple,j416c` | Multi-display work: five displays through HDMI and USB4. Image builds and VM acceptance. |

## What works

<span class="status ok">works</span> in both lanes unless noted. <span class="status partial">rc only</span> needs the Aurora kernel. <span class="status wip">known issue</span> is tracked.

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
| Several external displays, USB4 / DisplayPort alt-mode | <span class="status partial">rc only</span> | Aurora kernel. Five displays on the M2 Max. |
| Variable refresh rate, camera (ISP), always-on processor | <span class="status partial">rc only</span> | Aurora kernel |
| Fullscreen window on a very wide display | <span class="status wip">known issue</span> | Hyprland paints only a band of a fullscreen window on a 5120×1440 output next to a scaled internal display. Upstream Hyprland issue. |
| Fourth external display after HDMI unplug | <span class="status wip">known issue</span> | A stale DisplayPort link on the M2 Max after unplugging HDMI; replug or reboot |
| Text console between Plymouth and the greeter | <span class="status wip">known issue</span> | Cosmetic, a few seconds |
| Touch ID, Thunderbolt display chaining, microphone array beamforming | <span class="status no">no</span> | Not supported by Asahi or Aurora yet |
| Widevine DRM in browsers | <span class="status ok">works</span> | When the package is available from the Asahi repositories |
| Steam | <span class="status ok">works</span> | Optional, through the Asahi FEX environment |

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
