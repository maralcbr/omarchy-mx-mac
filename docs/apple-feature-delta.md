# Apple feature delta

Where every Apple-specific file in this fork should live once persistent
defaults move into packages, aligned with Scott's `omarchy-mac` add-on.

This is a classification record, not a change list. No runtime behaviour is
changed by this document.

## Sources (read-only, 2026-09-20)

| Tree | Ref | SHA |
| --- | --- | --- |
| This worktree (`maralcbr/omarchy-mx-mac`, `e/T0b` = `origin/main`) | `HEAD` | `69ad90fa438c588b6539fcc38b2fbbd431fe21ec` |
| Upstream desktop | `omacom/omarchy` `quattro` | `e38c1d1289252d2adb96372eeac48d02e489c5b7` |
| Scott product branch | `omacom/omarchy-mac` `quattro` | `79b074a8921ae2e195451991eda987445bcae962` |
| Scott distilled collaboration branch | `omacom/omarchy-mac` `quattro-upstream` | `fe18cd6ca74ccff9e0bec21ad930ad5186556d2d` |

Scott's plan and package contract:

- `docs/upstream-integration-plan.md` — package 1 is Wi-Fi iwd backend, Wi-Fi resume, microphone mapper, headset WirePlumber policy, notch `appledrm` default. It selects no kernel, contains no installer, and installs no repository trust. HID early-load, initramfs, boot, bindings, trackpad, Electron, ALS, snapshots, and the installer stay outside that package.
- `packages/omarchy-mac/` — independently buildable add-on `0.1.0`.
- `plans/omarchy-mac-package-validation.md` — physical M2 Max trial 2026-09-19 of add-on `0.1.0-4` with runtime/settings `4.0.3.r1.mac.20b8ae0f-1`. Validated: reboot, Wi-Fi, playback, microphone. Not validated: Aurora, BCM4388 resume, installer image, signed feed publication.

"Scott equivalent" paths below are on `quattro-upstream` unless marked `quattro` (product branch only). **Validated** means the file is in that package-1 payload (or is a compatibility leaf that only calls `omarchy-setup-mac`). Desktop leftovers on `quattro-upstream` were present on the trial machine but are not package-owned.

Target homes:

| Home | Meaning |
| --- | --- |
| `omarchy-mac (Scott)` | Scott's first add-on, or a later expansion of it |
| `omarchy-mac-boot (ours)` | New package in `omarchy-pkgs`; what package 1 excludes (boot/initramfs) plus, until Scott carries them, our persistent defaults |
| `mx runtime` | Stays in this fork's `omarchy` package / app |
| `omacom/omarchy quattro` | Already generic, or a later upstream PR |
| `drop` | Do not keep once the owner package is present |

`config/autostart/print-applet.desktop` matches `*apple*` by name only (CUPS). It is not in this delta. `applications/` and `themes/` have no Apple-specific files.

---

## 1. MX delta versus `omacom/omarchy` quattro

### 1.1 `install/hardware/apple/`

| File | What it does | Scott equivalent | Validated? | Home |
| --- | --- | --- | --- | --- |
| `install/hardware/apple/fix-asahi-hid-race.sh` | On Apple Silicon, writes `/etc/mkinitcpio.conf.d/apple_hid_modules.conf` so `hid_apple` and `hid_magicmouse` are in the initramfs before `dockchannel-hid` registers devices. | Same path, byte-identical. Plan puts HID early-load **outside** package 1. `quattro-upstream` `install/hardware/all.sh` still runs the leaf. | No (not in package 1) | `omarchy-mac-boot (ours)` |
| `install/hardware/apple/fix-asahi-btrfs-race.sh` | On Apple Silicon, writes a `kmod-static-nodes.service` drop-in so `/dev/btrfs-control` exists in the systemd initramfs. | Absent | — | `omarchy-mac-boot (ours)` |
| `install/hardware/apple/fix-brcmfmac-supplicant.sh` | Intel/T2 Broadcom: disable firmware WPA offload. MX adds `omarchy-hw-apple-silicon && return 0` because that offload is what works on Asahi. | Same path; same Apple Silicon skip, slightly longer comment. Package 1 owns **iwd** (`vendor/NetworkManager/conf.d/20-omarchy-mac-wifi.conf`), not this modprobe. | Skip: yes in spirit (package 1 is iwd). This file: no | `omacom/omarchy quattro` (AS skip is the later PR; quattro still lacks the detector so it cannot take the skip as-is) |
| `install/hardware/apple/fix-speaker-pop.sh` | Copies the WirePlumber no-suspend drop-in to `/etc`. (The `software-dsp.lua` overlay it once installed hung WirePlumber on J293; migration `1790225826.sh` removes it.) | No no-suspend file. Closest: `install/hardware/apple/audio.sh` (installs `speakersafetyd` / `asahi-audio`) and package 1 `share/wireplumber/wireplumber.conf.d/asahi-headset-mic.conf` (headset priority, different file). | No | `omarchy-mac-boot (ours)` until Scott's package carries no-suspend |
| `install/hardware/apple/fix-spi-keyboard.sh` | Intel MacBook SPI keyboard modules + mkinitcpio. MX only hardens missing DMI. | Same path (product and distilled). | n/a (not Apple Silicon) | `omacom/omarchy quattro` |
| `install/hardware/apple/fix-suspend-nvme.sh` | Intel MacBook NVMe D3cold. Identical to quattro. | Same path, identical | n/a | `omacom/omarchy quattro` |
| `install/hardware/apple/fix-t2.sh` | T2 kernel, firmware, Limine cmdline. Identical to quattro. | Same path, identical | n/a | `omacom/omarchy quattro` |

