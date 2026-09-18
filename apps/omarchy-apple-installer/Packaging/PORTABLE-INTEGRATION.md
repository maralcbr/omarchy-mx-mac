# Portable installer integration status

Local implementation for ticket #90, 12 September 2026. The main app now uses a
temporary embedded worker behind its existing Install and removal actions.
The owner confirmed end-to-end installation on M2 Max after the earlier failed
attempt. The current Release app was signed, notarized, stapled, and published
on 12 September 2026. Earlier authorization-only checks passed on macOS 26.6.2
(25G83). Remaining interruption/failure-path qualification is tracked separately.

## Implemented

- Native administrator authorization submits an internally named UUID job,
  checks app and helper signatures before and after authorization, pins the
  worker code hash at launch, and performs a version/session/root/PID handshake.
- The worker admits only the initiating signed app process, including its kernel
  start timestamp. It expires after five idle minutes; active work does not
  expire. Credential correction, removal confirmation and narrow Recovery retry
  retain the same bounded session. Retirement is bound to the caller's lease.
- A root-owned, never-replaced execution lock records the boot UUID and worker
  process group before request admission. Replacement workers remain blocked
  after leader death while children survive. Engine and removal launches retain
  that group, and cleanup waits for the entire group to drain. Unknown process
  observations keep admission and resources intact.
- Legacy daemon presence is checked before and after native authorization and
  again at worker admission. The app does not unload or delete an older helper.
- Existing import, exact-plan, asset verification, machine-owner credentials,
  unsupported-model rejection and Recovery checks remain in place.
- The app packager embeds the helper but no LaunchDaemon plist. It uses
  XcodeBuildMCP or explicitly supplied binaries from the tested source.
- No screens, navigation or controls were added. Error remedies now refer to the
  app instead of reinstalling a PKG. Native authorization cancellation returns
  to the existing Install action without consuming the execution attempt.

## Verified locally

115 focused tests passed in both Debug and Release on the final source. These
include existing installer-session journeys, native cancellation retry, temporary
lifetime and handshake checks, helper/executor validation, removal safety,
unsupported-host refusal and the original proof tests. A harmless real-process
case proves a surviving child blocks replacement after its leader exits and the
lock owner closes, then permits replacement after the child exits.

Strict Swift formatting and shell syntax checks pass. The signed private Debug
bundle passes strict codesign validation and reciprocal requirements. Its bundle
contains neither a PKG nor a LaunchDaemon plist. It was opened locally for review.
The expected ServiceManagement deprecation warnings remain accepted.

## Native check candidate

The immutable private candidate is under
`.build/portable-integration-native-20260912/Omarchy MX Mac Installer.app`.
`candidate.json` beside it records hashes. It is Developer ID signed and is not
notarized or published. The Debug-only `--validate-temporary-worker` argument
performs an authenticated root handshake and verifies exact job/process retirement;
it never submits an engine or removal request. Release builds reject this switch.

On the target, launch this private check through LaunchServices with private
stdout/stderr files so the native macOS authorization prompt belongs to the app:

```sh
open -W --stdout /private/tmp/omarchy-worker-check.jsonl \
  --stderr /private/tmp/omarchy-worker-check.stderr \
  '/path/to/Omarchy MX Mac Installer.app' --args --validate-temporary-worker
```

Use owner-only local files and an owner-only candidate directory. A pass requires
`authenticatedRootReply` and `jobAndProcessRetired`, plus independent verification
of no lingering job/process. Do not click Install during this check. Record the
exact signed candidate identity, macOS build and machine. The first native check passed on M2 Max (Mac14,6), macOS 26.6.2 (25G83).
Session `63DB8B3E-54EB-4201-A62A-9584A4DAB8AE` returned an authenticated root
reply from PID 1283. Independent checks confirmed job, PID and group absence.
The preceding legacy-helper refusal returned `legacyHelperActive` before native
authorization. The idle legacy registration was backed up under the root-owned
`/var/tmp/omarchy-legacy-helper-backup-20260912` on M2 and unloaded; its app and
installation journals were preserved. The original plist SHA-256 is
`12acfc56bcda7bd6cedaf0157a912e941b66665371571ec7c93406e087458352`.
The clean-relaunch check also passed: session
`C2009071-4DCE-47A6-AFDF-9BF79FCF406F`, PID 1434. Independent job/PID/group
absence was verified after both runs. The existing-installation message came from
the normal read-only app inspection; neither check submitted disk work. Local raw evidence
is in `.build/portable-integration-native-20260912/m2-evidence/`.

## Remaining work

1. Run this integrated app's native authorization/retirement check on macOS 26,
   including cancellation, busy/legacy refusal and startup failure handling.
2. Finish interrupted-attempt recognition and safe stopping/start-over behavior
   (#91–94). Parent exit currently defers retirement until active work finishes;
   stopping at an operation boundary is not implemented by the lifetime policy.
3. Build and qualify an exact release candidate on physical machines (#95–96),
   then publish the signed/notarized ZIP and submit the central Cask (#97–98).

Qualification targets macOS 26 at the owner's request. macOS 15 remains
unqualified; the deployment minimum has not changed. Tart remains stopped.
Process-group exclusion relies on the pinned engine and its tools retaining the
group; inspected engine Python does so. Physical qualification remains necessary
for the Apple disk and boot utilities and for the actual installation workflow.

### Persistent install diagnostics (2026-09-12)

The app now saves JSONL lifecycle events in
`~/Library/Logs/Omarchy MX Mac Installer/install-<UUID>.jsonl`.
The root worker saves its events in
`/var/db/com.omarchy.mx.installer/diagnostics/install-<UUID>.jsonl`.
Files use mode 0600 under private directories; each event is synchronized to
storage immediately. These locations survive reboot and temporary app cleanup.
Only static event names, timestamps, process/user IDs, and numeric status codes
are accepted. Credentials, usernames, arguments, environment values, raw engine
output, and error descriptions are excluded. Existing root engine execution
journals remain separate and unchanged. Correlate app and worker events by time
and the engine PID in `engine_spawned`.

The September 12 native attempt is not an installation pass: credentials were
accepted and helper import completed, but the disk remained macOS-only and no
new engine execution journal was present after reboot. The user reported a rapid
transition to the shutdown screen. The new diagnostics are instrumentation for
reproducing that failure, not evidence that its cause is fixed. RC is the default
for the next candidate and next physical attempt.

### Owner acceptance update (2026-09-12)

After the failed attempt above, the owner confirmed completing installation end
to end on the M2 Max. This supersedes the current blocking-status description of
the earlier attempt; its historical evidence remains for diagnosis. The owner
has authorized publishing the current app and updating the project home. This
is owner-reported hardware acceptance, not a newly captured agent boot trace.
