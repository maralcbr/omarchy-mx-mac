# 18: Userspace power report and sleep-cost notice

**What to build:** a separate omarchy-mac pull request, done by a separate agent: a power report command (battery draw, a 10-second CPU activity sample, kernel and AC state, frequency limits, PMP and cpuidle state), a sleep hook that records each suspend's energy cost, a post-unlock notification ("Suspend used X Wh over Y h. Overnight suspend can substantially drain this Mac."), and a docs page.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Report command works on the M1 Pro
- [ ] Notification appears after resume with correct figures; charging intervals and missing readings are rejected
- [ ] Docs page explains the current sleep limits honestly
