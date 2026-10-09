# s2idle sleep-drain programme

Spec and tracking: maralcbr/omarchy-mx-mac#281.

Cut lid-closed s2idle drain on Omarchy Macs in the Aurora kernel, measured on the M1 Pro lab Mac only, in three levels: Easy ≤ 1.0 W, Medium ≤ 0.5 W, Hard ≤ 0.2 W (from about 2 W today).

## Tickets

| # | Ticket | Blocked by |
|---|---|---|
| 01 | [Reimage the M1 Pro LUKS-free with lab access](tickets/01-reimage-m1-pro-luks-free.md) | — |
| 02 | [Lab control plane](tickets/02-lab-control-plane.md) | — |
| 03 | [M1 Pro registered with the recovery ladder proven](tickets/03-m1-registered-recovery-proven.md) | 01, 02 |
| 04 | [Aurora fork built and booted once by the lab](tickets/04-aurora-fork-built-booted.md) | 03 |
| 05 | [Timed wake from s2idle](tickets/05-timed-wake-smc-rtc.md) | 04 |
| 06 | [Sleep measurement job](tickets/06-sleep-measurement-job.md) | 04 |
| 07 | [Attribution matrix](tickets/07-attribution-matrix.md) | 06 |
| 08 | [Easy patch series](tickets/08-easy-patch-series.md) | 07 |
| 09 | [Easy reliability gate and edge release](tickets/09-easy-gate-edge-release.md) | 05, 08 |
| 10 | [Easy stable promotion](tickets/10-easy-stable-promotion.md) | 09 |
| 11 | [PMP opt-in validated on the M1 Pro](tickets/11-pmp-opt-in-validated.md) | 06 |
| 12 | [Medium: clusters and fabric off in sleep](tickets/12-medium-clusters-fabric-off.md) | 09, 11 |
| 13 | [Medium reliability gate and release](tickets/13-medium-gate-release.md) | 12 |
| 14 | [Hard spike with kill criteria](tickets/14-hard-spike.md) | 13 |
| 15 | [Hard: macOS-style deep sleep](tickets/15-hard-implementation.md) | 14 (go only) |
| 16 | [Report generator](tickets/16-report-generator.md) | 06 |
| 17 | [Final HTML report](tickets/17-final-html-report.md) | 16 + last level |
| 18 | [Userspace power report and sleep-cost notice](tickets/18-userspace-power-report.md) | — |

## Ground rules

- M1 Pro only. The M2 Max is not used unless the owner strictly authorises it.
- Base: `sep-7.1.12.aurora2-12.6-stable` on iconidentify/aurora-linux, in a fork under the owner's account.
- t6000/t6001 on by default once validated; every other SoC opt-in until the owner approves.
- Every saving: three paired alternating runs beating run-to-run variation. Every default change: 20 short and 3 overnight cycles, zero resume failures.
- Sol (`gpt-6.1-sol`, fast tier, high effort) is the kernel engineer; Claude runs the lab.
