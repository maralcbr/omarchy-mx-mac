# 09: Easy reliability gate and edge release

**What to build:** the Easy series passes the reliability gate on the M1 Pro (20 short and 3 overnight sleep cycles, zero resume failures), is on by default for t6000/t6001 and behind a kernel command-line opt-in for every other SoC, and is published as a kernel package on the edge channel of maralcbr/omarchy-pkgs.

**Blocked by:** 05, 08

**Status:** ready-for-agent

- [ ] 20 short and 3 overnight cycles with zero resume failures
- [ ] Opt-in documented for non-t6000 machines
- [ ] Edge package published and installable on the M1 Pro through the normal update path
