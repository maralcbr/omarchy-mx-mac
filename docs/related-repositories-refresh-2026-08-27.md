# Related repository refresh — 2026-08-27

Status: read-only remote refresh complete; no build, boot, release, or user integration

## Scope and authority

This record belongs to the active `omarchy-mx-mac` project. It compares the
separate `maralcbr/omarchy-iso` and `maralcbr/omarchy-pkgs` repositories with
their local handoff folders. The historical `omarchy-mac` fork is reference
material only and is not used as project truth or a synchronization target.

The refresh fetched remote references and tags only. It did not pull, merge,
rebase, reset, build, boot, publish, promote, sign, install, alter a channel, or
change any user or device configuration. Existing untracked `.DS_Store` files
in the handoff folders were left untouched.

## Repository evidence

| Role | Local folder and checkout | Refreshed project truth | Finding |
| --- | --- | --- | --- |
| ISO construction | `/Users/maralc/dev/omarchy/omarchy-iso-handoff`, `handoff/m4-apple-media-20260826` at `ac53ea656b334f0103a198d5e6c3c444868757c5` | `maralcbr/omarchy-iso`; default `quattro` at `268bac16`; accepted ARM64 release `release/v4.0.1-arm64-iso` at `b5d562f` (`v4.0.1.m.1`) | The handoff has three Apple-media commits that are not on the accepted release branch, but it is missing seven commits already accepted there. It is evidence, not a current build base. |
| Package/release orchestration | `/Users/maralc/dev/omarchy/omarchy-pkgs-signing-handoff`, `fix/repository-signing-certificate` at `8b15ed70` | `maralcbr/omarchy-pkgs`; default `asahi-quattro` at `bc1daaa` | The handoff's two signing-certificate patches are patch-equivalent to work already integrated on `asahi-quattro`. The default branch has 23 later commits. Do not merge or cherry-pick this handoff. |
| M1 source snapshot | `/Users/maralc/dev/omarchy/omarchy-m1-source-20260826` | Snapshot manifest, not a live Git remote | Source-only evidence created on 2026-08-26. It contains no generated ISO or VM package cache and cannot establish current repository or runtime state. |

## ISO handoff disposition

The ISO handoff is 34 commits ahead of `origin/quattro`, including these three
Apple-media experiments after `origin/phase-3-arch-selector`:

- `0cb1763` — validation-only Apple Silicon media target;
- `166fdd5` — contained Apple installation backend; and
- `ac53ea6` — signed-manifest Apple ISO release gates.

Against the accepted ARM64 release line, the handoff diverges by seven accepted
commits versus three experimental commits. The accepted side includes the
current package-candidate pins, acceptance records, and ARM keyring installation.
Building the handoff directly would therefore test an obsolete base and could
misattribute a pin or keyring defect to the Apple boot work.

The handoff's static validator can establish target metadata, AArch64 PE
architecture, `linux-asahi`, the Asahi initramfs hook, and the absence of the
generic-kernel/Limine path. Its own result deliberately records boot as
unverified with `disposable-asahi-boot-evidence-absent`. Static success must not
be described as Apple boot acceptance.

The accepted ARM64 ISO branch remains a generic UEFI AArch64 path; its recorded
QEMU/HVF acceptance is not evidence for the Apple m1n1/U-Boot chain.

### Required source-only reconciliation

Before any ISO is built, start from the then-current accepted ARM64 ISO release
line in a new isolated worktree and re-author the Apple changes selectively.
Reconcile package pins and the ARM keyring first, retain the validation-only
target, and independently review the contained backend and release-gate code.
Creating that branch/worktree is a repository mutation and is not authorized by
this read-only refresh.

## Package handoff disposition

`fix/repository-signing-certificate` exactly matches its tracked remote branch,
but both of its patches are already patch-equivalent on `origin/asahi-quattro`.
The canonical branch continues with signed immutable runtime-channel,
resumable-controller, protected-approval, and ISO-publication staging work.

Use `origin/asahi-quattro`, not the signing handoff, as the package and release
orchestration source. Keep the handoff for provenance only. The canonical
workflow separates verification, ISO authorization, acceptance, and
publication; reaching a successful generated artifact does not authorize
publication or a channel change.

## Current conclusion

Neither handoff folder should be synchronized into the active project as-is:

1. the package handoff is superseded and contributes no missing patch;
2. the ISO handoff contains unique Apple experiments but is stale against the
   accepted ARM64 release line; and
3. the M1 bundle is a source snapshot, not current Git or boot evidence.

The next safe implementation unit is an isolated, source-only re-authoring of
the validation target on the accepted ISO base, followed by static tests. An
actual Apple boot remains a separate physical-device gate and needs explicit
owner authorization immediately before any internal-disk, boot-policy,
firmware, m1n1/U-Boot, or recovery-environment action.
