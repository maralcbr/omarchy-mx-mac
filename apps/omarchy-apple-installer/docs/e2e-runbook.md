# Omarchy v8 — full end-to-end test runbook

This is the whole test, start to finish, in order. It proves that a person who
was handed nothing but a GitHub link can install Omarchy on an M1 Pro, that the
hardware works without hand-holding, that macOS is untouched, and that Omarchy
boots twice.

Two people are involved:

- **You (owner)** — at the M1. Steps marked **OWNER** need your hands: your
  password, a click, or a Recovery-mode restart. Nobody else can do them.
- **Me (agent)** — on the M4, over the Thunderbolt cable. Everything else.

Anything can be stopped at any point. Nothing writes to the M1 until step 5.

---

## Before you start

- The M1 is awake, logged in, plugged into power, and connected to the M4 by
  the Thunderbolt cable.
- The release is already published on GitHub with the app zip attached.
- Write the tag down here before you begin, and use the same one everywhere:

  ```
  TAG=<the published tag, e.g. v0.8.0-m1>
  RELEASE=https://github.com/maralcbr/omarchy-mx-mac/releases/tag/$TAG
  ```

- Expect about 2 hours end to end, most of it waiting on a download and two
  reboots.

---

## Step 1 — Pre-clean the M1

Removes the old Omarchy install and every trace of the old app, so the test
starts from a genuinely clean machine. macOS, Recovery, and your files are
never touched.

**First, look at the plan without changing anything:**

```bash
/Users/maralc/dev/omarchy/iteration2/preclean-m1.sh
```

Read what it prints. It shows the live partition table, which partitions it has
decided are protected (macOS, Recovery, the Apple ISC partition), and exactly
which partitions it would erase. If anything is ambiguous it stops on its own
and erases nothing.

**Check three things before going further:**

1. The protected list contains the big macOS partition and the Recovery
   partition.
2. The deletion list contains only Omarchy things: the Omarchy APFS stub, the
   ESP named `EFI - OMARC`, and the two Linux partitions.
3. The sizes look right — macOS should still be roughly 857 GB.

**OWNER: say go.** Then:

```bash
/Users/maralc/dev/omarchy/iteration2/preclean-m1.sh --confirm
```

It deletes the Omarchy APFS container, frees each Omarchy partition by its
UUID (not by name — names shift as space is released), clears the installer's
staging and state folder, and removes old copies of the app from
`/Applications` and `~/Downloads`. It prints what it did.

**Write down the protected partition UUIDs it printed.** Step 10 compares
against them.

---

## Step 2 — OWNER: download the app from GitHub, on the M1

This is the whole point of the test: the M1 gets the app the same way a
stranger would.

On the M1, in Safari, open `$RELEASE`, and download the app zip from the
Assets list into `~/Downloads`. Do not copy anything over the cable.

Double-click the zip to unpack it. You should get
`Omarchy MX Mac Installer.app`.

---

## Step 3 — OWNER: open the app

Double-click the app.

**What should happen:** it opens. No "unidentified developer" warning, no
right-click-Open trick, no trip to System Settings. The app is notarized, so
macOS checks it silently and lets it run.

**If macOS blocks it, stop.** That is a real failure of this release, not
something to work around. Tell me what the dialog said.

---

## Step 4 — Walk the six screens

The redesigned app is six screens, one decision each. Move through them and
check what each one shows.

1. **Check** — the app confirms this Mac is a supported M1 Pro
   (`apple,j314s`) and that the engine it carries is valid. Expect
   "Verified - supported".
2. **Plan** — the app downloads what it needs from the release and shows real
   progress. The OS payload arrives as two or more parts. Watch that the
   progress bar actually moves and that each part ends up marked verified. This
   is the slowest screen: roughly 3.6 GB.
3. **Authorize** — **OWNER: type your password.** The app says it is used once
   and kept only in memory. This is the point of no return, and it appears
   after the plan is on screen, not before.
4. **Install** — checkpoints tick over and the journal feed scrolls. Roughly
   15-25 minutes. Nothing to do but watch.
5. **Recovery** — the app tells you to finish in Recovery mode. See step 5.
6. **Boot** — after Recovery, this screen confirms the system is bootable.

**Before you type your password on screen 3, check the plan on screen 2 says
what you expect:** it should be installing into free space, not shrinking
macOS. If it proposes resizing the macOS partition, stop and tell me.

---

## Step 5 — OWNER: the Recovery step (1TR)

The app cannot do this part; Apple requires a human in Recovery mode.

1. Shut the M1 down completely.
2. Hold the power button until "Loading startup options" appears. Keep holding
   until it says that — a normal restart will not work.
3. Choose Options, then log in when asked.
4. Follow the on-screen instructions the app gave you to finish installation
   and set the boot policy.
5. Let it restart.

---

## Step 6 — OWNER: first Omarchy boot

The M1 should come up in Omarchy and reach a usable desktop. Complete any
first-run setup it asks for.

**Then tell me the machine's IP address on your network.** On the Omarchy
desktop, open a terminal and run:

```bash
ip -4 addr show scope global | grep inet
hostname
```

Read me the address. Everything in steps 7-9 runs over SSH to that address.
(The Thunderbolt bridge alias `omarchy-m1-thunderbolt` reaches the *macOS*
side only; the Linux side has no pinned alias, which is why WiFi has to work
before I can check anything.)

---

## Step 7 — Verify the hardware

