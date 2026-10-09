# 11: PMP opt-in validated on the M1 Pro

**What to build:** the Power Management Processor enabled through its device-tree opt-in on the M1 Pro, with awake-idle and s2idle draw measured with PMP on versus off, and suspend cycles checked. Runs in parallel with the Easy series.

**Blocked by:** 06

**Status:** ready-for-agent

- [ ] PMP driver binds on the M1 Pro
- [ ] Paired awake-idle and s2idle measurements, PMP on versus off
- [ ] Five suspend cycles and one overnight sleep with PMP on, zero failures
- [ ] Go/no-go: saves ≥ 0.3 W or ≥ 10 % consistently