`install/user/hardware/apple/fix-speaker-pop.sh` — per-user copy of the same no-suspend drop-in. Scott: `install/user/hardware/apple/mic.sh` is only `omarchy-setup-mac --user` (validated compatibility leaf). Home: `omarchy-mac-boot (ours)` until Scott carries no-suspend.

### 1.2 `install/*asahi*` and platform contract

| File | What it does | Scott equivalent | Validated? | Home |
| --- | --- | --- | --- | --- |
| `install/omarchy-base-asahi.packages` | Asahi core package list (`linux-asahi`, `m1n1`, mesa, `asdcontrol`, …). | `install/omarchy-apple.packages` is the single line `omarchy-mac`. No Asahi kernel list. | Package list: yes (add-on only) | `mx runtime` |
| `install/omarchy-other-asahi.packages` | Asahi extra set; includes `zram-generator`, PipeWire, `vulkan-asahi`. | Absent as a separate list | — | `mx runtime` |
| `install/apple-silicon-platform-stack.json` | Installer/engine ownership contract (boot backend, safety invariants, locked engine artifact). | Absent | — | `mx runtime` |

### 1.3 `config/`

No Apple-specific files. `config/hypr/input.lua` is the user override template (generic). `config/autostart/print-applet.desktop` is CUPS.

### 1.4 `default/` (Apple-named or Apple-gated)

| File | What it does | Scott equivalent | Validated? | Home |
| --- | --- | --- | --- | --- |
| `default/asahi-repository-signing.asc` | Package-channel signing key for `[omarchy]` Asahi snapshots. | Plan: package 1 installs **no** repository trust. Distilled `install/hardware/apple/pacman.sh` still adds unsigned `[omarchy-aarch64]`. | No | `mx runtime` |
| `default/aurora-qualified-release` | Pin + descriptor digest for `[omarchy-aurora]`. | Absent | — | `mx runtime` |
| `default/hypr/apple.lua` | `no_hardware_cursors` on Apple Silicon (DCP cursor lag). | Absent | — | `omarchy-mac-boot (ours)` until Scott carries bindings |
| `default/hypr/input.lua` (Apple lines only) | `hl.device` tap-to-click off for `apple-mtp-multi-touch` and `apple-spi-trackpad`. Rest of the file is generic; quattro lacks those two device lines. | `install/user/hardware/apple/touchpad.sh` appends `natural_scroll = true` / `tap_to_click = false` to the **user** override. Different mechanism, overlapping policy. | No | `omarchy-mac-boot (ours)` until Scott carries trackpad |
| `default/libalpm/hooks/01-omarchy-aurora-verify.hook` | PreTransaction abort unless Aurora db matches the staged descriptor. | Absent | — | `mx runtime` |
| `default/wireplumber/wireplumber.conf.d/asahi-audio-no-suspend.conf` | `session.suspend-timeout-seconds = 0` on AppleJ ALSA devices. | Package 1: `packages/omarchy-mac/share/wireplumber/wireplumber.conf.d/asahi-headset-mic.conf` (headset source priority). Same `conf.d`, different file. | Headset: yes. No-suspend: no | `omarchy-mac-boot (ours)` until Scott carries no-suspend |
| `default/systemd/zram-generator.conf.d/90-omarchy.conf` | `zram-size = ram`, zstd, priority 100. **Identical** to quattro and to `quattro-upstream`. | Same path, identical. Distilled `enable-services.sh` says Apple Silicon currently ships neither oomd drop-ins nor this zram tuning in settings. | Not as an Apple package | `omarchy-mac-boot (ours)` until Scott carries zram layout |

`etc/wireplumber/wireplumber.conf.d/asahi-audio-no-suspend.conf` is the settings-package copy of the same drop-in. Same home as the `default/` file.

### 1.5 `bin/omarchy-*asahi*`, `*apple*`, `*aurora*`

