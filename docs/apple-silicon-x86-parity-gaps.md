# Apple Silicon ↔ x86 parity gaps

Status: findings from the first end-to-end install of
`v4.0.1-mac.2.9.090126` on the M1 Pro (`apple,j314s`), 2026-09-01.
Purpose: make an ARM install behave like an x86 install, and keep every fix
in a shape that can go upstream.

Evidence: `/tmp/omarchy-update.log` on the device, `/var/log/pacman.log`,
the boot journal, and `omarchy debug apple` (32 passed / 0 failed after the
fixes below).

## Upstreaming principle used here

A fix belongs upstream when it is written as a *general* improvement that
happens to matter more on ARM. A fix belongs in the Apple orchestrator or in
`omarchy-pkgs` when it is genuinely platform-specific. Nothing below adds an
`if apple` branch to a shared code path.

---

## Gap 1 — five default packages have no ARM binary (the big one)

**Symptom the owner hit:** `omarchy update` compiled for eleven minutes and
then failed at the very end with

```
sudo: timed out reading password
 -> error installing: [localsend … aether … xdg-terminal-exec … yay … cliamp] - exit status 1
```

**Cause:** `localsend`, `aether`, `cliamp`, `xdg-terminal-exec` and `yay` are
in the default package set (`install/omarchy-base-asahi.packages`), but the
`omarchy` ARM repository ships only 21 packages and none of these. On x86
they arrive as prebuilt binaries; on ARM every machine compiles them from
source at every update — 495 Rust crates, a Flutter application, and two Go
builds.

**Consequences beyond the slow update:** the toolchain those builds pull in
(`rust`, `go`, `cmake`, `ninja`, `bats`, `fvm`, `scdoc`, `patchelf`, `lld`)
is then reported as orphaned at the end of the same update, so the owner is
invited to delete exactly what the next update will re-download.

**Where the pipeline actually stands (checked 2026-09-01):** this is *not* a
missing configuration. `maralcbr/omarchy-pkgs` already has a PKGBUILD for
each of the five, and `pkgbuilds/asahi-repository-packages` already declares
all five among its 33 entries. The published ARM repository nevertheless
carries only 21 — the five are simply absent.

The packages are not failing to build either. Run `33478352484` on
2026-09-01 06:36 finished green: all twenty-four `build-repository` jobs
succeeded — `aether`, `cliamp`, `localsend`, `xdg-terminal-exec` and `yay`
among them — and `assemble-and-verify` passed every gate. The `publish` job
was then **skipped**, because `publish_candidate` defaults to `false`.

The earlier runs that day did fail on mirror downloads
(`error: failed to commit transaction (download library error)`), but the
gate script already retries those deliberately — "the ALARM mirrors
regularly stall or drop mid-transaction" — and the retry got through. Those
failures are noise, not the blocker.

**The actual blocker is a one-line bug in the workflow.** Publishing
requires the `signing-check` job, and that job fails:

```
gpg: signing failed: No passphrase given
```

`bin/asahi-signing-subkey-validate` reads a `GPG_PASSPHRASE` environment
variable and makes a probe signature with the signing subkey. The
`signing-check` step passes `OMARCHY_ARM_REPOSITORY_SIGNING_SUBKEY`,
the fingerprint and the admin token — but not the passphrase. The same
workflow already passes it correctly in the publish job:

```yaml
GPG_PASSPHRASE: ${{ secrets.OMARCHY_ARM_REPOSITORY_SIGNING_PASSPHRASE }}
```

so the secret exists and only the gate is missing it. Adding that one line
to the `signing-check` step's `env:` block is the whole fix; no key, secret
or package list has to change.

