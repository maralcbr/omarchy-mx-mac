# Direct Asahi Install VM

This harness tests the published fresh Omarchy 4 lifecycle in a disposable
generic aarch64 KVM guest. It verifies the signed public assets unchanged, then
runs the current source candidate with only its hardware predicates patched in
a retained test copy. The installed Apple
detector is overridden while system setup runs and restored byte-for-byte
afterward. A temporary SSH firewall allowance supports post-reboot assertions
and is removed by the final rerun check. No VM bypass is shipped in the
production installer.

The guest installs the real Asahi package set while continuing to boot an
unowned generic `linux-aarch64` test fixture through GRUB. This validates package resolution,
the exact six-package transaction, pinned source builds, failure recovery, user
provisioning, hard-interruption recovery, collision safety, reboot, safe
completed reruns, migrations, and protected boot
files. It cannot validate
Apple GPU, Wi-Fi, audio, suspend, or other physical hardware behavior.

Run:

```bash
test/vm/asahi-fresh/run
```

The guest uses 8 vCPUs, 8 GiB RAM, and a 96 GiB sparse disk.

Use `--rebuild-base` to discard the cached Arch Linux ARM base and `--keep` to
retain the VM container after a run. State and failure artifacts are written to
`test/vm/asahi-fresh/test-runs/`, which is ignored by Git.

Use `--optional-packages` to install every transaction in
`install/optional-packages-aarch64-required` with real `pacman -S` operations
after the reboot checks. Each transaction gets a separate log under
`test-runs/run/optional-package-logs/`. This validates package installation and
post-install hooks in a disposable system, but it does not automate application
login, GUI interaction, or hardware behavior.
