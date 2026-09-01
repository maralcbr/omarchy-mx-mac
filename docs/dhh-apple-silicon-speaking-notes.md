# Apple Silicon presentation speaking notes

Prepared: 2026-08-24

## Suggested opening

“Omarchy is not merely a package experiment on Apple Silicon. It is already
running as a working system on a physical 14-inch M1 Pro MacBook Pro. We also
completed a clean disposable installation, so we have both real-hardware proof
and reproducible package proof. The remaining question is how far we want to
turn that success into an official ARM product.”

## Five-minute walkthrough

### 1. Start with the real machine

The current machine is a 14-inch 2021 MacBook Pro with an M1 Pro. It runs the
Asahi kernel and boot stack with the local signed Omarchy release. The
maintainer uses the system and confirms that Omarchy and its normal hardware
functions are working.

That validates the central statement: Omarchy works on this Apple Silicon Mac.

### 2. Add the reproducibility proof

The clean disposable validation run installed the repository-backed runtime,
the signed Omarchy release, and all pinned source packages. It rebooted to the
Omarchy login screen and passed package-closure, protected-state, migration,
updater, and rerun checks.

Use these numbers:

- 664 repository packages
- 9 signed release packages
- 10 pinned source-built packages
- 972 installed packages in total
- 141 of 141 runtime requirements present
- 10 of 10 source requirements present

The simple conclusion is: the software package path works end to end.

### 3. Explain what was learned

The original package inventory looked larger and more alarming than the real
problem. It mixed core runtime requirements with x86-only kernels, microcode,
GPU drivers, PC boot tooling, optional applications, and live-media packages.

After tracing 450 direct inputs and resolving their dependency transactions,
the core desktop stack proved healthy on ARM. The official blocker is narrower:
Omarchy does not currently publish its mandatory packages through an official
aarch64 repository.

The Apple platform must also stay distinct from generic ARM. Generic aarch64
can use an ARM kernel and UEFI media; Apple Silicon must retain Asahi's kernel,
GPU, firmware, device-tree, and boot ownership.

### 4. Show the engineering quality of the proof

This is more than “it booted once.” The installer now has explicit runtime and
source manifests, pinned inputs, signature verification, pre-mutation checks,
and exact installed-package auditing.

The disposable VM workflow survived repository hooks that reload networking.
It records its real result independently of SSH, retains logs on failure, and
runs within a conservative memory profile. Earlier failures were preserved and
used to improve the harness rather than being hidden.

### 5. State the boundary honestly

The current M1 Pro proves a working physical implementation. The VM separately
proves package and installation correctness. Neither result alone establishes
support for every M1, M2, M3, or M4 model.

The physical-hardware checklist should now capture the already-working M1 Pro
state as durable evidence and become the template for testing additional
models. It is no longer a blocker to saying the current machine works.

### 6. End on the decision

There are two viable directions:

1. Keep improving a maintained local Apple Silicon edition using the existing
   signed-bundle path.
2. Treat ARM as an official Omarchy product, which requires ownership of ARM
   repository publication, signing, generic ARM media, application policy, and
   hardware support boundaries.

The technical work supports either direction. The next strategic decision is
which product commitment is intended.

## Likely questions

### “Does Omarchy work on an Apple Silicon Mac now?”

Yes. It is running on a physical 14-inch M1 Pro MacBook Pro and the maintainer
confirms the system works. The clean disposable installation independently
proves that the package path is reproducible. What we are not claiming is
automatic support for every Apple Silicon model.

### “Why not just merge the fork?”

The fork contains useful working behavior, but it also owns local release,
package, and Apple-specific integration choices. The safer architecture is to
use it as evidence, extract coherent behavior at current code boundaries, and
keep Asahi-owned platform state outside Omarchy.

### “What is actually blocking an official release?”

Official aarch64 repository publication and signing, a supported ARM base and
generic ARM media pipeline, a multi-model support policy, and a decision about
the supported application set. The desktop and this M1 Pro implementation are
not the main blockers.

### “Do all x86 applications need to be ported first?”

No, not for a usable desktop. Some optional or preinstalled applications lack
ready ARM packages. Product policy must decide whether identical app parity is
required or whether ARM ships an explicit supported subset.

### “Are we replacing Asahi?”

No. Asahi remains the owner of the Apple kernel, GPU stack, firmware, device
trees, and boot environment. Omarchy should own the desktop payload and its
release behavior above that boundary.

### “What failed during testing?”

One run lost SSH while package hooks reloaded networking. Two larger QEMU runs
were killed by host memory pressure. These failures produced durable fixes:
out-of-band completion status, reconnect-safe supervision, QEMU liveness
checks, lower resource defaults, retained logs, and a verified package cache.
The final 3-GiB run completed.

### “What happens next?”

Capture the working M1 Pro state in the physical evidence checklist, use that
record as the baseline for future regressions and other models, and decide
whether official ARM distribution is a product goal. The current branch
remains local; no upstream PR is planned.

## Claims to avoid

- Do say Omarchy is working on the validated M1 Pro reference machine.
- Do not generalize one M1 Pro result to every Apple Silicon model.
- Do not use the VM as physical-device evidence; the real M1 Pro is that
  evidence.
- Do not say official Omarchy aarch64 repositories exist.
- Do not imply the fork will be merged wholesale.
- Do not promise every optional x86 application on ARM.
- Do not present an upstream PR or release schedule as approved.
