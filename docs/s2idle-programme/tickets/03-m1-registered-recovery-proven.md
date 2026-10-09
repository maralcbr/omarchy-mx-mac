# 03: M1 Pro registered with the recovery ladder proven

**What to build:** the M1 Pro registered as a lab device, with its known-good baseline job passing, and the full recovery ladder demonstrated: a deliberately broken test kernel ends with the M1 back on the known-good kernel, and a deliberately hung kernel is reset by the watchdog, then by the out-of-band reset, with the serial log kept in both cases.

**Blocked by:** 01, 02

**Status:** ready-for-agent

- [ ] Baseline job passes, including omarchy-m-test
- [ ] A kernel that panics at boot falls back to known-good with no human action
- [ ] A kernel that hangs is recovered by watchdog or out-of-band reset with no human action
- [ ] Serial logs for both failures are stored with the job
