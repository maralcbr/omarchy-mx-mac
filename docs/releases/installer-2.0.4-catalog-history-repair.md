# M1 private catalog history repair — 2026-09-07

Project: `maralcbr/omarchy-mx-mac`, `installer-audit-worktree`.

The installed 2.0.4 app rejected public RC during planning with
`rollback(stored: 1788759927, candidate: 1788738081)`.
The package installation itself had succeeded; Omarchy installation had not started.

## Proven cause

The M1 public RC receipt's digest was
`sha256:5a342522e476f2fd7fcddca15c87fd756deaad3601006ef4964b80be7685e6a2`.
It exactly matched the sealed catalog in the earlier private speed-test build
(`dist/m1-speed-20260907/removal-ssd-fix-app`). Older private builds persisted
this catalog into the same channel receipt used by production.

A fresh public RC response had sequence 1788738081 and payload digest
`sha256:74a4bbd806d3916d31df75c18c3076d4531472523eea298689223486f8b007e3`.
This was independent private/public history contamination, not a signature
failure, shared stable/RC history, disk failure, or stale response.

## Device repair and verification

Over the pinned Thunderbolt alias, verified mina / MacBookPro18,3 and bridge0.
Required an exact receipt digest and sequence match before mutation.
Preserved the original receipt under:
`~/Library/Application Support/com.omarchy.mx.installer/state/private-catalog-repair-20260907T134114Z/accepted-catalog-rc.json`.
Moved the matching private receipt to `accepted-sealed-catalog-rc.json`.
No unknown receipt was discarded and no partition, helper, or application binary changed.

Used Check again (host inspection), then Continue (file preparation and plan
review). The app verified and downloaded public RC assets and reached the
allocation review screen with the approval checkbox unchecked and Install
disabled. The new public receipt records the expected 1788738081 sequence and
74a4bbd8 digest above. No OS installation was authorized or started. Downloads
are now cached as a result of this verification.

Screenshot: workspace `review-images/m1-error-fixed.png`, SHA-256
`eea68531f9ea88e41a48d6d6c0e4209a2d44207f17540ae670497d2bfc8157a5`.

## Preventive source change

Bundled catalogs now use separate receipt filenames. Public filenames and
legacy stable migration remain compatible. Both timelines still reject
rollback and same-sequence payload substitution. Existing unknown receipts
are not automatically migrated or cleared.

Two added tests cover private/public isolation, rollback in both histories,
and private stable history never reading or retiring public legacy history.
The pre-fix run failed on the missing isolation API; focused tests passed after
the fix. The trust/configuration/coordinator test selection passed 253 tests
in debug and 253 in release. Strict package Swift formatting and git diff
checks passed. Read-only independent review found no actionable issues.
The debug app was rebuilt, packaged with an ad-hoc signature, launched in
simulation, and its simulation-only welcome screen verified via accessibility.

The device repair is live. The preventive source change is local and has not
been published as a new release; M1 still runs signed 2.0.4.
