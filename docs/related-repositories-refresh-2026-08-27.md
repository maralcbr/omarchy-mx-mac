# Related repository refresh — 2026-08-27

Status: initial refresh and follow-up static Apple ISO validation complete; no boot, release, or user integration

## Scope and authority

This record belongs to the active `omarchy-mx-mac` project. It compares the
separate `maralcbr/omarchy-iso` and `maralcbr/omarchy-pkgs` repositories with
their local handoff folders. The historical `omarchy-mac` fork is reference
material only and is not used as project truth or a synchronization target.

The initial refresh fetched remote references and tags only. The later
owner-authorized follow-up created isolated local commits and a disposable
static ISO build. Neither phase pushed, merged, booted, published, promoted,
installed, altered a channel, or changed user or device configuration.

## Repository evidence

| Role | Local folder and checkout | Refreshed project truth | Finding |
| --- | --- | --- | --- |
| ISO construction | `/Users/maralc/dev/omarchy/omarchy-iso-handoff`, `handoff/m4-apple-media-20260826` at `ac53ea656b334f0103a198d5e6c3c444868757c5` | `maralcbr/omarchy-iso`; default `quattro` at `268bac16`; accepted ARM64 release `release/v4.0.1-arm64-iso` at `b5d562f` (`v4.0.1.m.1`) | The handoff has three Apple-media commits that are not on the accepted release branch, but it is missing seven commits already accepted there. It is evidence, not a current build base. |
| Package/release orchestration | Superseded clean handoff moved recoverably to `/Users/maralc/.Trash/omarchy-pkgs-signing-handoff-20260827`; former branch `fix/repository-signing-certificate` at `8b15ed70` | `maralcbr/omarchy-pkgs`; default `asahi-quattro` at `bc1daaa` | Its two signing-certificate patches are patch-equivalent to work already integrated on `asahi-quattro`. Do not restore it as project truth or cherry-pick it. |
| M1 source snapshot | `/Users/maralc/dev/omarchy/omarchy-m1-source-20260826` | Snapshot manifest, not a live Git remote | Source-only evidence created on 2026-08-26. It contains no generated ISO or VM package cache and cannot establish current repository or runtime state. |

## Local cleanup follow-up

After validating uniqueness and Git state:

- moved the redundant clean package handoff recoverably to Trash;
- removed the exact `.DS_Store` from the retained ISO handoff;
- removed temporary transfer bundles and diagnostic package downloads; and
- retained the unique ISO handoff, M1 snapshot, VM package cache, validated ISO,
  and evidence required for the next reproducibility gate.

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

### Completed source-only reconciliation

The owner-authorized follow-up created the isolated local branch
`feature/apple-validation-media-rebase`, now at deterministic-build source
`387d899551ce8209fe8ee0e96288879801ece31b`, from accepted ARM64 base `b5d562f`
and ArchISO submodule `424e78130db2af6c1ceb55b442d7914b1109ff2b`.
The first ISO bytes were produced at `cb26f81dbe66b4bf9b31f564f334ba0287a3a164`
and statically validated with verifier source
`50d97710347d82e61b420658d23173c210c46d60`.

The source now reconciles the exact signed Asahi package snapshot, pinned keyring
identity, validation-only Apple target, and concatenated-initramfs inspection.

The first static ISO is 3,414,587,392 bytes with SHA-256
`9885cf7df10b251e51b74ac4621a131d966bb1ac7c69bb062b16dedf5042ebda`.
Its canonical evidence passes static layout validation and remains fail-closed
with `boot.verified=false`.

## Package handoff disposition

`fix/repository-signing-certificate` exactly matches its tracked remote branch,
but both of its patches are already patch-equivalent on `origin/asahi-quattro`.
The canonical branch continues with signed immutable runtime-channel,
resumable-controller, protected-approval, and ISO-publication staging work.

Use `origin/asahi-quattro`, not the removed signing checkout, as the package and
release orchestration source. Remote and Git history remain the provenance.
The canonical workflow separates verification, ISO authorization, acceptance,
and publication; reaching a successful generated artifact does not authorize
publication or a channel change.

## Current conclusion

Neither handoff source should be synchronized into the active project as-is:

1. the package handoff is superseded and contributes no missing patch;
2. the ISO handoff contains unique Apple experiments but is stale against the
   accepted ARM64 release line; and
3. the M1 bundle is a source snapshot, not current Git or boot evidence.

The next safe implementation unit is a second clean build with a complete log,
tool-version manifest, recursive media manifest, and artifact/evidence hash
comparison. If that reproducibility gate passes, stop before any media write
and request explicit owner authorization for a dedicated supported M1 canary.

An actual Apple boot remains a separate physical-device gate. It needs explicit
authorization immediately before any internal-disk, boot-policy, firmware,
m1n1/U-Boot, recovery-environment, or removable-media action.