| File | What it does | Scott equivalent | Validated? | Home |
| --- | --- | --- | --- | --- |
| `bin/omarchy-hw-apple-silicon` | Device-tree `apple,` detector. Quattro does not have it. | Same path (extra comment). Legacy alias `bin/omarchy-hw-apple` on distilled only. | Detector is a **runtime** interface the add-on requires (`README.md`: "Runtime dependencies: `omarchy` (shared Apple hardware detector)") | `mx runtime` |
| `bin/omarchy-hw-apple-kernel` | Prints `linux-asahi` or the Aurora marker file. | Absent | — | `mx runtime` |
| `bin/omarchy-apple-silicon-channel` | Channel record, rc/edge lane, holds, verify-locked. | Absent | — | `mx runtime` |
| `bin/omarchy-apple-silicon-boot-check` | Byte-compare kernel, initramfs, GRUB, m1n1 stage-2 vs installed pair. Never runs `update-m1n1`. | Absent | — | `mx runtime` |
| `bin/omarchy-apple-silicon-retire-saved-modules` | After a kernel downgrade, move saved `-ARCH` modules aside and rebuild m1n1. | Absent | — | `mx runtime` |
| `bin/omarchy-update-aurora-repository` | Pin/move `[omarchy-aurora]` to the qualified signed release; edge lane. | Absent | — | `mx runtime` |
| `bin/omarchy-update-aurora-verify` | Hook body for `01-omarchy-aurora-verify.hook`. | Absent | — | `mx runtime` |
| `bin/omarchy-apple-platform-stack-verify` | Validates `install/apple-silicon-platform-stack.json`. | Absent | — | `mx runtime` |
| `bin/omarchy-install-asahi-fresh` | Fresh Asahi/Aurora install: `--deferred-user`, `--offline`, `update-m1n1`, boot-check. | Absent. Plan reuses this app + encrypted ISO work; does not extract this command. | No | `omarchy-mac-boot (ours)` (deferred user, m1n1 rebuild, encryption handoff) |
| `bin/omarchy-update-apple-boot-admission` | Read-only: `owned` / `adopt` / `skip` for image-written `omarchy-apple-boot` files (vendorfw, `90-omarchy-asahi.conf`). | Absent | — | `mx runtime` (updater must keep deciding adoption) |
| `bin/omarchy-update-asahi-repository` | Move `[omarchy]` Server along the signed Asahi channel. | Distilled `install/hardware/apple/pacman.sh` (unsigned `[omarchy-aarch64]`). | No | `mx runtime` |
| `bin/omarchy-update-asahi-bundle` | Older signed Quattro bundle updater (`omarchy-dev` / settings-dev). | Absent | — | `drop` once the channel updater is the only path |
| `bin/omarchy-debug-apple` | Post-install PASS/FAIL including `speakersafetyd`. | Absent | — | `mx runtime` |
| `bin/omarchy-brightness-display-apple` | Studio/XDR brightness via `asdcontrol`. Identical to quattro. | Identical | n/a (generic Apple display) | `omacom/omarchy quattro` |
| `bin/omarchy-hyprland-monitor-focused-apple` | True if focused monitor is Studio/XDR. Identical to quattro. | Identical | n/a | `omacom/omarchy quattro` |

`bin/omarchy-channel-set` is not in the glob as `*apple*` but gates `rc`/`edge` through `omarchy-apple-silicon-channel`. Home: `mx runtime`.

`bin/omarchy-drive-password` is **identical** to quattro (generic LUKS `luksChangeKey`). Apple encryption/keyslot work does not live in this binary; it lives in `omarchy-provision-owner` + the fresh installer. Home of the binary: `omacom/omarchy quattro`. Home of Apple parity glue: `omarchy-mac-boot (ours)`.

### 1.6 Migrations that touch Apple

One-shot migrators stay in `mx runtime` even when the payload they once wrote moves: they must keep no-oping on machines that already applied them. New installs must not re-run the leaf once the package owns the file (section 3).

| File | What it does | Scott equivalent | Validated? | Home |
| --- | --- | --- | --- | --- |
| `migrations/1787497040.sh` | Re-run HID early-load + rebuild initramfs. | `migrations/1788200001.sh` (same job) | No | `mx runtime` (historical); payload → `omarchy-mac-boot (ours)` |
| `migrations/1789107528.sh` | Re-run btrfs static-nodes drop-in + mkinitcpio. | Absent | — | `mx runtime`; payload → `omarchy-mac-boot (ours)` |
| `migrations/1788345489.sh` | Speaker no-suspend drop-in. | `1789136142.sh` / `1789136143.sh` (audio stack + mic map, not no-suspend) | Audio stack: package 1 mic yes; speakersafetyd desktop leftover | `mx runtime`; payload → `omarchy-mac-boot (ours)` until Scott |
| `migrations/1787552067.sh` | Install `rtkit` on Apple Silicon. | `1788200002.sh` + `audio.sh` | Partial (audio packages on trial) | `omarchy-mac (Scott)` (audio.sh leftover; should join package 1 later) |
| `migrations/1789172112.sh` | Remove Intel `brcmfmac` workaround from Apple Silicon. | Absent (distilled leaf already skips AS) | — | `mx runtime` |
| `migrations/1788486400.sh` | Install packages missing from an older Asahi set. | Absent | — | `mx runtime` |
| `migrations/1787560726.sh` | Configure signed Omarchy repo on Apple Silicon. | `1788200000.sh` `[omarchy-aarch64]`; `1789275235.sh` package-owned Wi-Fi default | Trust: no | `mx runtime` |
| `migrations/1789879296.sh` | Replace leftover `linux-asahi-headers` on Aurora; `update-m1n1`. | Absent | — | `mx runtime` |
| `migrations/1786391100.sh` | Broadcom software WPA on Intel/T2 Macs. | Same idea on product branch | n/a | `omacom/omarchy quattro` |
| `migrations/1785944594.sh` | T2 suspend/Touch Bar/fan. | Present on product branch | n/a | `omacom/omarchy quattro` |
| `migrations/1785273276.sh` | T2 `apple-bce` → `t2bce`. | Present on product branch | n/a | `omacom/omarchy quattro` |
| `migrations/1789444024.sh` | Headers for Omarchy/T2 kernel; Apple Silicon exits first. | n/a | n/a | `omacom/omarchy quattro` |
| `migrations/1789325478.sh` | Limine `linux-omarchy`; skipped on Apple Silicon. | n/a | n/a | `omacom/omarchy quattro` |
| `migrations/1785013000.sh` / `1784961000.sh` | zram vendor drop-in / reclaim. Generic; identical lineage on quattro. | Distilled `1789154627.sh` ensures `zram-generator` | Not Apple-specific | `omacom/omarchy quattro` (generic); Apple layout copy → `omarchy-mac-boot (ours)` until Scott |

