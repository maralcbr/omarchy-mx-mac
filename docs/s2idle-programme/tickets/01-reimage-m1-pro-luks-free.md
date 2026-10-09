# 01: Reimage the M1 Pro LUKS-free with lab access

**What to build:** the M1 Pro lab Mac reinstalled with an unencrypted root and lab access baked in (SSH key, passwordless sudo, polkit rule, Tailscale), so every reboot, watchdog reset or out-of-band reset comes back to a reachable machine with nobody at it. The owner only types passwords and holds the power button for the Recovery handoff, about 15 minutes. All data on the M1 is disposable.

**Blocked by:** None (can start immediately; needs the owner at the machine).

**Status:** ready-for-agent

- [ ] The M1 Pro boots to a logged-in session after a cold power cycle without any passphrase prompt
- [ ] SSH from the M4 works at first boot with no manual bootstrap step
- [ ] The installed kernel is the Aurora `sep-7.1.12.aurora2-12.6-stable` line or newer
- [ ] The M2 Max is not touched at any point
