# 14: Hard spike with kill criteria

**What to build:** a one-week m1n1 hypervisor spike on the M1 Pro tracing macOS entering and leaving sleep (PMGR, memory controller, SMC, AOP and PMP mailboxes), answering two questions: do the cores wake at m1n1's reset vector or does iBoot re-run, and can the hypervisor survive the power-down to trace the wake. Uses the owner's banked Sol resets if trace volume needs it.

**Blocked by:** 13

**Status:** ready-for-agent

- [ ] Traces and findings recorded in the tracking issue
- [ ] Both questions answered with evidence
- [ ] Explicit go or no-go; no-go stops the programme at Medium