### 1.7 Applications and themes

None.

### 1.8 `.github`

| File | What it does | Scott equivalent | Validated? | Home |
| --- | --- | --- | --- | --- |
| `.github/workflows/packages.yml` | `resolve-asahi` / `install-asahi` jobs on `omarchy-*-asahi.packages`. | ARM install CI exists on product `quattro` (`codex/pr-arm-install-ci`, `fix/pr354-arm-recovery-pipe`) but not this layout. | n/a | `mx runtime` |
| `.github/workflows/release.yml` | Runs Asahi package/update/fresh-install shell tests. | Different release workflow | n/a | `mx runtime` |
| `.github/workflows/optional-packages.yml` | `asahi-packages` job, asahi-alarm keyring, `test/vm/asahi-fresh/**` path filter. | Absent | n/a | `mx runtime` |

Issue templates are generic. `pages.yml` / `tests.yml` are not Apple-named.

### 1.9 `test/shell.d` Apple tests

Tests follow the production file they cover.

| File | Covers | Scott equivalent | Home |
| --- | --- | --- | --- |
| `apple-hid-race-test.sh` | HID mkinitcpio leaf | Same name, same leaf | `omarchy-mac-boot (ours)` |
| `asahi-btrfs-race-test.sh` | btrfs static-nodes leaf | Absent | `omarchy-mac-boot (ours)` |
| `apple-speaker-pop-test.sh` | no-suspend copy | Absent (`asahi-audio-install-test.sh` covers package install) | `omarchy-mac-boot (ours)` until Scott |
| `apple-brcmfmac-cleanup-test.sh` | AS skip of Intel workaround | Distilled has this test | `omacom/omarchy quattro` |
| `apple-legacy-hardware-probe-test.sh` | SPI leaf with missing DMI | Absent | `omacom/omarchy quattro` |
| `apple-silicon-test.sh` | detector | Distilled `apple-silicon-test.sh` + `bin/omarchy-hw-apple` | `mx runtime` |
| `hw-apple-kernel-test.sh` | kernel helper | Absent | `mx runtime` |
| `apple-silicon-channel-test.sh` | channel record | Absent | `mx runtime` |
| `apple-silicon-boot-check-test.sh` | boot-check | Absent | `mx runtime` |
| `apple-silicon-retire-saved-modules-test.sh` | saved-modules / m1n1 | Absent | `mx runtime` |
| `aurora-repository-update-test.sh` / `aurora-edge-update-test.sh` / `aurora-verify-hook-test.sh` / `aurora-asahi-headers-migration-test.sh` / `update-system-pkgs-aurora-test.sh` | Aurora lane | Absent | `mx runtime` |
| `asahi-repository-update-test.sh` / `asahi-update-test.sh` / `asahi-bundle-update-test.sh` / `asahi-package-repository-test.sh` / `asahi-package-candidate-test.sh` / `asahi-packages-test.sh` | Asahi channel / lists | Distilled `apple-pacman-repo-test.sh` | `mx runtime` |
| `asahi-fresh-install-test.sh` / `asahi-fresh-deferred-test.sh` / `asahi-fresh-offline-test.sh` / `asahi-fresh-vm-run-test.sh` / `asahi-bootstrap-test.sh` / `asahi-bootstrap-channel-test.sh` | deferred-user, m1n1, vendorfw in image | Absent | `omarchy-mac-boot (ours)` + `mx runtime` (bootstrap wrapper) |
| `apple-boot-admission-test.sh` / `apple-boot-update-target-test.sh` | `omarchy-apple-boot` adoption | Absent | `mx runtime` |
| `apple-platform-stack-test.sh` | platform JSON | Absent | `mx runtime` |
| `apple-installer-branding-test.sh` / `apple-installer-channel-publish-test.sh` / `apple-installer-pkg-daemon-plist-test.sh` | macOS app packaging | Absent | `mx runtime` |
| `debug-apple-test.sh` | `omarchy-debug-apple` | Absent | `mx runtime` |
| `hyprland-apple-cursor-test.sh` | `default/hypr/apple.lua` | Absent | `omarchy-mac-boot (ours)` until Scott |
| `brightness-display-apple-cache-test.sh` | identical to quattro | Identical | `omacom/omarchy quattro` |
| `migrate-asahi-test.sh` | T2/Limine migrations skipped on AS | Distilled has broader Apple migration tests | `mx runtime` |

### 1.10 Fork-only app, engine, catalogs

Counted as three units, not per Swift file. Scott's plan names this app as the installer to reuse; it does not live in `packages/omarchy-mac/`.

