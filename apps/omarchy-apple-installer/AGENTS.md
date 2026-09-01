# Apple installer development

## Goal autonomy

During an active goal, choose and implement the best reversible local source,
test, or documentation option without pausing for routine choices. Stop only
when the next step needs owner authority, credentials, physical-device access,
or would cross a safety boundary below.

## Language conventions

- Format Python with conventional four-space indentation and validate it with
  `py_compile` plus the focused engine tests.
- Format Swift with Xcode's bundled `swift-format`, require strict lint for the
  package, and validate macOS builds and tests through XcodeBuildMCP.
- Keep shell scripts compatible with the root repository rules. Build workers
  come from `OMARCHY_BUILD_JOBS`, whose default is 10.
- For exact `[[ == ]]` or `[[ != ]]` string comparisons, quote a variable on
  the right-hand side so Bash treats metacharacters as literal text.

## Completion evidence

For installer changes, verify the focused Python tests, Swift tests in debug
and release, packaging structure, code-signing requirements, and unsupported
host rejection as applicable. A source build is not physical installation
proof.

## Iteration ownership and lifecycle

- One Codex task owns an installer iteration. Use bounded subagents for
  independent read-only analysis, but do not start a peer task that runs the
  same build, qualification, or physical workflow.
- Preview the change-impact plan before Docker, image restoration,
  compression, signing, or a full exact-upstream suite. Stop before expensive
  work if the observed invalidation frontier is broader than the declared
  change class.
- Run focused tests while editing, one component closure after the vertical
  slice is green, and one authoritative qualification for the immutable
  candidate. Do not restart a passed full suite for the same source and runner
  identities.
- Keep exactly one review app instance. Never use `open -n`, never launch the
  raw SwiftPM executable concurrently with the packaged app, and terminate
  only the exact automation-owned PID after an automated review.
- A concurrent request for an identical content-addressed run must attach to
  or resume its run journal; it must not start another build or app instance.

## Authorization boundary

Local source edits, pure tests, read-only inspection, and disposable artifacts
are reversible. Obtain the owner's explicit authorization immediately before
helper registration, privileged execution, disk or boot-policy mutation,
signing or notarization with production credentials, publication, deployment,
or physical-device work. Keep `apple,j614s` fail-closed until official support
and physical qualification both exist.
