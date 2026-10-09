# 06: Sleep measurement job

**What to build:** a lab job that boots a named kernel once on the M1 Pro, runs a sleep scenario (duration, lid state, attached devices), and returns one structured record: duration, energy used, average watts, resume result, wake source, interrupt counts across the sleep, power-domain states before suspend, omarchy-m-test results after resume, serial log. Battery energy deltas over windows of at least 30 minutes, on battery, nothing attached, fixed charge range. Paired, alternating-order comparison of two kernels or two configurations, reporting a verdict only when the difference beats run-to-run variation.

**Blocked by:** 04

**Status:** ready-for-agent

- [ ] One command produces one structured record for a sleep run
- [ ] A paired comparison of the same kernel against itself reports "no difference"
- [ ] Baseline s2idle draw of the stock tag is recorded in the tracking issue
- [ ] Ends sleep by timed wake when 05 has landed, otherwise by out-of-band reset with energy read at next boot
