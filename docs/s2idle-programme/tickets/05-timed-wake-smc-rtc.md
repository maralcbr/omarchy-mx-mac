# 05: Timed wake from s2idle

**What to build:** the M1 Pro wakes itself from s2idle after a requested duration, so sleep experiments end without a person opening the lid. Investigate the SMC real-time clock first (macOS can schedule wakes on Apple Silicon); fall back to any other wake-capable timer the platform exposes. Exposed through the standard RTC wake alarm so existing tools work.

**Blocked by:** 04

**Status:** ready-for-agent

- [ ] A requested wake after N minutes of s2idle brings the M1 back within a minute of the target, 10 out of 10 times
- [ ] Lid and power-button wake still work
- [ ] Awake and sleep draw are unchanged within measurement variation
- [ ] If no wake-capable timer exists, the finding is documented and the reliability gate falls back to out-of-band reset cycling