| Unit | What it does | Scott equivalent | Home |
| --- | --- | --- | --- |
| `apps/omarchy-apple-installer/` | macOS installer (SwiftPM, helper, packaging, notarize). | Plan: reuse. No sources on either Scott branch. | `mx runtime` |
| `apps/omarchy-apple-installer/Engine/overlay/` | Closed asahi-installer overlay (`omarchy_asahi.py`, stage1, vendorfw copy into the image). | Plan mentions overlay under a local integration tree, not in git. | `mx runtime` |
| `apps/omarchy-apple-installer/Release/` + `scripts/make-unsigned-catalog.py` + `scripts/publish-channels` | Signed catalogs, trust root, channel publish. | Absent (package 1 forbids trust config) | `mx runtime` |

Image-written boot files (`90-omarchy-asahi.conf`, `omarchy-vendorfw.sh` / `.service`, `/etc/initcpio/install/omarchy-vendorfw`) are **not** in this git tree. They are the `omarchy-apple-boot` payload in `omarchy-pkgs` (hashes in `bin/omarchy-update-apple-boot-admission`). T3's `omarchy-mac-boot` replaces that package. `apple-image-finalize` is likewise not a path here; it is image-builder work that belongs in `omarchy-mac-boot (ours)`.

### 1.11 Interleaved files T3 still cares about

| File | Apple gate | Home |
| --- | --- | --- |
| `install/hardware/all.sh` | Runs the Apple leaves | `mx runtime`; stop invoking leaves the package owns |
| `install/user/all.sh` | Runs user speaker-pop | same |
| `install/hardware/pacman.sh` | Writes `[omarchy]` on Apple Silicon | `mx runtime` |
| `install/config/enable-services.sh` | Skips `systemd-oomd` on Apple Silicon | `mx runtime` |
| `install/hardware/network.sh` | Distilled: requires `omarchy-mac` then `omarchy-mac-setup-system`. MX: no add-on call | Scott's hook stays; MX must not grow a second Wi-Fi writer |
| `bin/omarchy-provision-owner` | Shared deferred-user + LUKS rekey (`luksAddKey`, kill other slots). Uses `OMARCHY_SETUP_CONTEXT=provision-owner` when calling `omarchy-provision-user`. | `mx runtime` |
| `bin/omarchy-update-system-pkgs` | Adds `--needed omarchy-apple-boot` when admission says `adopt` | `mx runtime`; rename target to `omarchy-mac-boot` when T3 ships |

---

## 2. `quattro-upstream` carries that MX `main` does not

Apple-named paths on `fe18cd6c` that are absent from this worktree.

### 2.1 Scott package 1 (validated M2 Max 2026-09-20 record)

| Path | What it does | MX has? | Home |
| --- | --- | --- | --- |
| `packages/omarchy-mac/bin/omarchy-wifi-resume-fix` + `vendor/systemd/system/omarchy-wifi-resume-fix.service` | Restricted brcmfmac reload after s2idle (BCM4378/4387 only). | No (MX has no wifi-resume leaf) | `omarchy-mac (Scott)` |
| `packages/omarchy-mac/vendor/NetworkManager/conf.d/20-omarchy-mac-wifi.conf` | `wifi.backend=iwd`. | MX `install/hardware/network.sh` does not write this | `omarchy-mac (Scott)` |
| `packages/omarchy-mac/bin/omarchy-audio-asahi-mic-map` + `vendor/systemd/user/omarchy-asahi-mic.service` | Map Asahi mic array; persist gain/mute. | No | `omarchy-mac (Scott)` |
| `packages/omarchy-mac/share/wireplumber/wireplumber.conf.d/asahi-headset-mic.conf` | Deprioritize empty 3.5mm headset source. | No (MX has no-suspend instead) | `omarchy-mac (Scott)` |
| `packages/omarchy-mac/vendor/modprobe.d/asahi-notch.conf` | `appledrm show_notch=1`. | No | `omarchy-mac (Scott)` |
| `packages/omarchy-mac/bin/omarchy-mac-setup-{system,user}` | Setup entrypoints; retire exact generated files. | No | `omarchy-mac (Scott)` |
| `packages/omarchy-mac/legacy/*` | Historical `/etc` fragments for retirement. | No | `omarchy-mac (Scott)` |
| `install/omarchy-apple.packages` | `omarchy-mac` | MX uses `*-asahi.packages` | `omarchy-mac (Scott)` + MX keep Asahi lists |
| `install/hardware/apple/enable-notch.sh` / `fix-wifi-resume.sh` / `install/user/hardware/apple/mic.sh` | Compatibility: `omarchy-setup-mac`. | No | `omarchy-mac (Scott)` |
| `migrations/1789780917.sh` | `omarchy-setup-mac` transition | No | `omarchy-mac (Scott)` |
| `migrations/1789275235.sh` | Package-owned Wi-Fi default | No | `omarchy-mac (Scott)` |

### 2.2 Distilled desktop leftovers (explicitly **not** package 1)

