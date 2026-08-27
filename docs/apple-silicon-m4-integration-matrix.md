# Apple Silicon M4 selective integration matrix

Status: S3 implemented and first Apple media statically validated locally; no user integration
Created: 2026-08-27
Destination branch: `feature/m4-handoff-integration`
Destination base: `origin/main` at `c2252509fa48e430c7142543e9da4d442343328d`
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
- no GitHub secret, signing identity, production trust root, or live
  authorization mechanism is created or changed;
- the Apple application is not installed, registered, launched at login, or
  connected to an existing Omarchy installation path;
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

## Review findings that block source extraction

### Standards

1. `apps/omarchy-apple-installer/Engine/verify-source-lock.py` and the Python
   added by `Engine/patches/0001-omarchy-structured-inspection.patch` use
   four/eight-space indentation while `AGENTS.md` requires two spaces and no
   tabs. Resolve the ownership/style conflict before extracting these files;
   do not silently rewrite an upstream patch without re-verifying its source
   lock and reproducibility contract.
2. `PinnedEngineProcess.swift` and `PinnedEngineBundleProcess.swift` duplicate
   request validation, private temporary-file setup, process launch, error
   mapping, and transcript validation. Extract one closed execution harness and
   model the request/identity pair as one value before production trust work.
3. `InstallerView.swift` combines workflow state, all screens, reusable visual
   components, logo rendering, and custom shapes in one 1,220-line file. Split
   screen-level views from reusable presentation components before extending
   the authorization flow.

The hidden `bin/` command metadata and naming, shell style, migration mode and
idempotence, and privilege boundary otherwise conform to the documented
repository standards.

### Specification

- Production trust-root installation, a production-signed engine, live macOS
  authorization, notarization, and a mutation-capable backend are missing. This
  is intentional and must remain fail-closed during source extraction.
- One Apple-target ISO has passed the recorded disposable static build/layout
  checks. No candidate has passed a physical Asahi-prepared m1n1/U-Boot boot
  test or the two-clean-build reproducibility gate.
- No exact-model physical acceptance or release authorization exists; the
  empty allowlist correctly prevents user exposure.
- The scrolling and ChatGPT commits are scope creep for Apple Silicon work and
  remain excluded even though current main already contains independently
  integrated equivalents.

## Evidence at this checkpoint

- Current GitHub main is `c2252509fa48e430c7142543e9da4d442343328d`.
- The handoff contributes eight commits not reachable from main; one is
  patch-equivalent to main and one is behaviorally superseded on main.
- XcodeBuildMCP 2.7.0 ran the handoff Swift package tests on Xcode 26.5:
  78 passed, 0 failed, 0 skipped.
- The tested M4 model remains rejected by the prototype before any privileged
  or mutation-capable path.
- S1 adds a library-only trust core with no executable target, process adapter,
  persistence adapter, authorization provider, signing key, installer
  registration, or release wiring.
- S2 adds one closed execution harness with injected authorization and process
  seams. It contains no concrete process launcher, live authorization provider,
  filesystem persistence, installer registration, or release wiring.
- The 18 trust-core and closed-adapter interface tests pass in both debug and
  release configurations through XcodeBuildMCP 2.7.0. They prove cancellation
  before execution, plan-substitution rejection, signature failure before
  authorization, transcript validation, and hard rejection of `apple,j614s`
  even when a test-signed catalog enables it.
- S3 replaces raw public-key input at the public seam with an app-owned Ed25519
  verification root bound to its expected SHA-256 fingerprint. No production
  root, private key, signing operation, key installation, or key persistence is
  present in source.
- Candidate approvals now bind the trust-root fingerprint, signed-catalog
  identity, exact plan, device, store, candidate extent, and engine payload
  digests. The request is revalidated before authorization.
- The 24 identity and execution interface tests pass in both debug and release
  configurations through XcodeBuildMCP 2.7.0. They include public-key
  substitution, catalog-sequence binding, candidate replay, and approval-digest
  tampering failures before authorization or execution.
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

## Proposed source-only sequence

This sequence is a proposal, not authorization to execute later gates.

1. **S0 — review record:** approve this matrix and keep the branch
   documentation-only.
2. **S1 — non-operational core (completed locally):** re-author only the value types, parsers,
   journal, support-catalog validation, and pure tests needed for a closed
   Phase 4 trust boundary. The Python overlay, process adapters, and UI were not
   extracted, so their standards findings remain outside the S1 module.
3. **S2 — closed process adapter (completed locally):** one shared injected
   harness proves authorization cancellation, plan substitution rejection,
   signature failure, transcript validation, and `apple,j614s` rejection. No
   live authorization provider or mutation-capable engine was added.
4. **S3 — production identity design (completed locally):** the app-owned
   trust-root and candidate-bound plan interfaces are specified without
   installing keys, signing artifacts, publishing catalogs, or enabling
   mutation.
5. **Independent media evidence (format-aware static candidate accepted
   locally):** the validation-only Apple target was re-authored on the accepted
   ARM64 ISO base, and the accepted ISO passed the canonical format-aware static
   verifier with a complete build log and environment manifest. The compared
   ISO bytes are not reproducible, with known generated-content and timestamp
   differences documented. A later physical boot requires a dedicated,
   recoverable, officially supported M1 canary with a pre-existing Asahi
   environment. Keep both outside user release paths and do not treat a
   supported-canary boot as M4 acceptance.
6. **Explicit owner gate:** stop and request authorization before any push,
   pull request, merge, signing, notarization, publication, channel change,
   installed-user integration, privileged authorization test, or physical
   canary mutation.

## Next decision

The accepted-base re-authoring, signed Asahi dependency closure, format-aware
static validation, and full isolated build record are complete locally. The
next safe implementation unit is to prepare the candidate-specific read-only
canary procedure and independently audit its internal-NVMe no-write controls.
Stop before any media write and select a dedicated, recoverable, officially
supported M1 canary with a pre-existing correctly paired Asahi
UEFI/m1n1/U-Boot environment.

Any removable-media write, Asahi preparation, boot, publication, channel
change, or physical-device work remains a separate owner gate. Existing-user
machines are excluded. M4/J614s must remain rejected while Asahi's official
installer status remains unsupported.
