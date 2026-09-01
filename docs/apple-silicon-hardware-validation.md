# Apple Silicon Hardware Validation

Use this checklist only on an Apple Silicon machine running Asahi Linux. Record
results in `changelog.md`. Package/install validation in the generic VM must be
complete first so hardware failures are not confused with missing software.

## Current reference machine

Omarchy is already running successfully on the maintainer's Apple MacBook Pro
(14-inch, M1 Pro, 2021). On 2026-08-24, read-only checks captured its `aarch64`
and Apple `j314s/t6000` identity, Asahi kernel and boot packages, Mesa stack,
and signed local Omarchy release. The maintainer confirms that the normal
desktop and hardware functions are working.

This checklist is therefore an evidence-capture and regression template for
the current M1 Pro and future models, not a gate on the statement that Omarchy
works on the current machine. Detailed command output and artifacts should
still be retained when convenient so later updates can be compared against a
known-good baseline.

## Safety boundary

- Save active work and keep a local login available before network or suspend
  tests. Do not run suspend validation through an SSH-only session.
- Keep the machine on external power for update checks, but test battery state
  reporting separately.
- Start with read-only checks. Do not install, remove, or update packages merely
  to make a check pass; record the observed failure first.
- Capture the current kernel, release, package-source, and boot-file hashes
  before any later update transaction.

## Platform and release identity

- Confirm `uname -m` reports `aarch64`.
- Confirm `/proc/device-tree/compatible` identifies an Apple platform.
- Record `uname -r`, the installed `linux-asahi`, `linux-asahi-headers`, and
  `m1n1` versions, and `/var/lib/omarchy/asahi-quattro-release`.
- Confirm the configured repositories include `asahi-alarm`, `core`, `extra`,
  `alarm`, and `aur`.
- Compare the installed database with every non-comment entry in
  `install/omarchy-base-asahi.packages` and
  `install/omarchy-asahi-source.packages`; record any missing package exactly.

## Desktop and graphics

- Reboot and confirm SDDM offers the remembered `omarchy` user and Omarchy
  session, then complete an interactive login.
- Confirm the desktop shell, launcher, terminal, notifications, and screen lock
  render without software-rendering artifacts.
- Record the OpenGL and Vulkan renderer/device summaries. Apple GPU acceleration
  must be reported; `llvmpipe` or another software renderer is a failure.
- Exercise an external display if available and record resolution, refresh
  rate, scaling, hotplug, and resume behavior.

## Networking

- Confirm NetworkManager is active and reports the Wi-Fi device as managed.
- Confirm NetworkManager uses the iwd backend.
- Connect to a known Wi-Fi network, verify DNS and IPv4/IPv6 connectivity, then
  disconnect and reconnect once.
- Test Bluetooth discovery and one paired device if hardware is available.
- After suspend/resume, repeat Wi-Fi connectivity and DNS checks.

## Audio

- Record the PipeWire/WirePlumber device and default-route summary.
- Play audio through internal speakers and verify volume and mute controls.
- Record from the internal microphone and play the sample back.
- Test the headphone jack, Bluetooth audio, or HDMI audio when available; mark
  unavailable paths as not tested rather than passed.
- Repeat internal speaker and microphone checks after suspend/resume.

## Power and suspend

- Record battery/AC state and available power profiles.
- From a local session, suspend once on AC and once on battery when safe.
- Verify wake input, display restoration, keyboard/trackpad, Wi-Fi, audio,
  brightness controls, and clock state after each resume.
- Inspect the current-boot journal for suspend, firmware, GPU, audio, and network
  errors and retain the relevant timestamps.

## Update safety

- Run the Apple Silicon bundle updater in check-only mode and record its exact
  exit status and proposed release, if any.
- Confirm no pending Omarchy migrations remain.
- Record SHA-256 hashes for `/boot/vmlinuz-linux-asahi` and
  `/boot/grub/grub.cfg` before a separately approved update test.
- If an update is later approved, verify the signed release identity, reboot,
  repeat this checklist, and explain every protected boot/package change.

## Evidence record

For each check, record the date, hardware model, pass/fail/not-tested state,
command or interaction used, concise output, and artifact path. Never mark a
hardware path passed from generic VM evidence.
