Exploration is complete and all anchors verified. Here is the implementation plan.

---

# Omarchy Apple Installer UX Redesign — Implementation Plan

Package root: `/Users/maralc/dev/omarchy/omarchy-mx-mac-integration/apps/omarchy-apple-installer` (all relative paths below are under this root unless absolute).

## 0. Verified ground truth (corrections and load-bearing facts)

- The install journal lives under the **helper's** working directory: `ClosedEngineHelperServer` is constructed with `workingDirectory = /var/db/com.omarchy.mx.installer` (`Sources/OmarchyAppleInstallerHelper/main.swift:54`, `InstallerProductIdentity.helperWorkingDirectory`), the importer materializes the package there, and `PinnedAsahiEngineExecutor.preparePersistentJournal` (`:586-631`) derives `&lt;workingDirectory&gt;/execution-journals/&lt;bindingDigest-hex&gt;.jsonl`. Directory is root-owned 0700, file 0600 root. **The app can never read it directly.** This decides the streaming design (Section 1).
- `ClosedEngineXPCService` has exactly one method (`AuthenticatedEngineXPCSubmitter.swift:6-14`); the submitter creates a fresh `NSXPCConnection` per submit and invalidates it in the reply (`:76-134`). The app-side connection currently sets no `exportedInterface` — free slot for a callback object.
- The helper endpoint (`ClosedEngineHelperServer.swift:118-146`) runs its work in a detached `Task`; `NSXPCConnection.current()` is only valid synchronously inside the exported method, before that Task.
- Engine fsyncs after each journal append (`Engine/overlay/src/omarchy_contract.py:258,467`), and stage-1 is checkpoint-resumable (`omarchy_stage1.py:47-77`); checkpoint ids/phases confirmed at `omarchy_stage1.py:24-44`.
- `EngineTranscriptDecoder.decode` accepts a **prefix** transcript: it requires trailing `\n`, contiguous sequence from 1, inspection@1/inventory@2/plan@3 order, monotonic phases — but does *not* require a completion message (`EngineContract.swift:127-370`). A complete-lines-only buffer therefore validates incrementally via the public `AppleInstallerTrustCore().validateEngineTranscript(_:)`.
- Username charset is `[A-Za-z0-9._-]`, 1–255 bytes; password 1–1024 bytes UTF-8, no NUL/LF/CR (`MachineOwnerAuthorization.swift:27-49`). OpenDirectory rejection surfaces today as `ClosedEngineHelperError.invalidMachineOwnerCredentials` bridged to a generic `helperRejected(domain:code:)` NSError on the app side.
- Downloads use `URLSession.shared.download(from:)` with no progress (`VerifiedArtifactStager.swift:308-321`); expected byte sizes are pinned per artifact from the signed catalog (`PinnedInstallerArtifact.expectedSizeBytes`).
- Fixture `/Users/maralc/dev/omarchy/omarchy-mx-mac-integration/evidence/apple-silicon/2026-08-29-m1-fresh-install-v6/execution-journal.jsonl` is a 10-line, fully valid `awaiting_recovery` transcript for `apple,j314s` (resize candidate) — it decodes through the real trust core, so the mock can derive every display model from it.
- Tests use `@testable import OmarchyAppleInstallerTrustCore` and already pass in debug and release, so testability is enabled for release test builds in this toolchain; a new library test target will behave the same.
- This dev machine is the explicitly blocked `apple,j614s` M4 (`MacHostInspection.swift:53`), which produces the locked state; keep it fail-closed.

---

## 1. Progress streaming design

### Comparison

**(a) Daemon-side journal tailer forwarding envelopes over an XPC client callback — CHOSEN.**
- The journal is root:0700/0600 under `/var/db`; only the helper can read it. The helper already owns the run lifecycle (single-flight actor) and the XPC connection stays open for the duration of `submit` (reply arrives at the end), so a callback interface on the same connection is the natural, already-authenticated channel (mutual codesigning requirements already pin both peers).
- Zero changes to the engine, zero changes to `PinnedAsahiEngineExecutor`, no new files on disk, no permission weakening. Advisory-only by construction: the authoritative transcript still arrives via the existing `reply` path and is still re-validated by both the helper (`ClosedEngineHelperServer.swift:87-105`) and the app.

**(b) Piping engine stdout — rejected.** The engine's contract output is the journal (env `OMARCHY_ENGINE_JOURNAL`), not stdout; stdout/stderr are deliberately nulled (`PinnedAsahiEngineExecutor.swift:214-216`). Using stdout would require touching the most qualification-sensitive file's process wiring, changing the pinned engine to double-write, and would create a second, non-fsync'd, unvalidated channel. Worst churn, weakest guarantees.

**(c) App-readable progress file — rejected.** Would require the root daemon either to relax the 0700/0600 hardening or to write into a user-controllable directory (symlink/planting hazards for root, exactly what the current `lstat`/`O_NOFOLLOW` discipline exists to prevent). Also adds polling with no auth binding to the run.

### New/changed trust-core surface (exact signatures)

**New file `Sources/OmarchyAppleInstaller/EngineJournalProgress.swift`** (small; the only place the XPC callback protocol lives):

```swift
@objc public protocol ClosedEngineProgressClient {
  // One or more complete, "\n"-terminated NDJSON envelope lines, in file order.
  // Fire-and-forget (no reply block): XPC does not queue unbounded replies.
  func engineJournalDidAppend(_ completeLines: Data)
}

public protocol EngineJournalProgressSink: Sendable {
  func journalDidAppend(_ completeLines: Data)
}
```

