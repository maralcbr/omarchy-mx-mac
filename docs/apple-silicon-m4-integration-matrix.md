# Apple Silicon M4 selective integration matrix

Status: S6 stage one completed and read back on the approved M1; 1TR reached Omarchy's initramfs but the `.5` root selector failed Switch Root; the local repair remains unqualified on hardware
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

This document does not authorize a push, pull request, merge, release, package publication, channel change, deployment to existing users, or user-default change. The owner separately authorized destructive private canary validation on the named physical `MacBookPro18,3` (`apple,j314s`) only; that exception does not extend to the M4, other devices, production signing, or publication.

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
- privileged helper registration or invocation remains forbidden except on the approved named M1 canary; the current local repair and qualification work must not contact it;
- the physical support allowlist remains empty and public release authorization
  remains false;
- the M4 model `apple,j614s` remains rejected before authorization or mutation;
- no APFS, GPT, System ESP, Apple boot policy, firmware, m1n1, U-Boot, package database, or user configuration mutation is executed outside the approved named M1 canary;
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

1. The Python engine follows conventional four-space Python indentation under the scoped `apps/omarchy-apple-installer/AGENTS.md`; shell entry points now follow the root Bash conditional rules.
2. One validated `SHA256Digest` module now owns prefixed and unprefixed digest validation, byte formatting, and length-prefixed hashing across the package.
3. Header, step navigation, engine inspection, authorization, execution, and plan-review behavior now live behind focused modules. A further mechanical split of `OmarchyAppleInstallerApp.swift` is deliberately deferred to a separate non-functional follow-up: it is not required for correctness, and changing the qualified `.5` UI/state composition here would enlarge this port and invalidate binary identity without improving the Recovery gate.
4. Running-UI inspection verified the unsupported M4 locked state. On the supported M1, the exact approved `.5` plan completed authenticated stage-one execution, consumed only its approved extent, and passed installed-content read-back. The owner then completed 1TR and reached the installed initramfs, where the `.5` image failed Switch Root; the corrected root-selector candidate is local-only and not physical proof.

### Specification

- The source now contains the root helper, authenticated XPC bridge, pinned engine executor, resumable mutation backend, app packaging, and notarization workflow. They remain unreachable to public users because no production trust root, Developer ID artifact, notary ticket, public model allowlist, or release authorization exists. The one private helper execution was limited to the exact owner-approved M1 plan.
- One validation-only Apple-target ISO has passed the recorded disposable static build/layout and read-only-media checks but has not been physically booted. Separately, the installed `.5` full-OS package passed stage-one read-back and booted through m1n1, the kernel, and initramfs before its incorrect builder-local root selector caused Switch Root to fail.
- The pinned `.5` stage-one engine fixes the root-helper extraction mismatch exposed by the first physical attempt, passed two clean same-host reproducibility builds, and completed the exact approved M1 stage-one plan with partition and installed-content read-back. The next local package candidate requires `root=UUID=<installed-root-uuid>` and rejects builder-local root paths before sealing; that repair, installed-system verification, macOS coexistence, and public release authorization remain unqualified. The empty public allowlist prevents user exposure.
- The scrolling and ChatGPT commits are scope creep for Apple Silicon work and
  remain excluded even though current main already contains independently
  integrated equivalents.

## Evidence at this checkpoint

- Current local feature HEAD is `dff6311446439e1f29f0f2e6c0cf82a9a190e5bc` on fork base `f2943bab5345029c4f82f24a198e9a5bff26634c`.
- A synthetic port of the 39 feature commits plus the current tracked patch onto Basecamp Quattro `83881e979b35468c3e7d60b171e319ede61a88fd` completed without conflicts. The active and synthetic tracked patches are byte-identical; proof patches are retained under `/private/tmp`.
- In the active and synthetic upstream trees, XcodeBuildMCP passed all 122 Swift tests in debug and all 122 in release with no failures or skips. All 56 focused Python engine tests, the three archive-mode verifier tests, every shell syntax check, and strict whole-package Swift formatting also passed.
- The exact-upstream Quattro shell suite passed all 209 test files under the retained pinned ARM64 builder with Bash 5.3 and an advancing `EPOCHREALTIME`; the focused sleep-lock lane passed separately. Their source, builder, command, result, and elapsed-time records remain separated under `/private/tmp/omarchy-bash5-shell-evidence-20260828T070157Z/`.
- The immutable `v0.9.0-omarchy.5` engine reproduced byte-for-byte across two clean builds: 22,069,312 bytes, SHA-256 `992f4c7b6090b3f6eb71876d151336f29becc0c2a97a871c4cba04910d98cb99`. Its release verifier accepts 1,104 archive entries and rejects any group/world-writable regular file or directory.
- A separate private Apple Development-signed `0.5.0` canary embeds catalog sequence `1787910668`, the `.5` engine, and the unchanged qualified full-OS payload. Its deep/reciprocal signatures, embedded catalog signature and assets, transfer ZIP, and fresh extraction all verify. Local M4 review shows `Verified • unsupported` and keeps download, helper, and disk mutation blocked. The owner approved one exact M1 plan for this canary; stage one ran once and completed without engine/helper failure. After the owner completed 1TR, this preserved `.5` payload failed Switch Root and is disqualified from another execution. This does not authorize another Start action or public use.
- The prior private Apple Development-signed `.4` canary app passed strict deep code-signature verification, Team ID and reciprocal helper requirement checks, and embedded catalog/engine/full-OS payload byte checks. It is not notarized or publicly distributable and must not be executed again.
- The app binds its app-owned trust-root fingerprint, signed catalog identity,
  exact plan, device, store, candidate extent, and engine payload digests, then
  revalidates them immediately before authenticated XPC submission.