| Path | What it does | Collision with `omarchy-mac-boot`? | Suggested home |
| --- | --- | --- | --- |
| `install/hardware/apple/fix-asahi-hid-race.sh` | Same HID initramfs modules as MX | **Yes** — both would write `apple_hid_modules.conf` | `omarchy-mac-boot (ours)`; Scott leaf must become a no-op |
| `install/hardware/apple/audio.sh` | `pkg-add` rtkit, pipewire-pulse, asahi-audio, **speakersafetyd**; enable the daemon | **Yes** — speakersafetyd enablement | `omarchy-mac (Scott)` later; until then `omarchy-mac-boot (ours)` |
| `install/user/hardware/apple/touchpad.sh` | Append natural-scroll / no tap-to-click | **Yes** — Hyprland input | `omarchy-mac (Scott)` later; until then `omarchy-mac-boot (ours)` |
| `install/hardware/apple/electron-gl.sh` + user leaf + `bin/omarchy-cmd-electron-gl-{args,wrap}` | Software GL wrappers without AGX | No | `omarchy-mac (Scott)` (later package) or distilled desktop PR |
| `install/hardware/apple/video-decode.sh` | `avd-fw` / `libva-v4l2_request-avd` from `[omarchy-aarch64]` | No | distilled desktop / packages, not boot |
| `install/hardware/apple/pacman.sh` | Unsigned `[omarchy-aarch64]` | Trust conflict with MX signed channel | `mx runtime` keeps signed channel; distilled leaf should not ship to testers on MX |
| `install/user/hardware/apple/obsidian.sh` / `share-picker.sh` | AppImage Obsidian; PipeWire capturer flag | No | `omarchy-mac (Scott)` later or quattro PR |
| `bin/omarchy-hw-apple` | Alias to `omarchy-hw-apple-silicon` | No | `mx runtime` (add alias if user units need it) |
| `migrations/1789132067.sh` | Fn/media keys | No | later Scott / quattro |
| `migrations/1789135842.sh` | Keyboard ALS | No | later Scott / quattro |
| `migrations/1789148088.sh` | Snapper on Apple Silicon | No | later Scott / quattro |
| `migrations/1789158178.sh` | GRUB/plymouth branding on AS | Overlaps boot story | `omarchy-mac-boot (ours)` if it touches initramfs hooks; else desktop |
| `migrations/1789158179.sh` | Retire Asahi bootstrap from wheel | Deferred-user adjacent | `omarchy-mac-boot (ours)` |
| `migrations/1789522888.sh` | `omarchy-steam-fex` | No | Scott desktop / steam package |
| tests: `apple-touchpad-test.sh`, `apple-fnmode-test.sh`, `apple-capture-chords-test.sh`, `apple-video-decode-test.sh`, `apple-settings-test.sh`, `apple-rtkit-migration-test.sh`, `asahi-audio-install-test.sh`, `asahi-alarm-wheel-migration-test.sh`, `manual-apple-hotkeys-test.sh` | Coverage for the leftovers | Follow the production file | as above |

Product-only `quattro` extras not on `quattro-upstream` (not distilled): `bin/omarchy-audio-asahi-mic-map` still in desktop `bin/`, `default/systemd/user/omarchy-asahi-mic.service`, `default/wireplumber/.../asahi-headset-mic.conf`, `install/hardware/zram.sh`, `docs/arm-package-sources.md`. Those are the pre-extraction copies of package 1.

---

## 3. T3 (`omarchy-mac-boot`) dependency notes

T3 replaces the existing `omarchy-apple-boot` package (payload hashes in `bin/omarchy-update-apple-boot-admission`) and the MX leaves that still write the same classes of file. The runtime must stop installing a path the package owns: keep the leaf as a detector-gated no-op when `pacman -Qq omarchy-mac-boot` is present (same pattern as distilled `install/hardware/network.sh` requiring `omarchy-mac`).

