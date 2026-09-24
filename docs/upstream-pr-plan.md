# Upstream PR plan (T6)

DOCUMENT ONLY. No PR is opened to `omacom/omarchy`, `omacom/omarchy-mac`,
or `omarchy-mac/omarchy-pkgs-aarch64` until the owner has validated a
from-scratch encrypted image install (PLAN S1/S2). Tonight everything
Apple-specific ships from our repos. Classification:
`docs/apple-feature-delta.md`. Package contract: PLAN.md / INTERFACES.md.
Scott's values: `Upstream-Status: candidate | experimental | temporary`
(`omacom/omarchy-mac` `docs/upstream-integration-plan.md`).

Read-only refs, 2026-09-20:

| Tree | SHA | Blobs |
| --- | --- | --- |
| this worktree (`e/T6` = `e/T0b`) | `99fa59ca` | 2232 |
| `omacom/omarchy` `quattro` | `e38c1d12` | 1849 |
| `omacom/omarchy-mac` `quattro-upstream` | `fe18cd6c` | 1980 |

`gh api repos/omacom/omarchy-mac/branches/quattro-upstream`: protected,
Scott Jones, 2026-09-20. Path compare vs this tree: 1706 shared, **526
mx-only**, **274 quattro-upstream-only**. Commit compare vs `quattro`:
**955 ahead / 426 behind** (PLAN said 954/426). Vs `quattro-upstream`:
955 ahead / 460 behind. GitHub's compare `files` count truncates at 300.

---

## 1. PRs to `omacom/omarchy` quattro

Delta home `omacom/omarchy quattro` is 15 classified paths. Nine are
already byte-identical at `e38c1d12` — no PR.

Already on quattro: `install/hardware/apple/fix-suspend-nvme.sh`,
`fix-t2.sh`; `bin/omarchy-brightness-display-apple`,
`omarchy-hyprland-monitor-focused-apple`, `omarchy-drive-password`;
migrations `1785944594.sh`, `1785273276.sh`, `1789325478.sh` (already
`uname -m` gated), `1785013000.sh`, `1784961000.sh`;
`test/shell.d/brightness-display-apple-cache-test.sh`.

Do not fold these into open `#9835` (`omacom/asahi-overlay`, still
unmerged). Split them. `#9835` remains Scott's distillation source, not
the submission vehicle.

### Q0 — Apple Silicon detector (prerequisite)

- **Title:** Detect Apple Silicon from the device tree
- **Files:** `bin/omarchy-hw-apple-silicon`;
  `test/shell.d/apple-silicon-test.sh` (detector cases only; drop MX
  channel-set/dev/stable assertions)
- **Rationale:** Scott's add-on lists this as an `omarchy` runtime
  dependency. The skip PRs below call it. It cannot live in an Apple
  package (delta §4) but it must live in desktop `omarchy`. Already on
  `quattro-upstream` (plus alias `bin/omarchy-hw-apple`).
- **Upstream-Status:** `candidate`
- **Depends on:** nothing. Lands before Q2 and Q3.

### Q1 — SPI keyboard DMI hardening

- **Title:** Tolerate missing DMI in the MacBook SPI keyboard probe
- **Files:** `install/hardware/apple/fix-spi-keyboard.sh`;
  `test/shell.d/apple-legacy-hardware-probe-test.sh`
- **Rationale:** quattro's `cat /sys/class/dmi/id/product_name` fails
  closed on VMs/CI with no DMI. MX already uses a missing-file default.
  Intel-only; no detector.
- **Upstream-Status:** `candidate`
- **Depends on:** nothing. Can land in parallel with Q0.

### Q2 — Skip Broadcom firmware-supplicant quirk on Apple Silicon

- **Title:** Do not disable brcmfmac firmware offload on Apple Silicon
- **Files:** `install/hardware/apple/fix-brcmfmac-supplicant.sh`;
  `migrations/1786391100.sh`; `test/shell.d/apple-brcmfmac-cleanup-test.sh`
  (pairs with already-mx `migrations/1789172112.sh`, which stays mx)
