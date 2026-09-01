# Apple `container` testing assessment

Research snapshot: 2026-08-26. Sources are Apple documentation and Apple's
open-source repositories. No tool was installed and no container or VM was
started during this investigation.

## Decision

Use Apple's `container` CLI as an **additional Linux contract-test runner**,
not as a simulator for installing Omarchy on Apple hardware.

It can safely add useful T0/T2 coverage and a subset of T5 userspace coverage:
run the downstream engine's platform-independent tests, replay/fuzz structured
contracts, verify signed handoff manifests, and exercise synthetic regular-file
disk images inside a per-container Linux VM. It cannot exercise the Swift
app's macOS APIs, the host APFS container, recoveryOS/1TR, LocalPolicy, firmware
extraction, m1n1, U-Boot, the System ESP, or a physical Apple boot.

The M4 is eligible but not ready yet. A read-only SSH check found:

```text
architecture: arm64
macOS:        26.6.2
container:    not installed
```

Apple requires an Apple-silicon Mac and supports the CLI on macOS 26. Installing
the signed package writes under `/usr/local`, requests an administrator
password, and the service must then be started. Those are separate, explicit
setup actions; this report does not authorize them
([`container` 1.3.0 README](https://github.com/apple/container/blob/1.3.0/README.md#requirements)).
The latest official release observed for this snapshot is
[`1.3.0`](https://github.com/apple/container/releases/tag/1.3.0).

## What the tool actually isolates

`container` consumes OCI images and runs **Linux**, with one lightweight VM per
container. Each VM uses Virtualization.framework rather than sharing one Linux
kernel across all containers. The host service uses XPC helpers for images and
vmnet networking, and launches a Linux runtime helper per container
([technical overview](https://github.com/apple/container/blob/1.3.0/docs/technical-overview.md#how-does-container-run-my-container)).
The underlying Containerization framework boots a minimal Linux root filesystem,
runs `vminitd` as PID 1, and controls it over gRPC/vsock
([Containerization 0.41.0 design](https://github.com/apple/containerization/blob/0.41.0/README.md#design)).

That VM boundary is materially better isolation for untrusted Linux test code,
but it is not a macOS sandbox around a macOS process. Linux root or Linux
capabilities remain inside the guest VM and do not turn into macOS root or
access to the Mac's Apple platform devices.

### Images, CPU, kernel, filesystem, and network

- Native images are `linux/arm64`. The framework also supports
  `linux/amd64` processes through Rosetta 2; other operating systems are not a
  supported container runtime
  ([Containerization capabilities](https://github.com/apple/containerization/blob/0.41.0/README.md#containerization)).
- A custom Linux kernel can be supplied per container. Apple tests the
  framework starting with Linux 6.14.9 and requires VIRTIO drivers to be built
  into a supplied kernel, not only provided as modules
  ([kernel support](https://github.com/apple/containerization/blob/0.41.0/README.md#kernel-support)).
- Host directories can be shared with virtiofs bind mounts; named volumes are
  journaled ext4 images; tmpfs is guest-memory-backed. Bind mounts and the
  container root filesystem can be read-only
  ([mounts and volumes](https://github.com/apple/container/blob/1.3.0/docs/volumes.md)).
- `container system start` creates a vmnet network. Containers receive their
  own addresses; macOS 26 can create multiple networks isolated from one
  another, and explicit TCP/UDP port forwarding is supported
  ([networking](https://github.com/apple/container/blob/1.3.0/docs/networking.md)).
- On an M3-or-newer host, `--virtualization` can expose nested virtualization,
  but the guest also needs a custom KVM-enabled kernel. This is optional and
  adds another layer; it is not needed for the first experiment
  ([CLI reference](https://github.com/apple/container/blob/1.3.0/docs/command-reference.md#container-run)).

An isolated vmnet separates container networks from one another; the cited
documentation does not describe it as an outbound-network denial mechanism.
The first lane should therefore run reviewed test code and must not treat its
network topology as a sandbox for a hostile workload.

### Privilege, devices, and disks

The documented `run`/`create` surface allows individual Linux capabilities
with `--cap-add`, including `ALL`. It does **not** expose Docker-style
`--privileged` or `--device` options. Its documented mounts are host paths,
named ext4 volumes, or tmpfs—not host block-device passthrough
([complete `run` options](https://github.com/apple/container/blob/1.3.0/docs/command-reference.md#container-run),
[mount option types](https://github.com/apple/container/blob/1.3.0/docs/volumes.md#options-for---mount)).

Therefore the CLI should not be treated as a route to `/dev/disk*`. A regular
sparse disk-image **file** inside the guest is useful test data; it is not the
Mac's raw disk and cannot demonstrate APFS resize safety. We should not add a
custom VMM/device-passthrough implementation for installer tests: doing so
would discard the useful safety boundary.

## macOS, recovery, APFS, and Apple boot policy

The `container` CLI cannot run a macOS guest. Apple's broader Virtualization
framework can independently install macOS from an IPSW into a VM bundle with a
virtual disk image, virtual hardware model, machine identifier, and auxiliary
storage
([Apple's macOS VM sample](https://developer.apple.com/documentation/virtualization/running-macos-in-a-virtual-machine-on-apple-silicon)).
It can also request that such a macOS VM start in its macOS recovery environment
([`VZMacOSVirtualMachineStartOptions`](https://developer.apple.com/documentation/virtualization/vzmacosvirtualmachinestartoptions)).

That separate macOS-VM facility could improve T4 testing of packaging, UI,
authorization cancellation, controlled adapters, and disposable virtual APFS
images. It still presents virtual hardware and virtual storage. It is not the
named M1 Pro, physical internal APFS/GPT, physical 1TR gesture, machine-owner
LocalPolicy, device firmware, or Asahi boot chain. Apple documents startup
security policy as per installed OS and gates critical changes through a human
restart into recoveryOS by holding the power button
([Apple startup security](https://support.apple.com/guide/deployment/startup-security-in-macos-dep5810e849c/web)).
Asahi likewise defines a per-install m1n1/device-tree/U-Boot/ESP chain that
depends on Apple Silicon hardware
([Asahi boot process](https://asahilinux.org/docs/alt/boot-process-guide/)).

Consequently, neither `container` nor a macOS VM closes any physical T6/T7
evidence gate.

## Mapping to the project test ladder

| Gate | Coverage from `container` | Assessment |
| --- | --- | --- |
| T0 — pure state | Platform-independent code can run in Linux. The current Swift package is macOS-only and imports AppKit/IOKit, so its state core would first need a separate Linux-compatible target. | Useful after a clean target split; not required for existing macOS T0. |
| T1 — snapshots/accessibility | No AppKit, SwiftUI macOS renderer, VoiceOver, or native app window. | No. Keep native M4/macOS UI tests. |
| T2 — engine contracts | Run Python/shell contract tests, JSON/transcript replay, signature/manifest checks, fuzzers, and synthetic disk-image files in an isolated Linux VM. | Strong additional coverage. |
| T3 — read-only M4 | Guest Linux cannot validate host `sysctl`, IOKit, FileVault, `diskutil`, or the exact M4 rejection path. | No. Keep direct unprivileged M4 probes. |
| T4 — disposable macOS | Can test portable subprocess and fault-injection pieces only. It cannot test macOS packaging, signing, Authorization Services, `diskutil`, or recovery behavior. | Small supplement, not a T4 environment. Use a separate macOS VM plus controlled adapters. |
| T5 — generic AArch64 VM | Native ARM64 Linux containers can validate the package payload and Linux handoff. Full ISO/UEFI boot, reboot, and update evidence still belongs in the existing generic AArch64 VM harness. Nested KVM is possible on this M4 with a custom kernel, but adds complexity without improving the claim. | Useful subset; does not close T5 alone. |
| T6 — physical canary | No named physical model, internal storage, recovery/1TR, Apple boot policy, firmware, or hardware. | No. |
| T7 — named-device matrix | No physical device feature coverage. | No. |

## Recommended safe first experiment

After separate approval to install and start the tool:

1. Pin the signed Apple `container` release and an OCI image by digest; record
   both identities in the test result.
2. Mount only the repository checkout read-only. Provide a dedicated tmpfs or
   disposable named volume for test output; do not mount the home directory,
   SSH agent, credentials, `/dev`, or any disk path.
3. Keep the container root read-only. Do not use `--cap-add`,
   `--virtualization`, socket publishing, or host ports for this experiment.
4. Run only the platform-independent Engine Python tests and the Linux handoff
   verifier/fixture tests. Add one synthetic regular-file disk image containing
   a deliberately out-of-bounds target and prove the verifier rejects it.
5. Remove the test container and retain only the sanitized test report,
   pinned identities, and hashes. Treat any container/volume deletion as a
   scoped destructive action requiring exact target review.

Success means the same pinned inputs produce the same contract outcomes in a
fresh per-test Linux VM without host writes. It does **not** mean the app can
prepare a Mac, the ISO boots on Apple hardware, or the M1 Pro is ready for T6.

## Explicit non-goals

- No installation or service startup on the M4 under this research task.
- No host raw-disk, USB, DFU, recoveryOS, or device passthrough.
- No APFS resize, GPT edit, System ESP write, boot-policy change, or firmware
  extraction.
- No claim that an OCI container boots the Omarchy ISO or reproduces the
  Asahi/m1n1/U-Boot path.
- No replacement for T3 read-only host checks, a disposable macOS T4 VM, the
  existing generic AArch64 T5 VM, or the physical M1 Pro T6 canary.