| Package item | MX files it replaces | How the runtime stops installing them |
| --- | --- | --- |
| mkinitcpio hooks/presets (`asahi`, `omarchy-vendorfw`, `90-omarchy-asahi.conf`, `/etc/initcpio/install/omarchy-vendorfw`) | Image-written files + adoption via `bin/omarchy-update-apple-boot-admission` + `bin/omarchy-update-system-pkgs` target `omarchy-apple-boot`. Not sourced in git. | Rename the pacman target to `omarchy-mac-boot`. Admission hashes must match T3's payload or every Mac gets a `.pacnew`. Do not add a hardware leaf that tees those files. |
| HID modules (`apple_hid_modules.conf`) | `install/hardware/apple/fix-asahi-hid-race.sh`; migration `1787497040.sh` | Leaf: `omarchy-hw-apple-silicon \|\| return 0`; then `pacman -Qq omarchy-mac-boot && return 0`. `install/hardware/all.sh` may keep calling the leaf. |
| btrfs initramfs race | `install/hardware/apple/fix-asahi-btrfs-race.sh`; migration `1789107528.sh` | Same package-present guard. |
| `apple-image-finalize` | Not in this tree (image builder / `omarchy-pkgs`). Engine overlay copies vendorfw into the image (`Engine/overlay/src/omarchy_asahi.py`). | Package ships finalize; overlay stops embedding duplicate files once the installed system takes the package. |
| m1n1 stage-2 rebuild | `bin/omarchy-install-asahi-fresh` (`update-m1n1`); `bin/omarchy-apple-silicon-retire-saved-modules`; migration `1789879296.sh` | Rebuild **policy** can live in the package. `omarchy-apple-silicon-boot-check` and the channel/lane tools stay in mx and must keep calling the packaged rebuild, not a second copy. |
| First boot with deferred user | `bin/omarchy-install-asahi-fresh --deferred-user`; `bin/omarchy-provision-owner` | Installer/package may **create** `/var/lib/omarchy/provisioning/pending`. `omarchy-provision-owner` stays the tty1 hook that consumes it. |
| Encryption step | Fresh installer + `omarchy-provision-owner` `rekey_luks` | Package may ship Asahi-safe cryptsetup/initramfs drop-ins (no Limine UKI auto-unlock). Must not fork `rekey_luks`. |
| Recovery keyslot | `rekey_luks` in `omarchy-provision-owner` (add user key, kill other slots). No separate recovery-key UX in this tree. | If T3 adds a recovery slot, it hooks **after** owner rekey via the existing provisioning dir; do not add a second slot killer. |
| Drive-password parity | `bin/omarchy-drive-password` (already generic quattro) | Keep the command in desktop. Package only if Asahi needs a different `cryptsetup` invocation; otherwise a guard in the command is enough. |
| WirePlumber no-suspend | `default/` + `etc/` drop-ins; `install/hardware/apple/fix-speaker-pop.sh`; `install/user/hardware/apple/fix-speaker-pop.sh`; migration `1788345489.sh` | Package-present guard on both leaves. Do not write `$HOME/.config/wireplumber` if the vendor file is in `/usr/share/wireplumber`. |
| speakersafetyd | MX: enabled indirectly via Asahi packages + `omarchy-debug-apple`. Distilled: `install/hardware/apple/audio.sh` | If T3 enables the unit, MX must not, and Scott's `audio.sh` must guard. Prefer Scott taking this into package 1. |
| zram layout | `default/systemd/zram-generator.conf.d/90-omarchy.conf` (also quattro settings) | Shipping this in `omarchy-mac-boot` **and** `omarchy-settings` is a file-ownership clash. T3 should vendor an Apple-only drop-in name (`90-omarchy-mac.conf`) or wait for Scott. |
| Trackpad / bindings | `default/hypr/input.lua` device lines; `default/hypr/apple.lua` | Package-owned Hypr snippet. `all.sh` / user finalize must not append a second `omarchy-apple-touchpad` block (Scott's `touchpad.sh` already no-ops if keys exist). |

Kernel lane tools listed in the task stay in mx: `bin/omarchy-apple-silicon-channel`, `bin/omarchy-channel-set` (rc/edge), `bin/omarchy-update-aurora-repository`, `bin/omarchy-apple-silicon-boot-check`, `bin/omarchy-apple-silicon-retire-saved-modules`, `default/libalpm/hooks/01-omarchy-aurora-verify.hook`.

---

## 4. Impossible to move

**Shared Apple Silicon detector (`bin/omarchy-hw-apple-silicon`).** Scott's add-on documents it as an `omarchy` runtime dependency. Every MX leaf, distilled leftover, and the add-on setup scripts call it. Moving it into either Apple package makes that package a dependency of generic hardware setup and of x86 CI stubs.

**`omarchy-provision-owner` hook points.** First-boot user creation, group application, and LUKS rekey are the shared deferred-provisioning path (ISO and Asahi). Distilled Apple user setup runs from `install/user/first-run/enable-user-units.sh` and `omarchy-provision-user`, not by copying this file. Apple encryption/deferred-user must call in; they must not own the command.

**Kernel lane / Aurora tools.** Channel record, signed `[omarchy-aurora]` pin, ALPM verify hook, boot-check, and saved-module retirement are the mx kernel-switch machinery. Scott's package 1 selects no kernel. Putting them in `omarchy-mac-boot` would couple boot-file ownership to lane policy.

**macOS app, engine overlay, catalogs.** Closed Darwin installer, signed catalogs, and the asahi-installer overlay are fork-only (`docs/file-layout.md`). Scott's plan reuses them in a companion installer project; they are not add-on payload.

**Repository trust.** Package 1 forbids it. MX `default/asahi-repository-signing.asc` and the Asahi/Aurora updaters stay with the runtime that owns `pacman.conf`.

**T2 / Intel Mac leaves that quattro already has** (`fix-t2.sh`, `fix-suspend-nvme.sh`, `fix-spi-keyboard.sh`, display brightness helpers). They are not Apple Silicon boot. Moving them into `omarchy-mac-boot` would install Asahi initramfs policy on Intel Macs, or pull an Apple Silicon package onto T2.

---

## Counts (section 1 classified homes)

Each path below is counted once. Tests are listed with the code they cover.

**omarchy-mac-boot (ours) — 18**

`install/hardware/apple/fix-asahi-hid-race.sh`, `fix-asahi-btrfs-race.sh`, `fix-speaker-pop.sh`; `install/user/hardware/apple/fix-speaker-pop.sh`; `default/hypr/apple.lua`; Apple device lines in `default/hypr/input.lua`; `default/wireplumber/wireplumber.conf.d/asahi-audio-no-suspend.conf`; `etc/wireplumber/wireplumber.conf.d/asahi-audio-no-suspend.conf`; `default/systemd/zram-generator.conf.d/90-omarchy.conf`; `bin/omarchy-install-asahi-fresh`; tests `apple-hid-race-test.sh`, `asahi-btrfs-race-test.sh`, `apple-speaker-pop-test.sh`, `hyprland-apple-cursor-test.sh`, `asahi-fresh-install-test.sh`, `asahi-fresh-deferred-test.sh`, `asahi-fresh-offline-test.sh`, `asahi-fresh-vm-run-test.sh`.

Image payload not in this git tree (`90-omarchy-asahi.conf`, vendorfw, `apple-image-finalize`) is also this home; not in the 18.

**mx runtime — 60**

Detector/kernel lane: `bin/omarchy-hw-apple-silicon`, `omarchy-hw-apple-kernel`, `omarchy-apple-silicon-channel`, `omarchy-apple-silicon-boot-check`, `omarchy-apple-silicon-retire-saved-modules`, `omarchy-update-aurora-repository`, `omarchy-update-aurora-verify`, `omarchy-channel-set`, `default/libalpm/hooks/01-omarchy-aurora-verify.hook`, `default/aurora-qualified-release`. Trust/updater: `default/asahi-repository-signing.asc`, `bin/omarchy-update-asahi-repository`, `omarchy-update-apple-boot-admission`, `omarchy-update-system-pkgs`, `omarchy-apple-platform-stack-verify`, `omarchy-debug-apple`, `install/hardware/pacman.sh`, `install/omarchy-base-asahi.packages`, `install/omarchy-other-asahi.packages`, `install/apple-silicon-platform-stack.json`. Shared hooks: `bin/omarchy-provision-owner`. Installer units: `apps/omarchy-apple-installer/` (tree), `Engine/overlay/` (tree), `Release/`+catalog scripts (tree). Migrations: `1787497040`, `1789107528`, `1788345489`, `1789172112`, `1788486400`, `1787560726`, `1789879296`. Workflows: `packages.yml`, `release.yml`, `optional-packages.yml`. Tests: `apple-silicon-test.sh`, `hw-apple-kernel-test.sh`, `apple-silicon-channel-test.sh`, `apple-silicon-boot-check-test.sh`, `apple-silicon-retire-saved-modules-test.sh`, `aurora-repository-update-test.sh`, `aurora-edge-update-test.sh`, `aurora-verify-hook-test.sh`, `aurora-asahi-headers-migration-test.sh`, `update-system-pkgs-aurora-test.sh`, `asahi-repository-update-test.sh`, `asahi-update-test.sh`, `asahi-bundle-update-test.sh`, `asahi-package-repository-test.sh`, `asahi-package-candidate-test.sh`, `asahi-packages-test.sh`, `asahi-bootstrap-test.sh`, `asahi-bootstrap-channel-test.sh`, `apple-boot-admission-test.sh`, `apple-boot-update-target-test.sh`, `apple-platform-stack-test.sh`, `apple-installer-branding-test.sh`, `apple-installer-channel-publish-test.sh`, `apple-installer-pkg-daemon-plist-test.sh`, `debug-apple-test.sh`, `migrate-asahi-test.sh`.

**omacom/omarchy quattro — 15**

`install/hardware/apple/fix-brcmfmac-supplicant.sh`, `fix-spi-keyboard.sh`, `fix-suspend-nvme.sh`, `fix-t2.sh`; `bin/omarchy-brightness-display-apple`, `omarchy-hyprland-monitor-focused-apple`, `omarchy-drive-password`; migrations `1786391100`, `1785944594`, `1785273276`, `1789444024`, `1789325478`; tests `apple-brcmfmac-cleanup-test.sh`, `apple-legacy-hardware-probe-test.sh`, `brightness-display-apple-cache-test.sh`. Generic zram migrations `1785013000`/`1784961000` stay here as quattro history, not extra Apple files.

**omarchy-mac (Scott) — 1**

`migrations/1787552067.sh` (rtkit / audio packages; distilled already has `audio.sh` + `1788200002.sh`).

**drop — 1**

`bin/omarchy-update-asahi-bundle`.

Section 2 adds 11 package-1 paths already at `omarchy-mac (Scott)`, plus about 12 distilled leftovers that must not be copied into `omarchy-mac-boot` without the guards in section 3.

---

## The five collisions

These are the places Scott's add-on (or a leftover leaf that `quattro-upstream` still runs) and `omarchy-mac-boot` would both try to own:

1. **WirePlumber `conf.d`** — Scott validated `asahi-headset-mic.conf`; MX `asahi-audio-no-suspend.conf`. Same directory, two policies. T3 may ship no-suspend only until Scott takes it; never a second headset file.
2. **speakersafetyd** — Distilled `install/hardware/apple/audio.sh` enables the daemon; MX health checks and Asahi package lists assume it; T3 holding "speakersafetyd until Scott" double-enables.
3. **zram layout** — Identical `90-omarchy.conf` already in quattro settings. A boot-package copy is a pacman file conflict with `omarchy-settings`.
4. **Trackpad / Hyprland input** — Distilled `touchpad.sh` appends user `input.lua`; MX ships device lines in `default/hypr/input.lua` plus `apple.lua` cursor. Two writers.
5. **HID initramfs modules** — Byte-identical `fix-asahi-hid-race.sh` in both trees; Scott's plan keeps it out of package 1; T3 would take it; `quattro-upstream` `all.sh` still runs the leaf.

Package 1's validated Wi-Fi iwd file and MX's Intel `brcmfmac` modprobe are **not** a collision: MX already returns on Apple Silicon.
