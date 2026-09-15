# Portable Omarchy Mac installer

Date: 2026-09-10
Status: Design confirmed by the owner. The [specification](portable-macos-installer-spec.md) and [tickets](portable-macos-installer-tickets/README.md) are maintained in this repository. Local implementation of the capability proof is in progress; the shipping installer and release are unchanged.

## Agreed outcome

Owner clarification during implementation, 2026-09-10: the installer experience must remain exactly as before, with no new screens. Preserve the existing layout, navigation and installation flow. Temporary privileges operate behind the existing Install action; restart handling uses existing review, confirmation and error surfaces. Developer qualification tooling is separate and never ships in the app, ZIP or Cask.

The Mac app is a disposable launcher for installing Omarchy on disk. A website user downloads a ZIP, extracts the app, and opens it where it was downloaded. Moving it to Applications, installing a package, and enabling a persistent helper are not prerequisites.

The same signed app will be submitted to central `homebrew/cask`. Executing directly through Homebrew is preferred, but the user accepts ordinary Cask installation. Use that supported route initially: Homebrew places the app, then the user launches it. A documented install-and-open shell command can combine those steps. Homebrew installation must never itself start disk installation.

The user accepts a deprecated API for temporary privilege elevation. There is no ongoing Mac updater or service after installation. Website publication may precede central Homebrew acceptance. This change does not alter Omarchy's own update system.

If an installation is interrupted, it can remain incomplete. On the next launch the user starts over, rather than relying on automatic background completion or an elaborate resume experience. Starting over must safely handle the partitions already created by the failed attempt.

Do not implement automatic migration or cleanup of old `.pkg` installations in the product. Old helper cleanup on the owner's M1 Pro and M2 Max is separately authorized housekeeping.

## Recommended architecture

### Distribution

- Publish the existing SwiftUI app as a Developer ID signed, hardened, notarized and stapled `.app` inside a ZIP. Recreate the distributable ZIP after stapling, then hash that final ZIP.
- Keep the launcher, signed helper and bundled validation engine together. The user does not need Homebrew Python or Xcode.
- Resolve resources relative to the running bundle; remove assumptions that the launcher lives in `/Applications`.
- Use a private staging location where needed for privileged execution. Prove the location and trust handling with real quarantined downloads; do not disable Gatekeeper or strip quarantine as a workaround.
- Keep existing hardware eligibility, signed catalogs, channel selection, exact-plan review and Recovery handoff behavior except for the explicit interruption changes below.
- Use immutable versioned ZIP URLs and checksums for Cask releases, with website links pointing to the recommended release.

### Temporary privileged worker

Use an adapter around `Authorization Services` and `SMJobSubmit` to start the signed helper as a temporary system job when privileged work is needed. This is the candidate to qualify first, not a claim that the current application already works through this API.

Apple's current DTS guidance specifically suggests `SMJobSubmit` for one-shot privileges in widely distributed products. The current SDK still declares it as deprecated; current Sparkle source uses it for a non-permanent installer job. Neither `SMJobBless` nor an installed `SMAppService` daemon matches the agreed lifetime.

- Keep the GUI unprivileged and retain mutual signing checks on XPC connections, exact-plan authorization, payload verification and the root-owned import boundary.
- Separate the helper's permanent code-signing identity from the temporary job's service address. Prefer one fixed transient address distinct from the legacy helper unless qualification shows a reason to use per-run addresses.
- Enforce one mutating operation across users and all launcher copies. The current per-user app lease and per-process helper actor do not alone cover multiple temporary workers or lingering child processes.
- Model startup, authorization cancellation, health failure, ready, executing, stopping and exited states explicitly. A plist's existence is not a health check.
- Give the worker a finite lifetime: expire if never used; remain available for the bounded request sequence; exit and remove the temporary job when finished or safely stopped. Do not terminate after a ping or credential rejection.
- No persistent plist in `/Library/LaunchDaemons`, no copied helper in `/Library/PrivilegedHelperTools`, no login item, and no service that returns after reboot.
- Keep temporary worker cleanup separate from retained installation evidence. Ordinary completion can remove disposable execution files once the handoff no longer needs them.
- The native administrator authorization and the existing machine-owner/Recovery credential flow are different. Do not promise a single total password prompt without proving it.