- **Rationale:** the Intel/T2 `feature_disable=0x82000` drop-in times out
  firmware commands on BCM4387 and breaks scan. MX adds
  `omarchy-hw-apple-silicon && return 0`. quattro cannot take that line
  until Q0 exists.
- **Upstream-Status:** `candidate`
- **Depends on:** Q0.

### Q3 — Skip Omarchy/T2 headers migration on Apple Silicon

- **Title:** Skip linux-omarchy/linux-t2 header repair on Apple Silicon
- **Files:** `migrations/1789444024.sh`;
  `test/shell.d/kernel-headers-migration-test.sh` (already stubs the
  detector; quattro lacks the migration file on `quattro-upstream`)
- **Rationale:** the migration installs x86 headers. MX exits via the
  detector; quattro has the migration with no skip.
- **Upstream-Status:** `candidate`
- **Depends on:** Q0.

Order: Q0 → Q1 (parallel with Q0) → Q2, Q3. After S1/S2, not tonight.

### hyprwm (owner submits; those projects take no AI-written PRs)

These are **not** `omacom/omarchy` PRs. The owner files them by hand
from our `omarchy-pkgs` patches / notes. Agents do not open, draft, or
ghost-write them.

| Upstream | What | Status |
| --- | --- | --- |
| `hyprwm/aquamarine` | Re-read `possibleCrtcs` on connector rescan so a DCP-rerouted Type-C port gets a CRTC without restarting the compositor. Patch: `pkgbuilds/aquamarine/0001-drm-re-read-possible-CRTCs-when-rescanning-connectors.patch` (From: Marcelo Alcantara). | Owner PR. Until merged we carry the patch in `[omarchy]`. |
| `hyprwm/aquamarine` #410 | Release output on disconnect (`3c3292c1`, fixes #386). We carry `0002-drm-release-output-on-disconnect.patch`. | Already upstream. Owner does not re-submit; drop 0002 when we consume a release that includes it. |
| `hyprwm/Hyprland` | Hardware-cursor lag on Apple DCP (workaround `default/hypr/apple.lua` `no_hardware_cursors = true`). | Owner PR if compositor-side; otherwise the workaround stays package 1-later / `omarchy-mac-boot`. |
| `hyprwm/Hyprland` or aquamarine | `libseat` `TakeDevice` ENOENT when HID nodes rebind (trackpad dead for the session). Workaround is HID modules in initramfs (package 2). | Owner only if we also want a compositor retry; the boot fix is ours. |

`bin/omarchy-hyprland-monitor-focused-apple` is already on quattro
(Studio/XDR helper). It is not a hyprwm project change.
Naeem's Hyprland software-renderer work is Scott's plan, not this list.

---

## 2. PRs to `omacom/omarchy-mac`

Package 1 already exists (`packages/omarchy-mac/`, 25 files on
`fe18cd6c`; validated M2 Max add-on `0.1.0-4`: reboot, Wi-Fi, playback,
mic). It owns iwd, wifi-resume, mic map, `asahi-headset-mic.conf`,
notch. It selects no kernel, has no installer, installs no trust.

We vendor the rest in **our** `omarchy-mac-boot` (T3) with `# Origin:
omarchy-mx-mac <path>` until the owner-validated PRs below. Consuming
Scott's signed, pinned `omarchy-mac` package is allowed; otherwise keep
vendoring.

### What moves from `omarchy-mac-boot` into Scott package 1

Land as four focused PRs after S1/S2, each one owner class. Do not dump
boot files into package 1.