Each block below is one thing that was broken or manual in v7. Run them over
SSH to the Omarchy machine.

### WiFi — must be up with no manual command

The v7 failure: WiFi firmware was not copied to the installed system, so WiFi
only worked after somebody ran a command by hand. If the previous step gave me
an IP address over WiFi at all, this is already most of the proof.

```bash
ls /lib/firmware/brcm | wc -l
ls /lib/firmware/brcm | head -20
systemctl status omarchy-vendor-firmware.service --no-pager
nmcli device status
nmcli -f ACTIVE,SSID,SIGNAL device wifi list | head -5
```

**Pass:** the `brcm` directory has files in it (not zero), the vendor-firmware
service shows as having run successfully, and `nmcli device status` shows the
wifi device `connected`.

### Audio — must use the Asahi DSP profile, not the raw hardware

The v7 failure: the Apple ALSA profiles package was missing, so PipeWire fell
back to raw `hw:0` and the speakers were unusable and unsafe.

```bash
pacman -Q alsa-ucm-conf-asahi
systemctl is-active speakersafetyd
systemctl status speakersafetyd --no-pager | head -12
wpctl status
```

**Pass:** `wpctl status` lists a real sink with an Asahi/Apple profile name
under Sinks — **not** a bare `alsa_output...hw:0` fallback. `speakersafetyd`
is `active`. The package query returns a version, not "was not found".

Then a quiet, short speaker test. **Keep the volume low.**

```bash
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.25
speaker-test -c 2 -t sine -f 440 -l 1
```

**OWNER: listen.** You should hear a short tone from both speakers, clean, at
a modest level. Stop it with Ctrl-C if it keeps going.

### Bluetooth

```bash
systemctl is-active bluetooth
bluetoothctl show
rfkill list bluetooth
```

**Pass:** `active`, `bluetoothctl show` prints a controller with `Powered:
yes`, and rfkill shows it is not blocked.

### Boot-selection tools

These let you switch back to macOS from inside Omarchy without Recovery mode.

```bash
pacman -Q asahi-bless startup-disk
which asahi-bless startup-disk
```

**Pass:** both return a version and a path.

### Capture the evidence

```bash
{
  echo "Observed: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Host: $(hostname)  Kernel: $(uname -r)"
  echo
  echo "## firmware"; ls /lib/firmware/brcm | wc -l
  echo "## network"; nmcli device status
  echo "## audio"; wpctl status
  echo "## speakersafetyd"; systemctl is-active speakersafetyd
  echo "## bluetooth"; systemctl is-active bluetooth; bluetoothctl show
  echo "## boot tools"; pacman -Q asahi-bless startup-disk alsa-ucm-conf-asahi
  echo "## packages"; pacman -Q | wc -l
  echo "## mounts"; findmnt -no SOURCE,TARGET,FSTYPE /
} > /tmp/omarchy-v8-hardware.txt
cat /tmp/omarchy-v8-hardware.txt
```

I copy that file back and store it beside the v6/v7 evidence, in the same
style: a short README naming the device, engine digest, plan digest, payload
digest and result, plus the raw capture.

---

## Step 8 — OWNER: reboot into macOS

Restart and hold the power button again to pick macOS (or use `asahi-bless` /
`startup-disk` from Omarchy if you want to prove those work too).

macOS must come up normally, with your files and settings exactly as before.

---

## Step 9 — Check macOS is unchanged

Over the Thunderbolt cable again:

```bash
ssh omarchy-m1-thunderbolt '/usr/sbin/diskutil list /dev/disk0'
ssh omarchy-m1-thunderbolt '/usr/sbin/diskutil apfs list'
ssh omarchy-m1-thunderbolt 'sudo /usr/sbin/bputil -d' 2>/dev/null || true
```

**Pass:** the macOS partition UUID and the Recovery partition UUID are exactly
the ones the pre-clean printed in step 1. The macOS partition is still its full
size — it must never have been shrunk. New Omarchy partitions are present with
new UUIDs.

---

## Step 10 — OWNER: boot Omarchy a second time

This is the step the old evidence never captured. A first boot can succeed on
leftover state; a second boot proves the installed system is genuinely
self-sufficient.

Restart into Omarchy again. It must reach the desktop, and WiFi must come up on
its own with no commands typed.

Re-run the short version of step 7 to confirm nothing regressed:

```bash
nmcli device status
wpctl status | head -20
systemctl is-active bluetooth speakersafetyd
```

---

## Step 11 — Wrap up

I do this part:

- Store the evidence in the v6/v7 style under
  `evidence/apple-silicon/<date>-m1-fresh-install-v8/`.
- Record the result in the plan document's Adjudication log.
- Update session memory.

**OWNER, last thing:** the M1's SSH and firewall were opened up for this
session. Close them again when we are done:

```
System Settings → General → Sharing → Remote Login → off
System Settings → Network → Firewall → on
```

---

## Stop rules

Any one of these ends the session. Do not work around them.

- The pre-clean cannot tell the partitions apart, or the protected list looks
  wrong.
- macOS warns about the app in step 3 (a notarization failure is a real bug).
- The plan on screen 2 proposes shrinking macOS.
- Any download part fails verification.
- The install reports a mismatch between what it wrote and what it read back.
- macOS does not boot, or its partition UUIDs changed.
- WiFi needs a manual command — that is the v7 bug, unfixed.
- Audio still shows a raw `hw:0` sink — that is the other v7 bug, unfixed.
