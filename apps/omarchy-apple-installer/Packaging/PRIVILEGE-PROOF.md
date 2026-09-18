# Temporary privilege qualification

This implements the local capability harness for [ticket #89](https://github.com/maralcbr/omarchy-mx-mac/issues/89). It does not replace the shipping installer or qualify disk installation. The proof app and worker depend only on the lightweight privilege core, with no installation/removal RPCs or disk engine dependency.

This is developer qualification tooling only. The owner's implementation constraint is to preserve the existing installer experience with no new screens. Do not add this harness to the shipping app, ZIP, Cask or user installation flow. Temporary privilege handling belongs behind the existing Install action; interruption and restart behavior must use the existing installer flow.

## Local review

Build and test the package through XcodeBuildMCP. Assemble the resulting binaries with `build-privilege-proof.sh BUILT_PRODUCTS_DIRECTORY NEW_OUTPUT_DIRECTORY`. The default uses local ad hoc signing and sets administrator authorization to disabled. It is safe to open and click either check button in this review build: both stop before authorization or helper submission.

The shared signing-requirement syntax validator retains the shipping installer's existing behavior. Proof signatures additionally require fixed proof-only identifiers, an Apple signing anchor and the same team for both executables. Each run gets a distinct temporary service label. The worker reports only a nonce, protocol version, service label, effective UID and PID; it writes no attempt journal and never imports or starts the disk engine.

## Qualification candidate

Obtain owner authority for production signing, notarization and the named harmless privileged runs before performing them. Invoke the packaging script with the approved signing identity in `OMARCHY_PROOF_SIGNING_IDENTITY` and `OMARCHY_PROOF_SIGNING_AUTHORIZED=yes`. Use Developer ID for the downloadable candidate. The script is packaging only: it does not notarize, upload, install or run the app.

Notarize a ZIP of the signed app using the approved notary profile, staple the app and recreate the final ZIP. Record source commit and diff identity, executable hashes, final archive SHA-256, signing identifiers/team, notarization result and exact macOS version. Download that ZIP through a browser on the qualified machine and keep quarantine intact. Do not substitute a build-directory launch for this evidence.

Run the following on the supported macOS floor and current supported macOS release:

1. Cancel the native authorization prompt. Expect no submitted worker and an explicit cancelled outcome.
2. Run the authorization/reply check. Expect a nonce-bound authenticated root reply, then observation that both its exact job and its worker process disappeared.
3. Run the unused-worker check. The app sends no XPC request. Expect positive liveness observations spanning at least 11 seconds, followed by process and job absence under the independent 12-second lifetime limit. The one-second allowance covers launch and polling latency. Early exit or insufficient observations fail qualification; delayed observation of an already dead worker cannot pass.
4. Quit the GUI while a worker is idle. Independently observe its bounded exit and check that its UUID job is absent. If a registration remains, record that failure rather than inferring that LaunchOnlyOnce guarantees removal.
5. Verify that a wrong client identifier/team cannot receive a reply, a changed helper fails signature validation, and a deliberately mismatched SpawnConstraint prevents the worker from executing. Record the AMFI enforcement evidence. The latter is required to establish that legacy SMJobSubmit honors the constraint before using this launch path with the disk engine.
6. Exercise startup and connection failure, and verify that the app removes only its own submitted UUID job and never reports a pass without proven retirement. A worker that exits before its PID can be observed produces an unverified result, not a false pass.
7. Verify no persistent installer plist, privileged-helper copy or login item was added, and that no proof service returns after reboot. Do not remove unrelated or shipping installer services to make the result pass.

Record all passed, failed and unavailable evidence separately. The real capability gate remains incomplete until these checks are run on the signed downloadable artifact. No physical disk mutation is part of this proof.

## Lifetime and trust limits

### Automated developer runner

`OmarchyPrivilegeProofRunner` is a separate developer executable linking only the
privilege core. It is excluded from the shipping app and ZIP. Build it through
XcodeBuildMCP and package it with `build-privilege-proof-runner.sh`, under the same
named-signing authorization as the qualification app. The runner uses the proof
client identifier, never the shipping installer identifier.

Run `OmarchyPrivilegeProofRunner check /absolute/path/to/candidate.app` for a
nonprivileged preflight. Run `OmarchyPrivilegeProofRunner run /absolute/path/to/candidate.app`
as the logged-in non-root user for a batch containing authenticated reply and
idle expiry. JSON lines on stdout include each outcome and its UUID evidence;
failure returns a nonzero exit code. Native administrator authorization may
still require the owner. No password is accepted by the runner or stored.

The runner pins the September 10 qualification candidate's app, worker and
Info.plist hashes. The backend checks these both before and after authorization;
the runner also adds its fixed worker CDHash to the spawn constraint. The original
GUI candidate's descriptor and binary remain separate qualification evidence.
One authorization reference is retained only across the batch, freed on success
or failure, and never serialized. A 120-second process deadline bounds an
unattended run; each submitted worker independently expires after 12 seconds.
The original GUI still releases authorization after every completed run.

Direct execution in an SSH login returns `errAuthorizationInteractionNotAllowed`.
Launch the packaged `Omarchy Proof Automation.app` through Launch Services in
that user's desktop session, with `open -W --stdout RESULT.jsonl --stderr STDERR`
and `--args run CANDIDATE.app`. The app has no windows or installer UI. Keep the
runner in an owner-only temporary directory: the M1's privacy controls denied
`authd` access to the standalone executable when it was in Downloads. Do not
change privacy settings to solve this. Copy the pinned candidate to that same
test directory and retain the original downloaded app and its quarantine. This
is backend automation evidence; the original browser-download and translocated
GUI launch remain separately recorded.

A native authorization prompt may still require one owner action. The runner
then performs both checks using its one authorization reference and exits. Read
the JSON `complete` event and both passing results; `open -W` exiting zero alone
does not mean the tests passed. Cancellation and the 120-second deadline are
failures, never automated approval. Private developer signing does not constitute
notarization or public distribution qualification for this runner.

The `negative` command runs a normal root control, missing-service failure,
wrong-client and wrong-worker-requirement checks against a live worker, and a
fixed mismatched launch constraint. The separately signed negative peer is
bundled only with this developer runner. Correct probes before and after each
rejection must reach the same worker PID.

The `startup` command runs a normal root control followed by the same pinned
worker with a fixed extra argument. Its expected failure is `EX_USAGE` before
XPC setup. Both negative commands emit `pending-system-evidence`, not a passing
batch: correlate the exact UUID/PID with system logs and verify job/process
absence. For the constraint, require enforcing AMFI `c[5]p[1]m[1]e[0]`; for
startup, require an explicit failure and verified retirement of an observed live
job/PID. The numeric exit status is diagnostic, not a separate acceptance gate.
A missing reply alone is inconclusive.
Start a bounded live launchd log stream before launching when persisted logs
omit normal exit statuses. Preserve each attempt in separate output files.

Cancellation, client termination and reboot absence remain distinct evidence,
and must not be inferred from a successful batch.

On the M1 running macOS 26.6.2 (25G83), the September 11 negative batch proved
both XPC rejections, enforcing launch-constraint rejection and exact-job cleanup.
Startup-failure handling and retirement also passed; its numeric exit status
was not captured.
The macOS 15.0 floor remains unqualified. These results do not qualify shipping
engine integration or physical installation.

The worker independently exits after 12 seconds; the normal check requests an earlier exit after its reply. The app retains authorization only for cleanup of the exact UUID job it submitted. It first observes that job and PID, then requires job absence and ESRCH from a process-existence probe. EPERM counts as a live root process. A reused PID conservatively fails retirement rather than being killed. Unknown status or cleanup failure is visible and cannot become a passing result.

If the job and observed process have already retired, cleanup records their verified absence. Otherwise every failed SMJobRemove call preserves its error domain, code and description, even if the worker expires concurrently. A malformed job dictionary is an unknown result, not absence.

The launcher validates signatures again after the human authorization delay. A SpawnConstraint pins the executable's team and signing identifier before launch, addressing executable replacement in a user-owned download location. Its enforcement through SMJobSubmit and access under Downloads/translocation must be proven with the actual signed artifact; static checks and mutual XPC authentication alone do not establish that prelaunch guarantee.

The expected Service Management deprecation warnings are confined to the proof adapter. No assertion here broadens supported installation models or changes the shipping installation engine.

## Vendor references

- [Apple DTS privilege guidance](https://developer.apple.com/forums/thread/708765)
- [SMJobSubmit](https://developer.apple.com/documentation/servicemanagement/smjobsubmit(_:_:_:_:))
- [Launch constraints](https://developer.apple.com/documentation/security/applying-launch-environment-and-library-constraints)
- [Constraint facts](https://developer.apple.com/documentation/security/defining-launch-environment-and-library-constraints)
- [Notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
