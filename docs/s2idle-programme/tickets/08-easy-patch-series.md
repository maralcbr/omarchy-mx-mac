# 08: Easy patch series: power-gate blocks in s2idle

**What to build:** for each qualifying block group from the attribution matrix, kernel changes so the block powers off during s2idle and comes back on resume, designed and drafted by Sol from a stage brief, one measured patch at a time on the programme branch. Time-boxed to one week of lab time; whatever gain exists at the end ships.

**Blocked by:** 07

**Status:** ready-for-agent

- [ ] Sol's stage brief and review are recorded
- [ ] Each patch has a paired measurement showing its saving
- [ ] Combined Easy draw is recorded; target ≤ 1.0 W
- [ ] omarchy-m-test passes after resume for every patch
