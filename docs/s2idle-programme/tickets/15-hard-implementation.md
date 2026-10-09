# 15: Hard: macOS-style deep sleep

**What to build:** a `mem` suspend state on the M1 Pro where the SoC powers down with DRAM in self-refresh and wakes through m1n1's reset vector, with drivers that assume power loss and coprocessors rebooted on wake. Only started on a go from the spike.

**Blocked by:** 14 (go only)

**Status:** ready-for-agent

- [ ] Deep-sleep draw recorded; target ≤ 0.2 W
- [ ] Reliability gate passes
- [ ] Ships with the same per-SoC enablement rule
