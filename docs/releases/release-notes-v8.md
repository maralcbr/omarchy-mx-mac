# Omarchy for Apple Silicon — M1 Pro installer

This release installs **Omarchy**, an Arch Linux desktop built on Asahi Linux,
onto a MacBook Pro with an M1 Pro chip, alongside macOS. You keep macOS. You
choose which one to boot.

Everything you need is in this release: a Mac app that does the install, and
the operating system it writes.

---

## What you need

- **A 14-inch MacBook Pro (2021), M1 Pro** — model identifier `apple,j314s`.
  The installer refuses to run on any other machine. To check yours:
  Apple menu → About This Mac.
- **macOS up to date.** Install pending macOS updates first and reboot.
- **137 GB of free disk space.** The installer will not shrink your macOS
  partition; it needs genuinely free space to work with.
- **Mains power, and keep it plugged in.** The install takes 15-25 minutes and
  must not be interrupted.
- **An internet connection.** The app downloads about 3.6 GB.
- **Your Mac's login password**, and one restart into Recovery mode. Only you
  can do those two things.

Back up anything you care about before you start. This writes to your disk.

---

## Installing

1. **Download** `Omarchy-MX-Mac-Installer-0.8.0.zip` from the Assets list
   below.
2. **Unzip it** by double-clicking. You get
   `Omarchy MX Mac Installer.app`.
3. **Open the app.** It is signed and notarized by Apple, so it opens
   normally — no security warning, no right-click trick.
4. **Follow the six screens:**
   - **Check** — confirms your Mac is supported.
   - **Plan** — downloads and verifies the operating system, showing progress.
     This is the long part.
   - **Authorize** — asks for your password. It is used once and kept only in
     memory, never written anywhere.
   - **Install** — writes the system and reads every write back to confirm it.
   - **Recovery** — tells you to finish in Recovery mode. **This step is
     yours:** shut down, then hold the power button until "Loading startup
     options" appears, choose Options, log in, and follow the instructions.
     Apple requires a human here; no app can do it for you.
   - **Boot** — confirms the system is ready.
5. **Restart.** Hold the power button to choose between macOS and Omarchy at
   any time.

Once you are in Omarchy, `asahi-bless` and `startup-disk` let you pick the
next boot OS from Linux, without Recovery mode.

---

## What is fixed since v7

- **Audio works.** v7 installed without the Apple audio profiles, so the sound
  system fell back to the raw hardware device and the speakers were unusable.
  This release ships `alsa-ucm-conf-asahi`, so the speakers come up on the
  proper Asahi DSP profile, with `speakersafetyd` running to protect them.
- **WiFi works on its own.** In v7, WiFi only came up after running a command
  by hand, because the machine's own WiFi firmware was not copied into the
  installed system. A first-boot service now does that copy, so WiFi is
  available from the first login and stays working across reboots.
- **Bluetooth and boot tools are installed.** Bluetooth is active out of the
  box, and `asahi-bless` plus `startup-disk` are included so you can switch
  boot OS from Linux.
- **A redesigned installer app.** The old build was one dense screen of
  technical detail. It is now six clear screens with one decision each, real
  progress during the download and install, a live activity feed, and the
  technical detail tucked into Details panels for anyone who wants it.
- **You can download it.** v7 had to be hand-carried onto the machine over a
  cable — it could not be given to anyone. The operating system now ships with
  this release and the app fetches it, so this is the first version a person
  other than the author can actually install.

---

## About integrity

Every file this installer uses is pinned by its SHA-256 digest in a catalog,
the catalog is cryptographically signed, and the signed catalog and its trust
root are sealed inside the app bundle at build time.

That means the app will only accept the exact bytes it was built to expect. If
a download is corrupted, truncated, or substituted, verification fails and the
install stops before anything is written to your disk. The large OS payload is
delivered in parts; each part is checked on its own, and the reassembled whole
is checked again.

The app itself is signed with an Apple Developer ID and notarized by Apple.

`SHA256SUMS` is attached to this release if you want to verify the downloads
yourself:

```bash
shasum -a 256 -c SHA256SUMS
```

---

## Known limits

- One model only: M1 Pro 14-inch (`apple,j314s`). Other Apple Silicon Macs are
  rejected on the first screen, deliberately.
- The Recovery-mode step cannot be automated. Apple requires it.
- This is a fresh install into free space. It does not upgrade or repair an
  existing Omarchy installation.
