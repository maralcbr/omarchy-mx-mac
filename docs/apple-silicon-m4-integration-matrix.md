# Apple Silicon M4 selective integration matrix

Status: S6 installer execution chain implemented locally; no installed-user or physical qualification
Created: 2026-08-27
Destination branch: `feature/m4-handoff-integration`
Destination base: `origin/main` at `f2943bab5345029c4f82f24a198e9a5bff26634c`
Upstream comparison: `basecamp/omarchy` `quattro` at
`83881e979b35468c3e7d60b171e319ede61a88fd`
Evidence branch: `handoff/m4-apple-silicon-20260826` at `1a2102813b97c2a9eb1447226523d681010519b5`
Merge base: `46224d32dbdf70003f0620f588182f3852cb36ac`

## Purpose

Use the M4 handoff as evidence for small, independently reviewable changes on
current `omarchy-mx-mac` main. Do not merge, rebase, or cherry-pick the handoff
branch wholesale. The historical `omarchy-mac` fork is reference material only
and is not an integration source or synchronization target.

This document does not authorize a push, pull request, merge, release, package
publication, channel change, deployment, privileged installer run, physical
disk mutation, or user-default change.

## Existing-user safety boundary

Work may proceed only while all of these conditions remain true:

- changes stay in the isolated local worktree and are not pushed or merged;
- no package, ISO, catalog, release, update-channel, or repository metadata is
  published or promoted;
- no GitHub secret, production signing identity, production trust root,
  catalog, or helper registration is created or changed;
- the Apple application is not installed in `/Applications`, registered as a
  login item, or connected to an existing Omarchy installation path; a local
  debug build may be opened only for blocked-state inspection;
- the privileged helper remains unregistered and no helper request is sent;
- the physical support allowlist remains empty and public release authorization
  remains false;
- the M4 model `apple,j614s` remains rejected before authorization or mutation;
- no APFS, GPT, System ESP, Apple boot policy, firmware, m1n1, U-Boot, package
  database, or user configuration mutation is executed; and
- validation is limited to pure/unit tests, non-privileged read-only probes,
  source builds, and explicitly disposable environments.

Crossing any boundary above requires the owner's separate explicit
authorization immediately before the action.

## Commit disposition

The rows below record the original handoff disposition. The current
implementation review and evidence sections supersede their prototype-era
statements about which source modules were still missing.

| Handoff commit | Evidence | Disposition on current main | Required action or gate |
| --- | --- | --- | --- |
| `9fd6a6d4` — traditional scrolling | `git cherry` and `git range-diff` identify `4be8a8eb` on main as patch-equivalent. It also changes an existing user default outside the Apple Silicon specification. | **Exclude.** Do not cherry-pick or reimplement. | None. Main already contains the separately authorized change. |
| `e4cbf9eb` — retire legacy ChatGPT launcher | The same behavior and tests are present through `3a6eba25` and merge `c2252509`; patch identity differs only because it was applied onto a newer parent state. It is unrelated to Apple Silicon and changes existing-user launcher behavior. | **Exclude.** Do not cherry-pick. | None. Retain GitHub main's implementation. |
| `6d1f5be3` — guarded Apple installer prototype | Contains the fail-closed Swift prototype, engine contract, journal, support catalog, packaging, safety documentation, and tests. Production trust, authorization, notarization, media acceptance, and mutation backend are intentionally absent. | **Re-author selectively; never cherry-pick wholesale.** Treat as source and test evidence. | First resolve the standards findings below. Keep the app disconnected from install/update paths and keep mutation unreachable. Each extracted seam must be an atomic reviewable commit. |
| `16d84a25` — platform release gates | Adds a hidden verifier, ownership manifest, release lifecycle, package input, focused shell tests, and Phase 4 status. The lifecycle is still `development`, public authorization is false, and the physical allowlist is empty. | **Extract contracts and tests only after current-main review.** | Preserve fail-closed defaults. Do not connect the manifest to a release pipeline, package channel, ISO publication, or installed-user command. |
| `27ebd79f` — incremental ARM64 workflow | Documentation for work owned primarily by `omarchy-pkgs`; it explicitly separates implementation from publication. | **Reference only in this repository.** | Validate applicable steps in `maralcbr/omarchy-pkgs`. Publishing or channel advancement remains a separate approval gate. |
| `4c9e88ff` — shell standards fixes | A fixup spanning the prototype, verifier, packaging script, and already-superseded ChatGPT test. It has no independent product behavior. | **Fold applicable hunks into re-authored commits.** Do not cherry-pick separately. | Apply only to files actually extracted after their repository standards are rechecked. |
| `988cdd90` — M4 continuation handoff | Snapshot-specific paths, object IDs, bundles, host identities, and operational continuation gates. | **Preserve as handoff evidence; do not transplant verbatim.** | Carry durable safety and authorization gates forward in current documentation, without stale host or branch claims. |
| `1a210281` — source-only clarification | Clarifies that the transfer contains source only and authorizes no remote or runtime action. | **Preserve as handoff evidence.** | The durable authority boundary is captured in this matrix. |

