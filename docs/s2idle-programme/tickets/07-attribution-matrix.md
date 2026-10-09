# 07: Attribution matrix

**What to build:** a measured table of how much of the s2idle draw each block group owns, produced by unbinding or unloading one group at a time before sleep: Thunderbolt/USB-C controllers and PHYs, external display controller, GPU, video decoder and neural engine, NVMe, Wi-Fi and Bluetooth PCIe, display pipe, SEP, AOP sensor streams. Posted in the tracking issue with the list of groups worth at least 0.1 W.

**Blocked by:** 06

**Status:** ready-for-agent

- [ ] Every listed group has a paired measurement or a documented reason it cannot be unbound
- [ ] Table with watts saved and variation is posted in the tracking issue
- [ ] Qualifying groups (≥ 0.1 W) are listed as the input to the Easy series