**Status 2026-09-01 — candidate published, parity proven.** Both workflow
bugs are fixed (the passphrase as PR #55, the plan path as PR #56) and
`asahi-packages-candidate-901e39bdc0dd42a93644bce14a07eeb9bb18a12c` is live:
33 repository packages, 6 runtime, 39/39 signatures, signed `omarchy.db`.

Measured against that repository from the M1 itself, the five arrive as
prebuilt binaries:

| package | version | download |
| --- | --- | --- |
| aether | 4.27.2-1 | 3.51 MiB |
| cliamp | 1.57.1-1 | 7.33 MiB |
| localsend | 1.17.0-3 | 10.29 MiB |
| xdg-terminal-exec | 0.14.0-1 | 16.62 KiB |
| yay | 12.6.0-1 | 2.81 MiB |

That is the gap closed: about 24 MiB of downloads in place of eleven
minutes of compiling 495 Rust crates, a Flutter application and two Go
builds — the x86 experience.

**Remaining, and owner-owned.** Installed systems read a *stable* tag, and
the image is still pinned to `asahi-packages-stable-afd72814…` (21
packages, 2026-08-25). Promotion is not a workflow dispatch: it runs
`bin/promote-asahi-package-candidate`, which requires the signing key and an
**acceptance evidence file** naming the exact candidate — a deliberate gate
saying a candidate was tested before it becomes stable. Once promoted,
repoint the `[omarchy]` `Server` in
`configs/airootfs/usr/share/omarchy-iso/pacman-online-installed-arm.conf`
at the new stable tag and rebuild the image.

**Priority: highest.** Everything else in this document is a robustness
improvement; this one is the actual parity difference.

**Installed systems no longer wait for a rebuilt image.** `omarchy update`
now runs `omarchy-update-asahi-repository` on Apple Silicon, right after the
runtime bundle and before the package sync. It reads the `omarchy-pkgs`
release listing, picks the newest non-draft, non-prerelease, immutable
`asahi-packages-stable-<commit>` release, verifies that release's signed
`CANDIDATE` descriptor against the shipped
`default/omarchy-arm-repository.asc` signing subkey and the tag's own source
commit, refuses to move to a lower signed workflow run, and then rewrites only
the `Server` line of the existing `[omarchy]` block after backing the file up
under `/var/lib/omarchy/backups/`. The ISO pin above is still worth updating so
fresh installs start current, but it is no longer the only way forward.

---

## Gap 2 — a long build outlives the sudo credential cache

**Cause:** an update authenticates once, then spends minutes in unprivileged
steps. `sudo`'s five-minute cache expires during a long build, and the
install that follows prompts for a password nobody is watching.

**Fix (landed, one line):** `bin/omarchy-update-aur-pkgs` now does
`source omarchy-sudo-keepalive` before `yay -Sua`.

Omarchy already ships that helper, and `omarchy-pkg-aur-install` and
`omarchy-pkg-install` already use it for exactly this reason — the update's
own AUR step was simply the one path that had been missed. Reusing it beats
adding a second mechanism: nothing new to review, and the behaviour matches
what a user gets when installing an AUR package by hand.

General by construction: any machine whose builds outlast the cache hits
this; ARM merely hits it on every update. Covered by
`test/shell.d/update-aur-keepalive-test.sh`, which also pins that an
unreachable AUR still asks for no password at all.

---

## Gap 3 — Bluetooth is dead on the first boot after an install

**Cause:** both radios probe at ~4.5 s, before `omarchy-vendor-firmware`
has extracted the machine-specific firmware:

```
hci_bcm4377 0000:01:00.1: Unable to load firmware; tried 'brcm/brcmbt4387c2-apple,maldives-u.bin' …
hci_bcm4377 0000:01:00.1: probe with driver hci_bcm4377 failed with error -2
```

The unit then reloaded `brcmfmac` only, so Wi-Fi recovered and Bluetooth did
not. The firmware was on disk the whole time; a `modprobe -r hci_bcm4377 &&
modprobe hci_bcm4377` brought the controller up immediately, which confirms
the diagnosis.

**Fix (landed):** the unit's `ExecStartPost` now reloads every radio that
depends on the vendor firmware. Apple-specific by nature, so it lives in the
Apple orchestrator phase (`finalized_phases.py`), not in shared code.
Regression test: `test_vendor_firmware_reloads_both_radios`.

---

## Gap 4 — a single-mirror repository with no fallback

**Symptom the owner hit:** the VS Code install failed. `pacman` logged the
start at 16:00:52 and never opened a transaction, i.e. the 165 MB download
failed. A retry installed it cleanly.

**Cause:** ARM package downloads have no meaningful redundancy. `[omarchy]`
has exactly one `Server` (a GitHub release URL), and `[core]`/`[extra]`/
`[alarm]` list two Arch Linux ARM mirrors — where an x86 install draws on
dozens.

**Not the cause of Gap 1** — that turned out to be a workflow bug — but real
all the same. The owner's VS Code install died mid-download, and several ARM
package builds the same day died on
`failed to commit transaction (download library error)`. CI absorbs it
because the gate script retries deliberately; a user at a terminal has no
such cushion and simply sees the install fail.

**Suggested fix (not landed, needs a decision):** add mirrors — a proper
mirrorlist for the ARM repositories, and/or a retry with backoff around the
CI transaction step. Retrying by hand worked in both observed cases, which
suggests plain transience rather than a broken host.

---

## Non-issues confirmed (do not "fix" these)

- **Audio is correct.** The Asahi speaker path is a wireplumber filter chain
  (`audio_effect.j314-convolver [Audio/Sink]`, and it is the default sink),
  not a plain ALSA sink. A checker that only reads the `Sinks:` list will
  wrongly report it missing — `omarchy debug apple` was corrected to read the
  `Filters:` section, and now treats raw-sinks-only as a failure.
- **The two shipped fixes hold on hardware.** `[omarchy]` and
  `[asahi-alarm]` are both configured, and `speakersafetyd` is enabled and
  active on a fresh install.

## Gap 5 — our own build broke `omarchy commands --check`

The build installs `/usr/bin/omarchy-apple-installed-verify` on the target,
where Omarchy's command router picks it up. It carried no `omarchy:` metadata,
so the installed system failed its own command check:

```
Missing metadata summary: omarchy-apple-installed-verify
Command metadata check failed (3 issues)
```

**Fix (landed):** the script now declares `omarchy:summary` and
`omarchy:hidden=true`, so it stays out of the user-facing command list and
the check passes. Anything else the Apple build drops into `/usr/bin` must
do the same.

The other two reported commands (`omarchy-nvim-refresh`,
`omarchy-nvim-setup`) are not ours and are unchanged.

## Gap 6 — the default package list itself was short by 19 packages

**What was wrong:** `install/omarchy-base-asahi.packages` was authored as a
subset of the x86 list and never caught up. Against the x86 default set it was
missing 22 entries, of which three are renames (`mise-bin`→`mise`,
`nvim`→`neovim`, `quickshell`→`quickshell-git`) and 19 are real gaps:

| Why it was missing | Packages | Fix |
|---|---|---|
| Built for ARM but never listed | omacut, omawrite | list edit |
| In Arch Linux ARM `extra` but never listed | gpu-screen-recorder, libreoffice-fresh, moonlight-qt, qt6-imageformats | list edit |
| PKGBUILD declared `arch=('x86_64')` although the source is arch-neutral | tzupdate, tensaku, asdcontrol, hyprland-preview-share-picker, tobi-try | `arch=` widened, added to the ARM repository |
| PKGBUILD existed only upstream | herdr, omacalc, ttfx | ported into the fork, added to the ARM repository |
| No aarch64 binary anywhere | obsidian (bundled Electron), obs-studio (no CEF), dotnet (AUR `dotnet-core-bin`), qemu-user-static + binfmt (Debian static build), pinta (arm64 .NET RID, self-contained SDK) | new aarch64-only PKGBUILDs in the ARM repository |

Four interim substitutes are retired at the same time, because the real
package now exists: `gnome-calculator`→`omacalc` (calculator keybinding
restored to upstream's), `wf-recorder`→`gpu-screen-recorder`,
`python-terminaltexteffects`→`ttfx`, and `tensaku`. The migration
dispositions that skipped the upstream migrations for tensaku, omacalc,
herdr and ttfx now run them, and migration `1788486400` installs the whole
set on machines that were installed before this change (a no-op on x86).

**Related install-time gap, fixed with it:** `bin/omarchy-install-asahi-fresh`
still compiled ten packages with makepkg on the target machine, behind a
temporary build account with a passwordless pacman grant. Every one of those
packages has shipped as a signed binary since the 901e39bd candidate, so the
installer now installs the whole list in one pacman transaction and the build
account, sudoers drop-in and pkgbuild checkout are gone.

**Repository inventory change:** 24 sources / 33 packages → 37 sources / 52
packages (dotnet is a six-way split, qemu-user-static a two-way split). The
counts are pinned in `test/asahi-package-repository` and both candidate
workflows in omarchy-pkgs.

## Cosmetic

`macsmc-battery-charge-control-end-threshold.{path,service}` ship with the
executable bit set; systemd warns on every boot. One-line packaging fix,
belongs with whoever owns that unit.