- The live host is `apple,j614s`; the app remains locked before download,
  helper registration, authorization, or mutation. The helper service is absent
  from `launchctl` and no helper journal directory exists under `/var/db`.
- Running-UI inspection confirmed the unsupported M4 lock. On the physical M1, `.2` plan preparation exposed APFS minimum-bound drift in layout identity. That superseded local transcript produced no privileged request or disk operation and is intentionally excluded from the upstream patch because it contains transient device-state detail.
- The reviewed `.4` M1 plan `0c0323c809e6996e7f38075a9f06aa9401c556b9d74597d667438afdde53551e` entered the supported app/helper flow once. The helper accepted one XPC run, then returned `PinnedAsahiEngineExecutionError` code 8 before spawning the Python engine; two post-failure disk snapshots retained the exact normalized pre-execution identity. Direct Swift bridging proves code 8 maps to `invalidBundle`.
- Unified-log timing and a root-equivalent extraction replay identified the exact predicate: macOS `bsdtar` preserves archive permissions when the helper runs as root, while the executor allowed that default and then rejected 1,045 group-writable extracted files/directories. User-context inspect and plan runs did not preserve those modes, which is why the defect escaped local qualification. The `.5` executor now explicitly passes `--no-same-permissions` and retains the same post-extraction fail-closed validator; a root-style regression test failed before and passes after the change. The build recipe also normalizes staged modes and verifies archive headers so the release artifact is independently safe.
- The approved `.5` plan, artifact identities, exact extent containment, partition layout, installed ESP read-back, and subsequent Switch Root failure are captured in the sanitized, repository-owned [`2026-08-28-m1-v5-stage1` evidence](../evidence/apple-silicon/2026-08-28-m1-v5-stage1/README.md). It contains no credential, account name, network address, process ID, private temporary path, or reusable authorization.
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
8. **Upstream shaping (completed for this port):** digest consolidation and focused workflow modules are complete. A further mechanical view/state file split is deferred as a separate non-functional follow-up so it cannot invalidate the qualified `.5` binary or obscure the Recovery evidence.
9. **Physical M1 qualification (owner-approved, repair pending):** the exact `.5` plan completed stage one and installed-content read-back. The owner completed 1TR, and boot reached the installed initramfs before the incorrect `.5` root selector failed Switch Root. The local repair requires a new reproducible full-OS package, engine/app/catalog qualification, fresh signed-plan review, and separate owner approval before any further physical mutation. No additional helper invocation or disk action is authorized by this text.
10. **Distribution (owner-gated):** use Developer ID signing, notarization,
    stapling, exact release inputs, and model-specific acceptance before any
    publication or user integration.

## Uncommitted upstream review slices

No commit is authorized or created here. The retained patch is organized for review into these coherent slices:

1. pinned engine, full-OS metadata, stage-one execution, and Python tests;
2. macOS trust, authorization, helper handoff, workflow, and Swift tests;
3. catalog-aware packaging and immutable release inputs;
4. Bash 5 test-harness and legacy Apple hardware compatibility;
5. safety policy, qualification evidence, and upstream integration record.

Each slice must remain byte-identical between the active and exact-Quattro trees. Any eventual commit ordering is a later owner-authorized Git action.

## Next decision

The next physical action must wait for a newly qualified root-selector/authentication/retry/branding candidate, a fresh signed-plan review, and explicit owner approval. Local work must not contact, wake, monitor, or alter the M1. The consumed `.5` Start approval does not authorize another execution.

Any removable-media write, Asahi preparation, boot, publication, channel
change, or physical-device work remains a separate owner gate. Existing-user
machines are excluded. M4/J614s must remain rejected while Asahi's official
installer status remains unsupported.