**New file `Sources/OmarchyAppleInstaller/EngineJournalTail.swift`:**

```swift
public enum EngineJournalLocator {
  /// Mirrors PinnedAsahiEngineExecutor.preparePersistentJournal path derivation:
  /// &lt;workingDirectory&gt;/execution-journals/&lt;SHA256Digest(rawValue: bindingDigest).hexadecimal&gt;.jsonl
  /// Returns nil for a malformed digest.
  public static func journalURL(workingDirectory: URL, bindingDigest: String) -&gt; URL?
}

public actor EngineJournalTailer {
  public init(
    journalURL: URL,
    expectedOwner: uid_t,
    pollInterval: Duration,          // default .milliseconds(250)
    maximumChunkBytes: Int,          // default 262_144
    sink: any EngineJournalProgressSink
  )
  public func start()
  public func stop() async           // performs one final drain, then stops
}
```

Tailer behavior:
- Loop with `Task.sleep` (suspending, never blocking a pool thread). File may not exist yet — keep polling silently.
- Each tick: `open(O_RDONLY|O_CLOEXEC|O_NOFOLLOW)`, `fstat` guard (regular file, `mode &amp; 0o077 == 0`, `st_uid == expectedOwner`, `st_size &lt;= PinnedAsahiEngineExecutor.maximumTranscriptBytes`) — same fail-closed checks as `readTranscript` (`:644-674`) but tolerant of a growing file.
- Read from the last forwarded byte offset; scan backward for the final `\n`; forward only whole lines (`[offset, lastNewline+1)`), capped at `maximumChunkBytes` per message (a single oversized line up to the decoder's 65,536-byte max is still forwarded alone). Partial trailing line stays buffered in the file, not in memory.
- Always starts from **offset 0** — full replay on every attach (this is what makes reattach trivial; see below).
- Any guard failure: stop forwarding silently. Advisory channel; never propagate errors into the run.

Backpressure/rate limiting: poll cadence (4 Hz) is the coalescer; messages are no-reply so there is no reply-queue growth; total journal is capped at 8 MiB by contract, ~tens of lines in practice, so worst-case total streamed bytes are trivial.

**`Sources/OmarchyAppleInstaller/ClosedEngineHelperServer.swift` (edit, ~30 lines):**

```swift
// Actor method gains an optional sink; default nil keeps every existing call site and test identical.
public func submit(
  packageDirectory: FileHandle,
  authorization: MachineOwnerAuthorization,
  operation: EngineHandoffOperation = .install,
  progress: (any EngineJournalProgressSink)? = nil
) async throws -&gt; Data
```

- After `importer.prepare` (so `package.bindingDigest` is known) and *before* `executor.execute`: if `progress != nil` and `EngineJournalLocator.journalURL(workingDirectory:bindingDigest:)` resolves, start an `EngineJournalTailer` with `expectedOwner: geteuid()` (root, matching the executor's `expectedFileOwnerID`). `await tailer.stop()` on both the success and the throw path (wrap the executor call in `do/catch`; actors cannot `await` in `defer`).
- In `ClosedEngineXPCServiceEndpoint.submit`: capture the callback proxy **synchronously**, before the `Task`:

```swift
let client = (NSXPCConnection.current()?
  .remoteObjectProxyWithErrorHandler { _ in /* peer has no client object: disable streaming */ })
  as? ClosedEngineProgressClient
let sink = client.map(XPCJournalProgressSink.init)   // tiny @unchecked Sendable wrapper
```

- In `AuthenticatedEngineXPCListenerDelegate.listener(_:shouldAcceptNewConnection:)` add one line: `connection.remoteObjectInterface = NSXPCInterface(with: ClosedEngineProgressClient.self)`.
- **`ClosedEngineXPCService.submit` is byte-for-byte unchanged.** That is the version-skew story: old helper never calls back (app falls back to indeterminate after ~3 s without a chunk); new helper + old app hits the proxy error handler and simply stops streaming. No negotiation, no new failure modes on the authoritative path.

**`Sources/OmarchyAppleInstaller/AuthenticatedEngineXPCSubmitter.swift` (edit, ~20 lines):**

```swift
public init(
  machServiceName: String,
  helperCodeSigningRequirement: String,
  journalProgress: (@Sendable (Data) -&gt; Void)? = nil
) throws
```

Inside `submit(_:authorization:operation:)`, when `journalProgress != nil`:

```swift
connection.exportedInterface = NSXPCInterface(with: ClosedEngineProgressClient.self)
connection.exportedObject = EngineProgressClientRelay(handler: journalProgress)  // NSObject, ClosedEngineProgressClient
```

`EngineHandoffSubmitting` and `ClosedEngineHandoffProcess` stay untouched (progress is bound at submitter construction, not threaded through the protocol).

**`Sources/OmarchyAppleInstaller/InstallerExecutionCoordinator.swift` (edit, additive param):**

```swift
public func execute(
  _ prepared: PreparedInstallerPlanExecution,
  approval: CandidateBoundPlanApproval,
  configuration: InstallerReleaseConfiguration,
  handoffDirectory: URL,
  machineOwnerAuthorization: MachineOwnerAuthorization,
  journalProgress: (@Sendable (Data) -&gt; Void)? = nil
) async throws -&gt; InstallerExecutionProgress
// identical addition on retryRecoveryAuthorization(...)
```

It forwards `journalProgress` into the submitter initializer. Nothing else in the trust chain changes.

### App-side envelope validation

New UXCore type (Section 2) `LiveInstallJournalModel`:
- Maintains `raw: Data` of complete lines. `mutating func consume(_ chunk: Data)`: if the buffer is non-empty and the chunk's first line carries `"sequence":1` (helper re-replay from offset 0, e.g. a retry submit on a fresh connection), **replace** the buffer; otherwise append.
- After each mutation, run `AppleInstallerTrustCore().validateEngineTranscript(raw)` (public API; no new trust-core surface). Success → derive display state: current phase (max checkpoint phase seen, else inferred from last event name), completed checkpoints, last event, completion outcome.
- Any decode/validation error (sequence gap, garbage line, phase regression) → set `degraded = true`: the UI drops to an indeterminate bar labeled with the last good phase. **Never** surface as an install failure and never cancel anything — the authoritative outcome still arrives via the existing reply and post-run validation, which remain unchanged and authoritative.
- Re-validating the whole ≤8 MiB, ~10–40 line buffer at ≤4 Hz on a background task is negligible; publish the derived display struct to the `@MainActor` session.

### App quits mid-run and reattaches

- The helper's detached Task keeps executing after connection invalidation; the reply is dropped, the journal keeps being written and fsync'd, the single-flight actor stays busy until the engine exits.
- Because the tailer always replays from offset 0 on attach, "reattach" needs no protocol state: any future submit for the same binding digest streams the whole journal first, and the engine's own resume logic (`run_stage1` skips completed checkpoints; a finished journal returns its completed outcome immediately) makes an identical resubmission converge fast. In-memory plan/approval are gone after a quit, so the UI path is: relaunch → re-inspect → re-prepare → if the disk is unchanged the digests match and resubmission resumes; if stage-1 already mutated the disk, the engine inventories a `repair` candidate and the normal flow converges through the repair operation. This is pre-existing product behavior; the streaming layer just makes it visible.
- v1 explicitly does **not** add a read-only "observe a run in flight" XPC method. If a submit while busy throws `ClosedEngineHelperError.busy` (seen as `helperRejected`), the UI shows a dedicated "an installation appears to be in progress — do not power off; quit and reopen later" failure card. A future `observeJournal(bindingDigest:)` method is a noted extension, not in scope.

---

## 2. App architecture

### Targets (Package.swift edit)

Add one library target so the state machine, mapping layer, and journal model are unit-testable in debug **and** release without importing an executable target:

```swift
.target(
  name: "OmarchyInstallerUXCore",
  dependencies: ["OmarchyAppleInstallerTrustCore"],
  path: "Sources/OmarchyInstallerUXCore"
),
.testTarget(
  name: "OmarchyInstallerUXCoreTests",
  dependencies: ["OmarchyInstallerUXCore"],
  path: "Tests/OmarchyInstallerUXCoreTests"
),
// OmarchyAppleInstallerApp dependencies gain "OmarchyInstallerUXCore"
```

### File layout

`Sources/OmarchyInstallerUXCore/` (Foundation + Observation only, no AppKit/SwiftUI):
- `InstallerSession.swift` — `@MainActor @Observable public final class InstallerSession` + `InstallerSessionPhase`.
- `InstallerEnvironment.swift` — the seam protocol (below) + display-model structs (`HostDisplay`, `PlanDisplay`, `HelperDisplay`, `InstallProgressDisplay`, `HandoffDisplay`, `CompletionDisplay`, `FailureDisplay`, `AssetProgressUpdate`).
- `LiveInstallJournalModel.swift` — Section 1 consumer.
- `PlainLanguage.swift` — mapping layer (below).
- `CredentialInput.swift` — sheet validation model mirroring `MachineOwnerAuthorization` rules.

`Sources/OmarchyAppleInstallerApp/`:
- `OmarchyAppleInstallerApp.swift` — slimmed to `@main`, the `NSApplicationDelegate` instance-lease logic (kept verbatim), and the `WindowGroup` hosting the new root. The current 879-line body is deleted at the end of the build (WP11).
- `InstallerRootView.swift` — phase switch → screen; hosts the credential `.sheet`.
- `LiveInstallerEnvironment.swift` — real `InstallerEnvironment`: wraps `AppleSiliconHostInspector`, `EngineInspectionRunner`, `InstallerReleaseConfigurationLocator`, `AcceptedCatalogIdentityStore`, `InstallerReleaseAssetCoordinator`, `InstallerAllocationRecommendation`, `InstallerPlanPreparationCoordinator`, `InstallerHelperServiceManager`, `InstallerExecutionCoordinator`; privately retains the trust objects (`AppleSiliconHostInspection`, `Data` transcripts, `PreparedInstallerPlanExecution`, `InstallerPlanReview`, `CandidateBoundPlanApproval`, `InstallerReleaseConfiguration`) and the `installerWorkspace()` logic moved from the old view (`OmarchyAppleInstallerApp.swift:790-826`).
- `PreviewInstallerEnvironment.swift` — entirely inside `#if DEBUG` (Section 6).
- `InstallerTheme.swift` — retro tokens: the palette from the prototype (`omarchy-mx-mac/.../InstallerView.swift:1195-1220`, renamed `OmarchyTheme.*`), monospaced type scale, spacing; replaces `OmarchyInstallerPalette`.
- `RetroComponents.swift` — `RetroBackdrop` (grid + scanline Canvas), `RetroRule`, `RetroButton`, `StatusLight`, `PixelMark`, `SignalPanel`, `RetroProgressBar` (block glyphs `█▓░`), `RetroDisclosure` (the "Details/Advanced" affordance), `StepRail` (adapted from prototype `InstallerView.swift:140-222`).
- `Screens/WelcomeScreen.swift` (A), `Screens/PreparingScreen.swift`, `Screens/PlanReviewScreen.swift` (B), `Screens/CredentialSheet.swift` (C), `Screens/InstallingScreen.swift` (D), `Screens/RecoveryHandoffScreen.swift` (E), `Screens/CompletionScreen.swift` + `Screens/FailureScreen.swift` + `Screens/UnsupportedScreen.swift` (F and error/locked states).
- `InstallerChrome.swift` — deleted in WP11 (replaced by Theme/RetroComponents).

### Phase machine (replaces the 11 `@State` booleans)

```swift
public enum InstallerSessionPhase: Sendable {
  case inspecting
  case unsupported(FailureDisplay)                       // locked; re-inspect only
  case welcome(HostDisplay)                              // Screen A
  case preparingPlan(AssetProgressUpdate)                // catalog fetch, downloads, engine inspect+plan
  case planReview(PlanDisplay, acknowledged: Bool)       // Screen B
  case awaitingInstall(PlanDisplay, helper: HelperDisplay, sheet: CredentialSheetState)
  case installing(InstallProgressDisplay)                // Screen D
  case awaitingRecovery(HandoffDisplay)                  // Screen E (awaiting_recovery | awaiting_media)
  case done(CompletionDisplay)                           // Screen F (installed)
  case failed(FailureDisplay)                            // includes retryRecoveryAvailable flag
}
```

Legal transitions (anything else is a guarded no-op):

| From | To | Trigger |
|---|---|---|
| inspecting | welcome | host + engine inspect OK, supported, not blocked |
| inspecting | unsupported | blockedReason, engine unsupported, engine artifact unavailable, device mismatch |
| unsupported | inspecting | Re-inspect |
| welcome | preparingPlan | Continue |
| welcome | inspecting | Re-inspect |
| preparingPlan | planReview | prepared |
| preparingPlan | failed | preparation error (recoverable → Start over) |
| planReview | awaitingInstall | Approve (requires `acknowledged == true`; calls `environment.approve`) |
| planReview | preparingPlan | Re-prepare |
| awaitingInstall | installing | sheet submit (helper `.enabled` + `CredentialInput` valid) |
| awaitingInstall | planReview | Back (drops approval in environment, mirroring today's reset) |
| installing | awaitingRecovery / done / failed | reply outcome via `InstallerNextAction` |
| failed(retry) | installing | sheet submit with `.retryRecoveryAuthorization` |
| failed / done / awaitingRecovery | inspecting | Start over (full reset identical to `inspectThisMac()` field resets at `:829-845`) |

Mapping of every existing gate:
- `isInspecting` → `.inspecting`. `installationBlocked` / `engineInspectionError` / `inspectionError` (`:82-84, :191-265`) → `.unsupported`/`.failed` payloads.
- `isPreparingPlan` / `planPreparationError` → `.preparingPlan` / `.failed`.
- `planReview` + `ownerAcknowledged` (`:273-279`) → `.planReview(_, acknowledged:)`; the Approve action still calls `InstallerPlanReview.approve(confirming:)` with a confirmation built **from the retained trust objects** exactly as `approve(_:)` does today (`:644-665`) — the display model is render-only and never the source of confirmation values.
- `planApproval` + `preparedPlan` + `releaseConfiguration` non-nil → encoded structurally: `.awaitingInstall` is only constructible by the environment after a successful approve, so `canStartInstallation`'s nil-checks (`:433-443`) become unrepresentable states.
- `helperServiceStatus` / `helperRegistrationError` (`:58-59, :418-431, :667-694`) → `HelperDisplay` inside `.awaitingInstall`; `refreshHelperStatus()` re-reads on `scenePhase == .active` as today (`:106-110`). The helper-registration confirmation dialog copy (`:111-124`) is preserved as a confirm step before `registerHelper()`.
- `machineOwnerCredentialsReady` (`:445-450`) → `CredentialInput.validated()` which attempts the same `MachineOwnerAuthorization(username:password:)` initializer.
- `isExecuting` / `hasExecutionStarted` (`:63-64`) → the phase machine (only `.awaitingInstall → .installing`, no re-entry); the daemon single-flight remains the backstop.
- `recoveryAuthorizationRetryAvailable` + `showsRecoveryRetryConfirmation` (`:65,:68,:125-138,:452-462,:708-717`) → `.failed(FailureDisplay(retryRecoveryAvailable: true))`, set from `RecoveryAuthorizationRetryPolicy.isEligible(after:)` unchanged; the retry confirmation copy moves into the sheet's retry variant.
- `showsExecutionConfirmation` (`:139-153`) → the credential sheet's explicit destructive "INSTALL" button is the confirmation click (Section 3); the semantic chain (checkbox → approve → separate explicit start confirmation → password) is preserved, with the confirmation and credential steps combined into the auth-dialog-style sheet per the decided direction.
- `executionProgress` / `executionMessage` (`:51,:464-479,:774-779`) → `.awaitingRecovery` / `.done` via `InstallerNextAction` mapping; `.attachInstallationMedia` renders as an `awaitingRecovery` variant, `.manualRecovery` as `.failed`.
- `selectedStepID` → derived read-only rail highlight (`InstallerRailStep`: INSPECT, REVIEW, AUTHORIZE, INSTALL, RECOVERY, DONE); the sidebar is no longer clickable navigation.

Environment seam:

```swift
public protocol InstallerEnvironment: Sendable {
  func inspect() async throws -&gt; HostDisplay
  func preparePlan(progress: @escaping @Sendable (AssetProgressUpdate) -&gt; Void) async throws -&gt; PlanDisplay
  func approve() throws                                   // review.approve(confirming:) on retained objects
  func discardApproval()
  var helperStatus: HelperDisplay { get }
  func registerHelper() throws
  func execute(
    operation: InstallOperationKind,                       // .install | .retryRecoveryAuthorization
    authorization: MachineOwnerAuthorization,
    journal: @escaping @Sendable (Data) -&gt; Void
  ) async throws -&gt; CompletionDisplay
}
```

### Copy movement

- Move to `PlainLanguage.swift`: `executionMessage(_:)` strings (`OmarchyAppleInstallerApp.swift:464-479`), all status-banner strings (`:221-247`), credential explainer (`:288-291`), confirmation-dialog bodies (`:120-152`), preflight row labels (`:176-183`), error strings from `prepareSignedPlan`/`performApprovedPlan`/`inspectThisMac` catch blocks.
- New tables in `PlainLanguage.swift`: phase → short title ("Checking this Mac", "Making room on the disk", "Installing the starter boot system", "Waiting for Recovery", "Setting the boot policy", "Handing off installation media", "Installing Omarchy"); event/checkpoint names → one-liners; `EngineCompletionOutcome` → next-step instructions; `requiredHumanSteps` tokens (`enterOneTrueRecovery`, `authenticateMachineOwner`) → numbered plain-language Recovery steps for Screen E; error mapping `(headline, plainDetail, technicalDetail, remedy)` for `EngineXPCSubmissionError`, `ClosedEngineHelperError` domains, `InstallerPlanPreparationError`, `ArtifactStageError`, `InstallerReleaseConfigurationError.releaseResourcesUnavailable`, `InstallerAppError`. `technicalDetail` always preserves `String(describing: error)` for the Details disclosure.
- `Sources/OmarchyAppleInstaller/InstallerWorkflow.swift` is **not touched** (public API pinned by `InstallerWorkflowTests`); the new UI reads `AppleSiliconHostInspection.eligibility` directly and stops consuming the step copy.

### Trust-core files touched (complete list)

1. `Sources/OmarchyAppleInstaller/EngineJournalProgress.swift` — NEW: callback protocol + sink protocol.
2. `Sources/OmarchyAppleInstaller/EngineJournalTail.swift` — NEW: locator + tailer (no existing behavior modified).
3. `Sources/OmarchyAppleInstaller/ClosedEngineHelperServer.swift` — additive optional `progress:` param on the actor's `submit`; endpoint captures client proxy; listener delegate sets `remoteObjectInterface`. `ClosedEngineXPCService` unchanged.
4. `Sources/OmarchyAppleInstaller/AuthenticatedEngineXPCSubmitter.swift` — additive `journalProgress` init param + exported object; new `EngineXPCSubmissionError.machineOwnerCredentialsRejected` case; `EngineXPCErrorBridge` gains a dedicated domain `com.omarchy.mx.installer.machine-owner-authorization` mapped from `ClosedEngineHelperError.invalidMachineOwnerCredentials` (skew-safe: old apps map the unknown domain to the generic `helperRejected` as today).
5. `Sources/OmarchyAppleInstaller/InstallerExecutionCoordinator.swift` — additive `journalProgress` param threaded to the submitter.
6. `Sources/OmarchyAppleInstaller/VerifiedArtifactStager.swift` — download progress (Section 4).
7. `Sources/OmarchyAppleInstaller/InstallerAssetPreparer.swift` — additive optional progress field on the request.
8. `Sources/OmarchyAppleInstaller/InstallerReleaseAssetCoordinator.swift` — threads the same.
9. `Package.swift` — new UXCore target + test target.

**`PinnedAsahiEngineExecutor.swift`: zero changes.** The journal-path convention is duplicated in `EngineJournalLocator` and pinned by a unit test plus an end-to-end helper-server test using a stub executor writing to the real derived path, so drift is caught.

---

## 3. Credential sheet (Screen C)

`Sources/OmarchyAppleInstallerApp/Screens/CredentialSheet.swift`, presented from `InstallerRootView` when phase is `.awaitingInstall(sheet: .presented(...))` or `.failed(retry)` with the sheet requested.

Layout, patterned on the macOS authentication dialog in retro-terminal dress: `PixelMark` (64pt) over a box-drawing frame; title `"OMARCHY INSTALLER WANTS TO MAKE CHANGES."`; body: "Enter the machine owner's macOS user name and password to allow this. This authorizes only the exact approved plan." plus a muted `binding &lt;first-8&gt;…&lt;last-8&gt;` line; footer caption reuses the existing lifecycle copy verbatim ("Used only in memory to authorize Apple's Recovery boot-policy handoff. The password is not written to the plan, handoff package, journal, environment, or logs." — from `OmarchyAppleInstallerApp.swift:288-291`). Retry variant title "RETRY RECOVERY AUTHORIZATION" with the existing revalidation body from `:134-137`.

Fields and validation (mirroring `MachineOwnerAuthorization.swift:27-49` via `CredentialInput` in UXCore):
- `TextField("USER NAME")`, prefilled `NSUserName()`, `.autocorrectionDisabled()`, `.textContentType(.username)`. Live check: 1–255 UTF-8 bytes, charset `[A-Za-z0-9._-]`; violation shows a muted inline reason and disables INSTALL.
- `SecureField("PASSWORD")`, `.textContentType(.password)`, `.privacySensitive()`. Check on edit/submit: 1–1024 UTF-8 bytes, no NUL/LF/CR (structural truth: `CredentialInput.validated()` attempts the real `MachineOwnerAuthorization` initializer; the UI never re-implements the rules as the source of truth).
- Focus order: `@FocusState` — password first when username prefilled non-empty, else username; Tab cycles; Return in password submits when valid; Esc cancels (`.keyboardShortcut(.cancelAction)`); INSTALL is `.keyboardShortcut(.defaultAction)`, disabled until valid.
- Buttons: `CANCEL` and `INSTALL` (primary accent; retry variant `AUTHORIZE`).

Password lifecycle (identical to today's `:751-755`):
- Password lives only in sheet-local `@State var password: String`.
- On submit: build `MachineOwnerAuthorization(username:password: Data(password.utf8))`, set `password = ""` immediately, dismiss, call `session.submitInstall(authorization)`. The session and environment APIs accept only `MachineOwnerAuthorization` — no layer above the XPC boundary can retain the string.
- Wipe on cancel and in `onDisappear` unconditionally; username persists across a rejection.

Error presentation for OpenDirectory rejection: the helper validates credentials before import/execute (`ClosedEngineHelperServer.swift:60-64`), so rejection returns fast. Session flow: submit → phase `.installing` with stage label "VERIFYING MACHINE OWNER…" → on `EngineXPCSubmissionError.machineOwnerCredentialsRejected` (new bridged case) transition back to `.awaitingInstall` with `sheet: .presented(error: .credentialsRejected)`; the sheet reopens showing "The user name or password is not correct." with a brief retro bracket-flash on the fields and password cleared. Other submit errors route to `.failed` with the PlainLanguage mapping.

---

## 4. Download progress

Minimal additive changes, all default-parameterized so existing call sites and the current test doubles keep compiling:

`Sources/OmarchyAppleInstaller/VerifiedArtifactStager.swift`:

```swift
public func stage(
  _ artifact: PinnedInstallerArtifact,
  in stagingDirectory: URL,
  progress: (@Sendable (_ bytesReceived: UInt64) -&gt; Void)? = nil
) async throws -&gt; StagedInstallerArtifact

protocol ArtifactDownloading: Sendable {
  func download(from sourceURL: URL) async throws -&gt; URL                                  // existing, kept
  func download(from sourceURL: URL, progress: (@Sendable (UInt64) -&gt; Void)?) async throws -&gt; URL
}
extension ArtifactDownloading {
  // default forwards to the legacy requirement, ignoring progress — existing fakes unaffected
}
```

`URLSessionArtifactDownloader` implements the progress variant with a delegate-based download task (`urlSession(_:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)` reporting `totalBytesWritten`); the `progress == nil` path keeps using `URLSession.shared.download(from:)` byte-for-byte. Fractions come from the catalog-pinned `expectedSizeBytes`, not the HTTP header. The `reusedExistingFile` fast path reports one final `expectedSizeBytes` callback.

`Sources/OmarchyAppleInstaller/InstallerAssetPreparer.swift`: `InstallerAssetPreparationRequest` gains `public let progress: InstallerAssetProgress?` (default nil in the init) where

```swift
public struct InstallerAssetProgress: Sendable {
  public let didUpdate: @Sendable (_ role: String, _ bytesReceived: UInt64, _ expectedBytes: UInt64) -&gt; Void
}
```

The three concurrent `async let stager.stage(...)` calls pass role-tagged closures (`artifact.role`). `InstallerReleasePreparationRequest` (`InstallerReleaseAssetCoordinator.swift`) gains the same optional field and threads it.

UI (PreparingScreen): per-artifact rows (engine ~tens of MB, metadata, payload multi-GB — the dominant bar) as retro block-glyph bars with `bytes / expected`, aggregate line on top; catalog fetch and engine inspect/plan rows are indeterminate ("VERIFYING…" sweep). Post-download SHA-256 verification renders as indeterminate "VERIFYING" per row (extending progress into `verify()` hashing is noted as an optional follow-up, not in scope).

---

## 5. Debug-only mock / preview mode (M4 demo)

- `Sources/OmarchyAppleInstallerApp/PreviewInstallerEnvironment.swift`, the entire file wrapped in `#if DEBUG … #endif`. Selection at startup: `InstallerEnvironmentFactory.make()` returns the live environment unless (`#if DEBUG` only) `ProcessInfo.processInfo.environment["OMARCHY_INSTALLER_UI_PREVIEW"]` is set. In release the env check does not compile; the factory unconditionally returns live.
- The preview environment reads the fixture path from `OMARCHY_INSTALLER_UI_PREVIEW_JOURNAL` (no fixture is bundled into app resources — nothing ships), decodes it with the real `AppleInstallerTrustCore().validateEngineTranscript(_:)`, and derives `HostDisplay`/`PlanDisplay` from the fixture's inspection/inventory/plan lines. `execute` drips the fixture's raw lines through the same `journal:` callback on a timer (800 ms/line), exercising `LiveInstallJournalModel` and Screen D exactly as production does, then returns the `awaiting_recovery` completion. Trust types with non-public initializers (`InstallerPlanReview`, `CandidateBoundPlanApproval`) are never fabricated — the display-model seam makes that unnecessary, which keeps fail-closed properties intact.
- Scenarios via the env var's value: `fresh-install` (A→B→C→D→E replay), `unsupported` (locked screen — also the real M4 behavior with no env), `credential-reject` (first submit returns `.machineOwnerCredentialsRejected`), `recovery-retry` (throws a retry-eligible error after the stub-and-esp checkpoint), `degraded-journal` (injects one corrupt line to demo indeterminate fallback).
- Demo procedure (M4, zero privileged actions, single instance — the `InstallerAppInstanceLease` enforces it; never `open -n`, ensure no packaged app instance is running first):

```
cd /Users/maralc/dev/omarchy/omarchy-mx-mac-integration/apps/omarchy-apple-installer
OMARCHY_INSTALLER_UI_PREVIEW=fresh-install \
OMARCHY_INSTALLER_UI_PREVIEW_JOURNAL=/Users/maralc/dev/omarchy/omarchy-mx-mac-integration/evidence/apple-silicon/2026-08-29-m1-fresh-install-v6/execution-journal.jsonl \
swift run OmarchyAppleInstallerApp
```

- Release compile-out verification: `swift build -c release` then launch the release binary with the env vars set → behaves as production (locked on M4); plus the config-dependent unit test in Section 6.

---

## 6. Test plan

New tests (Swift Testing or XCTest to match neighboring files):

In `Tests/OmarchyAppleInstallerTrustCoreTests/`:
1. `EngineJournalTailTests.swift` — locator derives `&lt;dir&gt;/execution-journals/&lt;hex&gt;.jsonl` for a known `sha256:` digest and rejects malformed digests (pins the executor convention); tailer forwards only complete lines, buffers partial trailing lines, tolerates a not-yet-created file, respects owner/mode guards, drains on stop, caps chunk size.
2. `ClosedEngineHelperServerProgressTests.swift` — `server.submit(..., progress: recordingSink)` with a stub executor that appends journal lines mid-execute at the locator-derived path → sink receives ordered lines then the reply validates; `progress: nil` path produces byte-identical behavior to today (existing `ClosedEngineHelperServerTests` untouched and still green).
3. `EngineXPCErrorBridgeTests.swift` — `invalidMachineOwnerCredentials` round-trips to `.machineOwnerCredentialsRejected`; unknown domains still map to `helperRejected`.
4. `VerifiedArtifactStagerTests.swift` (extend) — progress callback receives monotonic byte counts from a fake downloader; nil-progress path unchanged.

In `Tests/OmarchyInstallerUXCoreTests/`:
5. `LiveInstallJournalModelTests.swift` — feed the evidence fixture line-by-line (test resource or path-relative read) → assert phase progression preflight→apfs_preparation→stub_and_esp→awaiting_recovery, checkpoint set, final outcome; corrupt line → `degraded == true`, no throw; sequence-restart chunk replaces buffer.
6. `InstallerSessionTests.swift` — scripted mock environment replays the fixture → phase transition sequence matches the table in Section 2; illegal transitions no-op; Back from `awaitingInstall` calls `discardApproval`; credential-reject loops back to the sheet state; retry path only reachable with `retryRecoveryAvailable`.
7. `PlainLanguageTests.swift` — every phase/checkpoint/outcome/known error yields non-empty, distinct headline strings and preserves `technicalDetail`.
8. `CredentialInputTests.swift` — property-style matrix: `CredentialInput.validated() != nil` ⇔ `MachineOwnerAuthorization(username:password:)` succeeds (charset, 255/256 boundary, 0/1/1024/1025 bytes, LF/CR/NUL, non-UTF-8 rejected upstream).
9. `InstallerEnvironmentFactoryTests.swift` (app behavior via UXCore-visible factory input) — with the preview env var set, `#if DEBUG` asserts the preview environment is chosen, `#else` asserts live is chosen (compiles and passes in both configurations, proving compile-out).

Keeping the existing suite green: every trust-core change is additive with defaulted parameters; no existing public signature changes except the new `EngineXPCSubmissionError` case (fix any newly non-exhaustive `switch` in `AuthenticatedEngineXPCSubmitterTests` — mechanical). `InstallerWorkflow`, `PinnedAsahiEngineExecutor`, `EngineContract`, importer, and all digest/approval logic untouched.

Commands (run from the package root):
- Format: `xcrun swift-format format --in-place --recursive Sources Tests Package.swift`
- Lint (strict): `xcrun swift-format lint --strict --recursive Sources Tests Package.swift`
- Tests: `swift test --jobs 10` and `swift test -c release --jobs 10` (both required; `OMARCHY_BUILD_JOBS` default 10 per `AGENTS.md`)
- No commits/pushes; no helper registration or privileged runs on this machine (owner-gated).

---

## 7. Risk register (top 5)

1. **Qualified-binary invalidation** (any trust-core/helper byte change makes the build an unqualified candidate needing owner re-qualification on the M1). Mitigation: confine binary-affecting changes to the nine files listed in Section 2 with additive, default-parameterized diffs; keep `PinnedAsahiEngineExecutor` byte-identical; stage the work so the entire trust-core diff lands as one small reviewable package (WP7–WP9) with debug+release suites green, and plan exactly one authoritative re-qualification at the end, not per iteration.
2. **XPC protocol skew app↔helper** (a previously registered helper daemon keeps running an older binary while a new app connects, or vice versa during development). Mitigation: `ClosedEngineXPCService.submit` is unchanged; progress is a separate, opportunistic exported interface; helper uses `remoteObjectProxyWithErrorHandler` and silently drops streaming; app degrades to indeterminate after a ~3 s no-chunk window; the new credential-error domain degrades to today's generic message on old apps.
3. **Journal tail races / partial lines / replays** (reading while root's engine appends; file created late; re-replay after reconnect duplicating state). Mitigation: forward only `\n`-terminated whole lines from a tracked offset; full replay-from-zero on attach with app-side buffer replacement keyed on a `sequence:1` restart; all validation failures degrade the *display* only (indeterminate), never the run; the authoritative post-run transcript validation path is untouched.
4. **Mock leaking into release** (preview scenarios or fixture handling reachable in a shipped build). Mitigation: entire preview environment file inside `#if DEBUG`; env-var read itself compiled out; nothing added to app resources; factory unit test asserts opposite behavior per configuration; release build + release test run in the WP11 checklist.
5. **Password-lifecycle regression in the new sheet** (SwiftUI state copies or session retaining credentials). Mitigation: password exists only as sheet-local `@State`, cleared on submit/cancel/disappear exactly mirroring `machineOwnerPassword = ""` at `OmarchyAppleInstallerApp.swift:755/842`; all session/environment APIs accept only `MachineOwnerAuthorization`; XPC raw-`Data` → stdin-pipe path unchanged; review checklist item forbids logging/printing display or context objects that could embed authorization, and `InstallerSessionTests` assert no credential storage on the session.

---

## 8. Sequencing (work packages, ~1–3 h each)

- **WP0 — Mockup approval checkpoint (gate).** Build phase starts only after the retro-terminal mockup for screens A–F is approved (mockup production itself out of scope here). Everything below assumes the approved layouts.
- **WP1 (2–3 h)** Package.swift: add `OmarchyInstallerUXCore` + test target. Skeleton: `InstallerSessionPhase`, display models, `InstallerEnvironment`, `CredentialInput`. Tests: transition table, credential matrix (tests 6 partial, 8).
- **WP2 (2–3 h)** `InstallerTheme.swift` + `RetroComponents.swift` ported from the prototype (`omarchy-mx-mac/.../InstallerView.swift` backdrop/rail/buttons/panels), app shell `InstallerRootView` with rail + phase switch stubs.
- **WP3 (1–2 h)** `PlainLanguage.swift`: move existing copy, add phase/event/checkpoint/outcome/error tables. Test 7.
- **WP4 (2 h)** `LiveInstallJournalModel` + fixture replay tests (test 5).
- **WP5 (3 h)** Screens A, Preparing, B, Unsupported wired to the session; `PreviewInstallerEnvironment` (`fresh-install`, `unsupported` scenarios); first M4 demo of A→B.
- **WP6 (2 h)** `CredentialSheet` (both variants), sheet state in `.awaitingInstall`/`.failed(retry)`, `credential-reject` scenario. Focus/wipe behavior verified in demo.
- **WP7 (2–3 h)** Trust core part 1: `EngineJournalProgress.swift`, `EngineJournalTail.swift`, tests 1.
- **WP8 (2–3 h)** Trust core part 2: helper server `progress:` param + endpoint proxy capture + listener interface; submitter `journalProgress` + exported object; `machineOwnerCredentialsRejected` bridge; coordinator threading. Tests 2, 3; fix any newly non-exhaustive switches.
- **WP9 (2 h)** Trust core part 3: download progress through stager/preparer/coordinator (test 4); PreparingScreen bound to real byte updates.
- **WP10 (2–3 h)** `LiveInstallerEnvironment` (move workspace/coordinator logic out of the old view), Screens D/E/F + Failure with live journal binding, retry flow end-to-end against the mock (`recovery-retry`, `degraded-journal` scenarios).
- **WP11 (2 h)** Delete the old view body and `InstallerChrome.swift`; full `xcrun swift-format` format + strict lint; `swift test --jobs 10` and `swift test -c release --jobs 10`; release-binary env-var check; scripted M4 demo walkthrough of all scenarios; produce the reviewable trust-core diff summary for the owner's re-qualification decision.

Total ≈ 22–28 h across 11 packages, with the trust-core diff isolated to WP7–WP9.

---

### Critical Files for Implementation

- /Users/maralc/dev/omarchy/omarchy-mx-mac-integration/apps/omarchy-apple-installer/Sources/OmarchyAppleInstaller/ClosedEngineHelperServer.swift
- /Users/maralc/dev/omarchy/omarchy-mx-mac-integration/apps/omarchy-apple-installer/Sources/OmarchyAppleInstaller/AuthenticatedEngineXPCSubmitter.swift
- /Users/maralc/dev/omarchy/omarchy-mx-mac-integration/apps/omarchy-apple-installer/Sources/OmarchyAppleInstallerApp/OmarchyAppleInstallerApp.swift
- /Users/maralc/dev/omarchy/omarchy-mx-mac-integration/apps/omarchy-apple-installer/Sources/OmarchyAppleInstaller/PinnedAsahiEngineExecutor.swift (read-only reference: journal path convention and fail-closed file validation to mirror in the tailer)
- /Users/maralc/dev/omarchy/omarchy-mx-mac-integration/apps/omarchy-apple-installer/Package.swift