## Current implementation review

### Standards

1. The Python engine follows conventional four-space Python indentation under
   the scoped `apps/omarchy-apple-installer/AGENTS.md`; shell entry points now
   follow the root Bash conditional rules.
2. One validated `SHA256Digest` module now owns prefixed and unprefixed digest
   validation, byte formatting, and length-prefixed hashing across the package.
3. Header, step navigation, and engine inspection now live in focused modules.
   `OmarchyAppleInstallerApp.swift` still combines state coordination with the
   detail screen and should be split once more before an upstream pull request.
4. Running-UI inspection has verified the unsupported M4 locked state, but the
   physical supported-M1 flow remains unverified.

### Specification

- The source now contains the root helper, authenticated XPC bridge, pinned
  engine executor, resumable mutation backend, app packaging, and notarization
  workflow. They remain unreachable to users because no production trust root,
  signed catalog, Developer ID artifact, notary ticket, helper registration, or
  physical release authorization exists.
- One Apple-target ISO has passed the recorded disposable static build/layout
  and read-only-media checks. No candidate has passed a physical
  Asahi-prepared m1n1/U-Boot boot test or the two-clean-build reproducibility
  gate.
- No exact-model physical acceptance or release authorization exists; the
  empty public allowlist correctly prevents user exposure.
- The scrolling and ChatGPT commits are scope creep for Apple Silicon work and
  remain excluded even though current main already contains independently
  integrated equivalents.

## Evidence at this checkpoint

- Current local feature HEAD is `a9d6c7a3fd190307acd5bc1778504e7f78cf73ee`
  on fork base `f2943bab5345029c4f82f24a198e9a5bff26634c`.
- A synthetic three-way port of only the 38 feature commits onto Basecamp
  Quattro `83881e979b35468c3e7d60b171e319ede61a88fd` completed without conflicts.
  Merging the entire long-lived fork is not the upstream strategy and has six
  conflicts in unrelated shared paths.
- In the synthetic upstream tree, XcodeBuildMCP 2.7.0 passed all 106 Swift tests
  in debug and all 106 in release with no failures, skips, warnings, or errors.
  All 39 focused Python engine tests, every shell syntax check, and strict
  whole-package Swift formatting also passed.
- An ad-hoc release bundle has passed strict deep code-signature verification.
  Its helper refuses non-root execution. No Developer ID distribution identity
  or notarization credential is available on this host.
- The app binds its app-owned trust-root fingerprint, signed catalog identity,
  exact plan, device, store, candidate extent, and engine payload digests, then
  revalidates them immediately before authenticated XPC submission.
- The live host is `apple,j614s`; the app remains locked before download,
  helper registration, authorization, or mutation. The helper service is absent
  from `launchctl` and no helper journal directory exists under `/var/db`.
- Running-UI inspection confirmed the unsupported-host lock and disabled Start
  and disk-mutation controls. No privileged request or disk operation ran.
- The read-only related-repository refresh is recorded in
  [`related-repositories-refresh-2026-08-27.md`](related-repositories-refresh-2026-08-27.md).
  The package-signing handoff is superseded on `origin/asahi-quattro`; the ISO
  handoff's three Apple experiments are stale against seven accepted ARM64
  release commits and must not be built directly.
- The official-source build and boot evidence contract is recorded in
  [`apple-silicon-validation-media-evidence.md`](apple-silicon-validation-media-evidence.md).
  M4/J614s remains installer-unsupported, and removable-media boot still
  depends on a pre-existing internal Asahi m1n1/U-Boot environment.