### Interruption and Start over

This requires an engine capability change, not just a different download format.

Current code recognizes a complete four-part Omarchy layout, excludes partial/ambiguous layouts, and refuses an existing installation. The removal feature also refuses partial layouts. Existing journals stop when destructive intent lacks its completion checkpoint. Reopening the current app is therefore not a reliable restart mechanism.

Implement the following behavior:

1. Before disk mutation, persist a small root-owned attempt record containing the disk identity, protected macOS/ISC/Recovery identities, pre-existing partition inventory and approved target extent.
2. Record intent and observed results around individual partition-changing operations, including partition/container UUIDs. Existing checkpoints span too many operations to identify every partial result.
3. If the user quits, request a stop at an operation boundary, then leave the attempt incomplete. Do not deliberately finish the entire installation after the UI closes. A process crash or loss of power also leaves an incomplete attempt. No design can guarantee a safe instantaneous stop inside an in-flight APFS operation.
4. On the next launch, inspect unfinished-attempt evidence before normal planning and establish that no previous mutator remains active.
5. Offer **Start over** only after reconciling the attempt with the current disk. Show the specific unfinished Omarchy installation to be removed, obtain the user's confirmation and remove only resources attributable to that attempt.
6. Reinspect and obtain a fresh installation plan and approval. Reuse previously freed space when valid; never blindly repeat the old macOS shrink request.
7. Journal cleanup itself so interruption during Start over can also be reconciled.

Missing/corrupt provenance, changed disk identities, unrecognized partitions, unhealthy/incomplete APFS operations, an active mutator, or evidence that the prior installation became a used system must produce a specific blocker. Do not infer permission to erase a partition from its name, type, approximate position or a stale failed-attempt flag. Preserve macOS, its files, Apple recovery partitions and unrelated installations.

The existing complete-install refusal and separate, explicitly reviewed Omarchy removal flow remain in place. This plan does not add automatic deletion of arbitrary existing installations.

### Old package compatibility

The new product will not repair or migrate legacy `.pkg` installations. It still must detect an incompatible active legacy helper and stop before privileged disk work, rather than permit old and new workers to operate concurrently. This is a compatibility guard, not an automatic migration feature.

Owner-machine housekeeping is separate: inspect macOS identity and active installer work, unload the exact idle legacy helper and remove its verified system plist. Preserve the Mac app, disk contents, catalogs and recovery journals. Do not run the broad preclean script: it also removes application state and can perform disk cleanup.

## Delivery sequence and proof

| Stage | Change | Acceptance evidence |
| --- | --- | --- |
| 1. Capability proof | Isolated temporary-worker launcher using the intended signing and authorization mechanism | Launch from a browser-downloaded ZIP with quarantine intact; harmless authenticated request; authorization cancellation; worker exit; no persistent service or boot registration. No disk writes. |
| 2. Privileged session | Replace the package-presence gate; add bounded worker lifecycle and machine-wide serialization | Focused Swift tests; healthy and mismatched helper; two launcher copies/users; startup timeout; denied authorization; orphan/child lifetime handling. |
| 3. Restart capability | Add attempt provenance, operation-level records, safe stop and Start over | Engine tests with interruption injected before and after each mutation boundary and during cleanup; protection of original partitions; no second shrink; incomplete and ambiguous evidence cases. |
| 4. Portable app and ZIP | Preserve existing screens and navigation while updating resource paths, packaging and artifact validation | Swift debug/release tests and strict formatting; Python tests; packaging checks; unsupported-host rejection; verify fresh, denied, interrupted, Start over and blocked behavior through existing UI surfaces. |
| 5. End-to-end qualification | Exercise the exact immutable candidate on approved test hardware | Downloads and Homebrew placement paths on supported macOS; one complete installation through Recovery; controlled interruption followed by verified Start over; unchanged protected partition identities and macOS access. |
| 6. Release | Publish immutable ZIP and checksum; update website; submit central Cask | Gatekeeper and signature verification on public bytes; Cask install/uninstall and audit; canonical homepage/release metadata; Homebrew maintainer review. |

