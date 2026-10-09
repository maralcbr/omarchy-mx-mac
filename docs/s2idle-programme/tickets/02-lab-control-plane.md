# 02: Lab control plane

**What to build:** iconidentify/maclab deployed across two hosts: `labd` (controller, job queue, recovery ladder, artifact and log store) on the omarchy-gpu Linux box, and `oobd` (macvdmtool hard reset and serial over the M1's DFU-port USB-C) plus the container kernel builder on the M4 Pro. From the `lab` CLI on the M4, an operator can hard-reset the M1 Pro and read its serial console.

**Blocked by:** None (can start immediately; the debug cable must be plugged M4 to the M1's DFU port once).

**Status:** ready-for-agent

- [ ] `labd` runs as a service on omarchy-gpu and survives a reboot of that box
- [ ] `oobd` runs on the M4 and `lab` can trigger a hard reset of the M1 Pro end to end
- [ ] Serial output from the M1 is captured through `oobd`
- [ ] The container builder on the M4 builds a known kernel tree successfully
- [ ] Load on the M4 when idle is negligible (no polling loops or always-on VMs)
