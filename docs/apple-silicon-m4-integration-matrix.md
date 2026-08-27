# Apple Silicon M4 selective integration matrix

Status: S1 implemented locally; no user integration
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
- No Apple-target ISO has passed the required disposable build and
  Asahi-prepared m1n1/U-Boot boot test.
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
- The 12 trust-core interface tests pass in both debug and release
  configurations through XcodeBuildMCP 2.7.0.

## Proposed source-only sequence

This sequence is a proposal, not authorization to execute later gates.

1. **S0 — review record:** approve this matrix and keep the branch
   documentation-only.
2. **S1 — non-operational core (completed locally):** re-author only the value types, parsers,
   journal, support-catalog validation, and pure tests needed for a closed
   Phase 4 trust boundary. The Python overlay, process adapters, and UI were not
   extracted, so their standards findings remain outside the S1 module.
3. **S2 — closed process adapter:** add one shared harness whose tests prove
   authorization cancellation, plan substitution rejection, signature
   failure, transcript validation, and `apple,j614s` rejection. Do not add a
   live authorization provider or mutation-capable engine.
4. **S3 — production identity design:** specify the app-owned trust-root and
   candidate-bound plan interfaces without installing keys, signing artifacts,
   publishing catalogs, or enabling mutation.
5. **Independent media evidence:** build and boot the validation-only Apple ISO
   in a disposable Linux/Asahi-prepared environment. Keep this outside user
   release paths.
6. **Explicit owner gate:** stop and request authorization before any push,
   pull request, merge, signing, notarization, publication, channel change,
   installed-user integration, privileged authorization test, or physical
   canary mutation.

## Next decision

The next safe action, if separately approved, is S2 only: a local closed
process adapter with cancellation, substitution, signature-failure, transcript,
and M4-rejection tests. It must not include a live authorization provider,
installer registration, release wiring, privileged execution, or any path that
changes an existing user's machine.