Use an isolated checkout for implementation and preserve the primary checkout's dirty files. Keep the scope of production signing, physical disk tests and release publication explicit at the relevant execution stage. The current request plans those actions; it does not perform them.

Stage 1 is the early decision gate. If a notarized downloaded launcher cannot reliably start and retire its temporary worker on the supported macOS versions, return with the measured failure and concrete alternatives before integrating the disk engine.

Stage 3 is essential to the requested retry experience and likely more substantial than the packaging work. Do not publish app-only installation with a claim that rerunning fixes partial installations until that behavior is proven.

## Main source touchpoints

Paths below are relative to `omarchy-mx-mac/apps/omarchy-apple-installer/`.

| Area | Existing files |
| --- | --- |
| Service discovery and temporary lifecycle | `Sources/OmarchyAppleInstaller/InstallerHelperServiceManager.swift`, `InstallerProductIdentity.swift`, `InstallerReleaseConfiguration.swift`, `Sources/OmarchyAppleInstallerHelper/main.swift` |
| Trusted IPC and execution | `Sources/OmarchyAppleInstaller/AuthenticatedEngineXPCSubmitter.swift`, `ClosedEngineHelperServer.swift`, `InstallerExecutionCoordinator.swift`, `EngineHandoffPackageImporter.swift`, `PinnedAsahiEngineExecutor.swift` |
| UI and lifecycle | `Sources/OmarchyInstallerUXCore/InstallerSession.swift`, `PlainLanguage.swift`, `Sources/OmarchyAppleInstallerApp/LiveInstallerEnvironment.swift`, `OmarchyAppleInstallerApp.swift`, `OmarchyRemovalSheet.swift` |
| Attempt ownership, partial detection and restart | `Engine/overlay/src/omarchy_planner.py`, `omarchy_asahi.py`, `omarchy_stage1.py`, `Sources/OmarchyAppleInstaller/OmarchyRemoval.swift` |
| Distribution | `Packaging/build-app.sh`, `Packaging/notarize-app.sh`, `Packaging/pkg/`, `scripts/publish-channels`, associated channel/packaging tests and release instructions |

Existing signed engine archives must be rebuilt and repinned through the normal engine release process if Stage 3 changes engine behavior. Editing source without rebuilding the selected immutable archive does not change what users execute.

## Vendor sources read for this plan

- [Apple DTS: BSD Privilege Escalation on macOS](https://developer.apple.com/forums/thread/708765) — one-shot versus ongoing privilege and `SMJobSubmit` guidance.
- [Apple: SMJobSubmit](https://developer.apple.com/documentation/servicemanagement/smjobsubmit(_:_:_:_:)) — system-domain authorization contract.
- [Apple: Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) — ZIP submission, app stapling and rebuilding the final distribution archive.
- [Sparkle installer launcher](https://github.com/sparkle-project/Sparkle/blob/2.x/InstallerLauncher/SUInstallerLauncher.m) — current reference use of temporary jobs; reference only, not a proposed updater dependency or wholesale code import.
- [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook) — app artifacts, destination, checksums and uninstall behavior.
- [Homebrew manual](https://docs.brew.sh/Manpage) — `brew exec` operates on formula-provided commands and installs missing formulae; it is not a portable GUI-Cask run-once facility.
- [Homebrew: Adding Software](https://docs.brew.sh/Adding-Software-to-Homebrew), [Acceptable Casks](https://docs.brew.sh/Acceptable-Casks), [Package Acceptance Policy](https://docs.brew.sh/Package-Acceptance-Policy) — central submission, security, current-platform compatibility, canonical distribution and public-interest requirements. Acceptance is a maintainer decision.

## Separate housekeeping status

Read-only checks on 2026-09-10 found the M2 Max reachable at its configured LAN address but running Linux. The M1 Pro did not answer at its configured LAN address; the controller Mac's Thunderbolt bridge was inactive. No old helper has been removed. Booting the targets into macOS and restoring connectivity is pending owner action; no reboot or disk cleanup was attempted.