| PR | Title (sketch) | Payload today in `omarchy-mac-boot` | Origin |
| --- | --- | --- | --- |
| M1a | Enable speakersafetyd from package 1 | `files/usr/lib/systemd/system-preset/80-omarchy-mac.preset` line `enable speakersafetyd.service` (and drop MX/debug double-enable). Distilled leftover `install/hardware/apple/audio.sh` + mx `migrations/1787552067.sh` join this. | preset / `audio.sh` |
| M1b | Speaker no-suspend | No DSP overlay: mx dropped `software-dsp.lua` after it hung WirePlumber on J293 (#173). Do **not** ship `/etc/wireplumber/wireplumber.conf.d/asahi-audio-no-suspend.conf`: `omarchy-settings-dev` owns that path until a coordinated transfer (INTERFACES v3 item 2a). Headset file in package 1 is a different filename; that does not free the `/etc/` drop-in. | `default/` source; `/etc/` stays settings |
| M1c | Apple zram drop-in | must **not** be `90-omarchy.conf` (quattro settings already ships that path — pacman conflict). Vendor `90-omarchy-mac.conf` or wait. T3a currently copied the colliding name; rename before any publish. | `default/systemd/zram-generator.conf.d/90-omarchy.conf` |
| M1d | Trackpad / cursor bindings | Hypr snippet: `apple-mtp-multi-touch` / `apple-spi-trackpad` `tap_to_click = false`; `no_hardware_cursors` from `default/hypr/apple.lua`. Distilled `install/user/hardware/apple/touchpad.sh` becomes a no-op when the snippet exists. | `default/hypr/input.lua` (two device lines only), `default/hypr/apple.lua` |

### Proposed package 2 (`omarchy-mac-boot` → Scott)

One PR (M2) proposing package 2 in `omacom/omarchy-mac`, built from our
pkgs until Scott accepts. Scope is what package 1 excludes:

- mkinitcpio: `90-omarchy-asahi.conf`, hook names `asahi` and
  `omarchy-vendorfw` (keep names installed Macs already reference),
  `/etc/initcpio/install/omarchy-vendorfw`, vendorfw units
- HID early-load: `files/etc/mkinitcpio.conf.d/apple_hid_modules.conf`
- btrfs static-nodes: `kmod-static-nodes.service.d/10-before-tmpfiles-setup-dev.conf`
- `mac-image-finalize` (+ `apple-image-finalize` symlink)
- first-boot / encryption / recovery keyslot / m1n1 stage-2 rebuild
  policy (T3b/T4; `omarchy-provision-owner` stays in mx)

`Upstream-Status:` M1a–d `temporary` in our package until merged, then
the Origin header comes off; M2 `candidate` as a new package.

### Collision resolutions (delta § “five collisions”)

1. **WirePlumber `conf.d`.** Package 1 keeps `asahi-headset-mic.conf`.
   `/etc/wireplumber/wireplumber.conf.d/asahi-audio-no-suspend.conf`
   stays in `omarchy-settings-dev` until a coordinated transfer
   (INTERFACES v3 item 2a); `omarchy-mac-boot` must not claim it.
   We may still vendor DSP lua. Never a second headset file. M1b
   later moves no-suspend into package 1 after that transfer.
2. **speakersafetyd.** One enabler. Prefer M1a. Until then the T3
   preset may enable the unit; mx must not, and Scott's `audio.sh` must
   `pacman -Qq omarchy-mac && return 0` (and the same for
   `omarchy-mac-boot` while we still own it).
3. **zram.** Do not install `90-omarchy.conf` from the boot package.
   Rename to `90-omarchy-mac.conf` or omit until M1c. quattro and
   `quattro-upstream` already have the settings copy.
4. **Trackpad / Hyprland.** One writer. Package-owned snippet; Scott
   `touchpad.sh` already no-ops if keys exist; mx `all.sh` / user
   finalize must not append `omarchy-apple-touchpad`. `input.lua` on
   quattro stays generic; Apple device lines leave mx defaults once
   M1d/T3 owns them.
5. **HID initramfs.** Package 2 owns `apple_hid_modules.conf`.
   `quattro-upstream` `install/hardware/all.sh` still runs
   `fix-asahi-hid-race.sh` (byte-identical with mx). That leaf becomes
   `omarchy-hw-apple-silicon || return 0; pacman -Qq omarchy-mac-boot && return 0`.

Not a collision: package 1 iwd vs mx Intel `brcmfmac` modprobe (mx
already returns on Apple Silicon).

### Keep vendoring with `# Origin:` until those PRs

Present in T3a `pkgbuilds/omarchy-mac-boot/files/` tonight:

```
# Origin: omarchy-mx-mac install/hardware/apple/fix-asahi-hid-race.sh
# Origin: omarchy-mx-mac install/hardware/apple/fix-asahi-btrfs-race.sh
# (historical, removed in T3a round 2: asahi-audio-no-suspend.conf and the zram 90-omarchy.conf stay owned by omarchy-settings-dev)
```

Still required (T3 add, same header style):

```
# Origin: omarchy-mx-mac default/hypr/apple.lua
# Origin: omarchy-mx-mac default/hypr/input.lua (apple-mtp / apple-spi lines)
```

Preset `enable speakersafetyd.service` is our stand-in for M1a; header
that line with Origin `install/hardware/apple/audio.sh` when Scott's
leaf is the source of truth. Image-written vendorfw / `90-omarchy-asahi.conf`
are package 2 payload, not package 1.

Do not copy into `omarchy-mac-boot`: distilled `pacman.sh` (unsigned
`[omarchy-aarch64]`), Electron GL, video-decode, Obsidian, share-picker,
ALS, Snapper, Steam FEX, package 1 itself (`packages/omarchy-mac/`).

Order vs quattro: Q0 before any leftover leaf we ask Scott to guard
with the detector. M2 can proceed from our pkgs without M1a–d. M1a–d
need S1/S2 plus the collision guards in mx `install/hardware/apple/*.sh`.

---

## 3. Kernel lane tools → `omarchy-mac-boot` (PR after validation)

Stays in mx **tonight** (INTERFACES §3). This later extraction
**supersedes** `docs/apple-feature-delta.md` §4 ("Impossible to
move" for kernel lane / Aurora tools). The delta forbade a
same-night move into the boot package because that would couple
boot-file ownership to lane policy without a migration. INTERFACES
§3 authorizes the **staged** move after validation: one coordinated
mx + pkgs release transfers the helpers in the same `pacman -Syu`
so hook, body, and caller do not split across packages. After S1/S2
that release moves:

| Path | Role under `omarchy-update` |
| --- | --- |
| `bin/omarchy-apple-silicon-channel` | channel record, lane, holds, `locked` / `verify-locked` |
| `bin/omarchy-update-aurora-repository` | pin `[omarchy-aurora]`; `--complete` after migrate |
| `bin/omarchy-apple-silicon-boot-check` | byte-compare kernel/initramfs/GRUB/m1n1; never `update-m1n1` |
| `bin/omarchy-apple-silicon-retire-saved-modules` | post-downgrade module retire + m1n1 rebuild |
| `bin/omarchy-update-aurora-verify` + `default/libalpm/hooks/01-omarchy-aurora-verify.hook` | PreTransaction AbortOnFail on `linux-aurora*` |

**Keep in mx:** `bin/omarchy-channel-set`. It is the x86 desktop
channel command; only its Apple Silicon branch takes the update lock
and calls `omarchy-apple-silicon-channel switch` then `omarchy-update -y`.
Moving the binary into an aarch64 boot package would pull that package
onto Intel or leave x86 without `omarchy-channel-set`.

### Why it waited

`omarchy-update` takes `omarchy-update-lock`, then
`omarchy-update-system-pkgs` → `omarchy-update-aurora-repository`
(nests **update lock then channel lock**; refuses to wait the other
way), pacman, `omarchy-migrate`, then
`omarchy-update-aurora-repository --complete` (retire-saved-modules,
boot-check, lane-write). The ALPM hook runs **inside** pacman, not
under the update lock. Splitting hook vs body vs caller across packages
on different releases leaves a Mac that can abort every kernel
transaction or skip verification. Installed Macs therefore need **one
migration release** where `omarchy` / `omarchy-settings` drop the files
and `omarchy-mac-boot` gains them in the same `pacman -Syu`.

### Migration steps (that later release)

1. `omarchy-mac-boot` adds the five Apple helpers + hook at the same
   `/usr/bin` and `/usr/share/libalpm/hooks` paths; `backup=` the hook.
2. Same tag: `omarchy` / `omarchy-settings` stop shipping those paths
   (file ownership transfer, not a rename).
3. `omarchy-update` and `omarchy-channel-set` keep calling the same
   command names; no lock-order change.
4. Admission/target rename `omarchy-apple-boot` → `omarchy-mac-boot`
   already belongs to T3; this PR must not fight that.
5. Tests move with the tools (`apple-silicon-channel-test.sh`,
   `apple-silicon-boot-check-test.sh`,
   `apple-silicon-retire-saved-modules-test.sh`,
   `aurora-repository-update-test.sh`, `aurora-edge-update-test.sh`,
   `aurora-verify-hook-test.sh`, `update-system-pkgs-aurora-test.sh`).
6. Release notes: finish this update before the next `omarchy-channel-set
   edge|rc|stable`; do not reboot if `--complete` left
   `/run/omarchy-reboot-blocked`.
7. Then optionally propose the same files into Scott package 2 (M2
   follow-on). Not a desktop quattro PR. Scott package 1 selects no
   kernel.

`Upstream-Status: temporary` on the mx copies until the split; the
package carries them afterwards.

---

## 4. mx `main` → `quattro-upstream` cutover

**After** T7 ships stable from an E image and S1/S2 pass. Not overnight.
**Merge to adopt the upstream desktop tree; do not rebase 955 commits.
Never force-push published history.**

`quattro-upstream` is Scott's distillation of this fork (incl. `#9835`)
onto quattro. Rebasing 955-ahead / 426-behind history onto `fe18cd6c`
replays every Apple commit through 460 desktop commits we have not
taken. The cut is a merge that keeps current `main` as a parent and
adopts the selected `quattro-upstream` tree plus the overlay below.

### Order relative to shipping stable

1. T7 publishes `mac-image-<S>-<lane>` from **current** mx `main`.
2. S1/S2 on that image (encrypted, three lanes).
3. Open Q0–Q3 and M1/M2 from this plan (still no cutover).
4. Merge `omacom/omarchy-mac` `quattro-upstream` (`fe18cd6c` or newer)
   into mx `main`, keeping current `main` as a parent. The merge tree
   is that upstream commit **plus** the overlay below. A
   `mx-pre-cutover` tag may bookmark pre-merge `main`; it does not
   replace ancestry. Published history is never force-pushed.
5. Fast-forward testers via a packaged mx release, not `git pull`
   on `/usr/share/omarchy`.
6. Mechanical `asahi`→`mac` rename (PLAN R) is last and separate.

### Overlay (stays fork-only on mx)

Counted from mx-only paths (526). Keep:

| Tree | Files | Why |
| --- | --- | --- |
| `apps/omarchy-apple-installer/` | 193 | macOS app. Scott reuses; not add-on payload |
| `…/Engine/overlay/` | 20 | closed asahi-installer overlay |
| `…/Release/` + `scripts/make-unsigned-catalog.py` + `scripts/publish-channels` | 16 | signed catalogs / trust root |
| `evidence/` | 22 | hardware acceptance |
| `docs/apple-silicon-*`, `docs/releases/`, `docs/apple-feature-delta.md`, this file | ~50 | fork records |
| kernel lane tools + Aurora pin/hook + Asahi package lists + signing key + platform JSON + `omarchy-install-asahi-fresh` | see delta §1.2, §1.5 | until §3 split |
| `.github/workflows/{packages,release,optional-packages,tests,pages}.yml` | 5 | mx CI |

`omarchy-provision-owner`, `omarchy-hw-apple-silicon`,
`omarchy-update-apple-boot-admission` stay in the `omarchy` package
(detector becomes Q0; the rest stay mx).

### Drop / do not import

From **our** 526: leaves T3 already owns once `pacman -Qq
omarchy-mac-boot` (HID, btrfs, speaker-pop) become no-ops; Apple
lines in `default/hypr/input.lua` once M1d/T3 owns them. Keep
`bin/omarchy-update-asahi-bundle` at cutover (`omarchy-update` still
calls it); the delta's later drop is not this merge.

From **their** 274: do **not** copy `packages/omarchy-mac/` (25) into
mx — depend on the signed package. Do not copy
`install/hardware/apple/pacman.sh` (unsigned `[omarchy-aarch64]`; mx
keeps the signed `[omarchy]` / `[omarchy-aurora]` writers). HID leaf
stays a guarded no-op, not a second writer. Electron/video-decode/ALS/
Steam leftovers stay Scott desktop, not boot.

Shared 1706 paths: take `quattro-upstream` **content** for generic
desktop (we are 426 behind; 79 theme files unique each way — their
theme layout wins). Re-apply Apple-gated mx files quattro-upstream
did not distill. Upstream's updater and migrator lack the signed-
repository update, Aurora completion/reboot checks, kernel-channel
routing, and migration skip handling, so the preserved set must
include those callers **and** every lane tool they invoke:

- `install/hardware/pacman.sh` (signed channel)
- `install/config/enable-services.sh` (oomd skip)
- `bin/omarchy-update-system-pkgs` (Aurora + boot admission)
- `bin/omarchy-update`
- `bin/omarchy-channel-set`
- `bin/omarchy-migrate`
- `bin/omarchy-update-asahi-bundle`
- `bin/omarchy-update-asahi-repository`
- `bin/omarchy-update-aurora-repository`
- `bin/omarchy-apple-silicon-channel`
- `bin/omarchy-apple-silicon-boot-check`
- `bin/omarchy-apple-silicon-retire-saved-modules`
- `bin/omarchy-update-aurora-verify`
- `default/libalpm/hooks/01-omarchy-aurora-verify.hook`

Taking only the first three interleaves would drop the signed
`[omarchy]` / `[omarchy-aurora]` update, Aurora `--complete` /
reboot-block, Apple Silicon channel routing, and Asahi skip markers.

### Cutover risks (highest first)

1. **Installed Macs get the cutover as packages.** The two-parent merge keeps
   `main` fast-forwardable, but installed Macs never pull git: the cutover is a **pacman release**
   whose files match the overlayed tree, with migrations that no-op on
   machines that already applied HID/btrfs/audio/trust. Git `main`
   keeps both parents; do not force-push.
2. **Trust and leftovers.** Importing `pacman.sh` or skipping the
   signed-channel interleave unpins `[omarchy]` / `[omarchy-aurora]`.
3. **Five collisions on first mixed update.** quattro-upstream `all.sh`
   still runs HID + `audio.sh` + `touchpad.sh` while T3 owns those
   files — `.pacnew` or double-enable unless the guards land in the
   **same** release as the overlay.
4. **Lane tools still in mx** during the cut (correct). Moving them in
   the same cutover as the 426-behind desktop merge couples kernel
   verification to a 274-file import. Do §3 in a later release.
5. **Themes 79/79.** Taking their tree drops mx-only theme files;
   keeping ours drops quattro theme work. Take upstream; re-add only
   files we still ship that they lack.

---

## Counts (open after S1/S2, not tonight)

| Target | PRs |
| --- | --- |
| `omacom/omarchy` quattro | **4** (Q0–Q3). 9 identical quattro-row files: 0 PRs. |
| `omacom/omarchy-mac` | **5** (M1a–d package 1, M2 package 2). |
| `hyprwm/*` | **1** owner-personal (aquamarine CRTC). #410 already merged. Hyprland cursor/libseat optional, owner-only. |
| lane-tools split | **1** later, our `omarchy-mac-boot` + mx (not omacom tonight). |