- Candidate `2026-08-27-9885cf7d` was produced from accepted ARM64 ISO base
  `b5d562f` and build source `cb26f81dbe66b4bf9b31f564f334ba0287a3a164`.
  It was statically checked with verifier source
  `50d97710347d82e61b420658d23173c210c46d60` in an isolated AArch64 VM.
- The 3,414,587,392-byte ISO has SHA-256
  `9885cf7df10b251e51b74ac4621a131d966bb1ac7c69bb062b16dedf5042ebda`.
  Its canonical evidence proves AArch64 GRUB EFI, matching ISO/ESP EFI bytes,
  `linux-asahi`, Asahi initramfs content, exact signed package/keyring
  snapshot, and generic-ARM/Limine absence.
- The tracked static evidence remains fail-closed with
  `boot.verified=false`; no media write, boot, publish, channel, remote, or
  installed-user action occurred.
- Candidate `2026-08-27-a9c09d7b` supersedes that first checkpoint for the next
  gate. Source `0c1dbd071cd271c62b7d45dfbaa777eaaf6742c1` adds the format-aware
  verifier dependency only to Apple validation builds. Its full isolated build
  exited zero; the 3,414,591,488-byte ISO has SHA-256
  `a9c09d7bc510e16275b4721f5e854bae8ade9b392f0a86ad4d3790bf152ffb8f`.
  The complete log, environment manifest, and canonical static evidence are
  retained under `evidence/apple-silicon/2026-08-27-a9c09d7b/`. Physical boot
  and byte reproducibility remain explicitly unverified.
- Live-root inspection then disqualified `2026-08-27-a9c09d7b` from physical
  canary use because it retained the normal installer, cidata automation, and
  disk-mutation entry points. Candidate `2026-08-27-e732b2bc`, built from
  `dfa58faded2b123ea01dbfadad20d22bdc0bd9fb`, removes those paths, installs a
  validation-only console, disables systemd GPT/fstab automatic discovery,
  and proves NVMe read-only fail-closed behavior in focused tests.
- The candidate-4 full isolated build exited zero; its 3,414,530,048-byte ISO
  has SHA-256
  `e732b2bc025e382dcf5c75e43236f06dc1eb6db574a6c9e70a2a308af151b2c7`.
  Canonical evidence, the environment manifest, and complete compressed log
  are retained under `evidence/apple-silicon/2026-08-27-e732b2bc/`. Physical
  boot remains explicitly false and no media was written.

## Proposed source-only sequence

This sequence is a proposal, not authorization to execute later gates.

1. **S0 — review record (completed locally):** preserve the source and owner
   boundaries without importing unrelated handoff changes.
2. **S1 — trust core (completed locally):** validate signed catalogs, exact
   identities, resumable journals, and candidate-bound approvals.
3. **S2 — asset and handoff closure (completed locally):** stage exact signed
   assets and authenticate immutable handoff packages before execution.
4. **S3 — privileged boundary (completed locally):** authenticate the app over
   XPC and revalidate the exact request inside a root-only helper.
5. **S4 — pinned Asahi engine (completed locally):** lock the upstream object
   graph, toolchain, inputs, overlay, and reproducible engine artifact.
6. **S5 — application packaging (completed locally):** assemble and verify the
   hardened-runtime app/helper bundle; keep notarization separate and gated.
7. **S6 — supported-host flow (completed in source):** inspect, download,
   prepare, review, confirm, execute once, and map recovery/manual next actions.
8. **Upstream shaping (in progress):** digest consolidation and the initial
   view/runtime split are complete. Extract root state coordination from the
   detail screen, then rerun the synthetic Quattro port tests.
9. **Physical M1 qualification (owner-gated):** begin with a private read-only
   development-signed build. Register the helper, execute mutation, enter 1TR,
   boot, recover, and verify macOS coexistence only through separate explicit
   gates with retained evidence.
10. **Distribution (owner-gated):** use Developer ID signing, notarization,
    stapling, exact release inputs, and model-specific acceptance before any
    publication or user integration.

## Next decision

The next physical step is a private, development-signed M1 build and read-only
host inspection. It must prove the supported model, APFS inventory, release
identity, engine transcript, and exact candidate plan before helper registration
or disk mutation is considered.

Any removable-media write, Asahi preparation, boot, publication, channel
change, or physical-device work remains a separate owner gate. Existing-user
machines are excluded. M4/J614s must remain rejected while Asahi's official
installer status remains unsupported.
