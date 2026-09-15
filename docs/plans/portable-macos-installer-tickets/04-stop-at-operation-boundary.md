# Stop safely when the installer quits or loses its UI

## Parent

[Portable Omarchy Mac installer specification](../portable-macos-installer-spec.md)

## What to build

Quitting or losing the installer UI requests a bounded stop. The worker lets an in-flight operation reach its safe boundary where possible, starts no further mutation after stop is acknowledged, retires when safe, and leaves an attempt the next launch can inspect.

## Acceptance criteria

- [ ] A normal quit is propagated from the application session through the worker to the engine; the UI explains stopping or an unfinished outcome honestly.
- [ ] After acknowledging stop, no subsequent mutation starts. An in-flight APFS operation is not forcibly killed under a claim of safe instant rollback.
- [ ] UI connection loss, worker failure and system interruption preserve available attempt evidence and do not intentionally finish the entire installation in the background.
- [ ] The machine-wide guard remains effective while any earlier mutator is alive; timeout does not release it prematurely.
- [ ] Completed or safely stopped workers and their temporary job retire; diagnostics and attempt evidence needed on reopening remain available.
- [ ] Exercise quit and lost-connection behavior during startup, between operations and during a controlled in-flight operation using the existing session and engine seams.
- [ ] Reopening reports the retained attempt correctly; successful completion and the existing Recovery-only retry still work.
- [ ] Run focused checks, rebuild and inspect stopping, interrupted and failed UI states. Use harmless or disposable effects until the physical qualification stage.

## Blocked by

- [03: Recognize unfinished installations when the app reopens](03-recognize-unfinished-attempt.md)
