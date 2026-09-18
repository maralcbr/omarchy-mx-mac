# Installer speed regression after the Aurora merge

Status: corrected RC/Aurora catalogs signed, published and verified on 2026-09-08
(Australia/Brisbane). A fresh physical timing run remains pending. This is `maralcbr/omarchy-mx-mac` in
`installer-audit-worktree`, not the historical fork.

## Cause

The source merge retained the fast Python implementation, but the public 2.0.4
app omitted the private speed-test catalog and resumed fetching public channel
catalogs. At diagnosis, both public RC and RC (Aurora) selected execution engine `.14`.
The private build that the owner reported taking about two minutes selected
`.15`. Rebuilding Swift alone cannot fix this release-selection regression.

Fresh RC/Aurora envelopes were downloaded and their Ed25519 signatures verified
against the app-owned trust root. RC sequence: 1788738081. Aurora: 1788769678.
Both select `.14`, SHA-256
`9e9277384b6c9e8b269cc79b1b24df7bfcdcbb898a596a677b74d1d18050aebe`.

Known fast `.15`: 17,840,637 bytes, SHA-256
`8672182b3a60eecab83a7a1f014d257047f77d065432b3da9ea29509a57eb28f`.
All eight current overlay Python files match that archive byte-for-byte.
The app's bundled `.14` is used for read-only inspection; it is a separate
lifecycle and is deliberately not repinned by this correction.

The post-merge staging reuse guard compares against the derived release
subdirectory correctly. The public payloads differ from the private test OS
build, but their digest-verified metadata still declares a 2 GiB boot image
and a 32 GiB root image. The deterministic regression below is present in the
execution engine independently of network conditions or OS image contents.

## Reproduction

`Engine/verify-execution-performance.py` loads the actual archived Python
adapter, checks its artifact SHA-256, and runs tiny images against in-memory
partition substitutes. It additionally executes the archived upstream
`OSInstaller.install` method with fake I/O to verify raw-image hook dispatch.
It never uses a physical disk or privileged helper.

| Measured work, 4 KiB boot + 4 KiB root fixture | Public .14 | Fast .15 |
| --- | ---: | ---: |
| Image bytes expanded during preflight | 8192 | 0 |
| Root bytes reread during normal completion | 4096 | 0 |
| Root bytes written | 4096 | 4096 |
| Boot bytes reread | 4096 | 4096 |
| Upstream dispatch through raw-image hook | No | Yes |
| Budget result | Fail | Pass |

With the shipped 34 GiB of images, `.14` expands roughly 102 GiB across
preflight, installation and source/target verification, then reads back 34 GiB.
`.15` expands the images once during writing and reads back boot data (2 GiB).
It retains signed payload verification, streaming CRC, exact write lengths,
durability requests and exhaustive verification on Recovery retry. These are
work reductions, not a newly measured two-minute installation guarantee.

Reproduce from the worktree:

```bash
python3 apps/omarchy-apple-installer/Engine/verify-execution-performance.py \
  --archive dist/m1-speed-20260907/engine-final-a/installer-v0.9.0-omarchy.15.tar.gz \
  --sha256 8672182b3a60eecab83a7a1f014d257047f77d065432b3da9ea29509a57eb28f
```

The matching `.14` archive from `dist/installer-2.0.4` fails that same work
budget. Outputs are retained in `dist/merge-speed-review/*-engine-work.json`.

## Correction prepared

- Both release-input templates now select `.15`.
- Catalog generation and channel promotion verify the complete execution pin
  (version, digest, filename and size) against `Engine/source-lock.json`.
  This check is independent of the app's inspection bundle.
- `os-promote --catalog-name catalog-engine.15.signed.json` can promote a new
  immutable catalog revision while retaining the existing OS asset set.
  Filenames are constrained, signatures and sequence checks still apply,
  and every artifact must remain under the selected immutable release prefix.
- No automatic rollback-state clearing or source-lock bypass was added.
  `OMARCHY_ENGINE_SOURCE_LOCK` selects a separately qualified lock for isolated
  release tooling/tests; it does not change the application trust root.

Two exact unsigned candidates are ready under `dist/merge-speed-review`:

| Channel | Candidate SHA-256 | New sequence |
| --- | --- | ---: |
| RC | e61bfd929ec5db52617d1dd376348111aacd16610c496edfd40db562a7a84464 | 1788790581 |
| RC (Aurora) | ba5d17c4d74fefd0664d04eb4314515962c6082378f13cc81addbfc6f61b2b0c | 1788790581 |

Files: `rc/catalog-engine.15.json` and `aurora/catalog-engine.15.json`.
All 22 model records preserve their OS payloads, metadata, support state,
revisions and delivery URLs. Only execution-engine pins change. The top-level
sequence/time and installer requirements also change: minimum/latest 2.0.4,
with the published immutable 2.0.4 package URL. Requiring the merged app keeps
clients on the helper/UI version tested with the fast engine.

## Approved publication scope

Sign the two candidate JSON payloads with the existing catalog key and verify
them with the existing app trust root. Upload `.15` and the new immutable
`catalog-engine.15.signed.json` envelope under each existing release prefix:

- `releases/os-v4.0.2-mac.1.20260907/`
- `releases/os-v4.0.2-mac.1.20260907-aurora/`

Check existing object identity before upload; never overwrite an immutable
object. Verify public bytes/digests before promotion, reread live catalogs for
unexpected changes, and promote each matching tag with `--catalog-name
catalog-engine.15.signed.json --no-prune`. This changes only RC and RC (Aurora)
channel catalogs/pointers. Stable, OS images and the installed app binary stay
unchanged. Keep the prior signed catalogs as evidence; any later correction
must still use a higher sequence.

A new app package or OS image build is unnecessary to restore performance:
installed 2.0.4 will fetch the corrected execution catalog on its next plan.
The previous catalog-history prevention patch remains separate local work.

## Validation and limits

- 102 engine tests passed.
- 22 catalog-generation/execution-pin tests passed.
- 26 channel-publication checks passed, including stale engine refusal before
  any write and promotion of a separate immutable catalog revision.
- The archive work-budget probe fails on `.14` and passes on `.15`.
- Python compilation, Bash syntax and git diff checks passed.
- Debug application rebuilt through XcodeBuildMCP, packaged with an ad-hoc
  review signature, opened in simulation, and its simulation-only state read
  back. The automation-owned simulator was then closed.
- Independent read-only review confirmed the pin/catalog changes. Its concern
  about bypassing the archived upstream write hook was addressed by the
  additional archived-method dispatch check.

M1 Thunderbolt currently resolves through `en0`, not required `bridge0`.
The fail-closed preflight stopped before connecting; no Wi-Fi fallback,
partition change or install was attempted. Owner was asked to reconnect
Thunderbolt and boot macOS. A comparable physical run must separate download,
APFS resize, authenticated stage-one execution and human Recovery time, and
verify the `.15` engine identity in its journal before claiming restored timing.

## Publication receipt — completed

Owner approved signing and publishing the corrected catalogs. Both were
signed using the existing catalog Keychain identity and verified against the
app-owned Ed25519 trust root. Four immutable objects were created with
conditional PUT (`If-None-Match: *`), then downloaded from their public URLs
and checked for exact size and SHA-256 before channel promotion.

| Channel | Live sequence | Signed envelope SHA-256 |
| --- | ---: | --- |
| RC | 1788790581 | 82ab0f55d43321fe1d12c9174d4c58de62e6c94658f7681213fab6302e3318ff |
| RC (Aurora) | 1788790581 | a895bb1fbc1150f1044ade6e64497bf6ceb94f30a78d58ec3445b0a23541f428 |

Normal public GETs (without a special cache-busting URL or request header)
matched both exact signed envelopes after promotion. All 22 enabled records
in each feed select `.15` with the qualified digest. Both descriptive channel
pointers were verified. No pruning, OS-image replacement, stable promotion,
app replacement, or M1 installation was performed.

A publication-tool path quoting error was found before any remote write:
the default Swift signing command split the project path at spaces. The
signature itself verified when invoked directly. The command now uses an
argument array and an added regression check passed with the other 25
publication checks. The older AWS CLI lacks conditional PUT input support;
the upload used curl's SigV4 support with credentials passed through stdin,
not command-line arguments or a credential file.

Detailed receipts and logs: `dist/merge-speed-review/publication-receipt.json`,
`upload-approved.log`, `promote-rc.log`, and `promote-aurora.log`.
The source-level release guards remain in the local worktree; this publication
did not push or merge Git branches.

Manual retest: quit and reopen installer 2.0.4 before preparing a new plan,
so an already prepared `.14` plan is not reused. The app fetches the corrected
catalog automatically. Do not claim a restored two-minute wall-clock result
until a comparable physical installation has been measured.

## M1 evidence collected after Thunderbolt reconnection

On 2026-09-08 the owner connected the M1 in macOS. The route, pinned SSH
configuration and peer identity passed (`bridge0`, mina, MacBookPro18,3).
Installed app: 2.0.4; macOS: 26.0.1. No installer process was running. Existing
Omarchy partitions remain on disk. No disk, cache, helper or app mutation was
performed. A developer-tools prompt caused by probing the unavailable system
Python was cancelled; logs were instead copied and parsed on the controller.

The latest execution journal, `9d5ea72b...`, conclusively pins `.14` with digest
`9e927738...`. The three preceding timed private runs pin `.15` with digest
`8672182b...`, exactly the artifact now published.

For comparable totals, start is the public OSLog app_handoff completion
 timestamp minus its recorded duration; finish is the Recovery checkpoint
 evidence file's modification timestamp. This excludes downloads before
 authorization and human Recovery interaction after the checkpoint. File
 timestamps are wall-clock evidence, not a new monotonic end-to-end timer.

| Run (UTC on 2026-09-07) | Engine | App handoff through Recovery checkpoint |
| --- | --- | ---: |
| 06:40:25 → 06:42:50 | .15 | 144.681 s (2m25s) |
| 07:29:52 → 07:32:17 | .15 | 145.342 s (2m25s) |
| 10:04:25 → 10:07:41 | .15 | 196.158 s (3m16s) |
| 13:47:29 → 13:53:14 | .14 | 344.339 s (5m44s) |

The third `.15` run includes 48.689 seconds in target preparation, compared
with roughly 3.5 seconds in the other two. Nested engine spans are not added
again to their enclosing stage. Pure engine-phase totals were 133.494,
135.506 and 186.027 seconds respectively.

A normal catalog GET performed on the M1 itself matched the exact published
`.15` RC envelope. Its saved accepted-catalog receipt remains the prior RC
receipt because the app was left closed and no new plan was prepared.
This verifies reachability of the fix, not a new installation measurement.

Retained evidence: `dist/merge-speed-review/m1-timing/` contains the original
journal archive, filtered performance OSLog output, `timing-summary.json`,
`comparable-timings.json`, and `rc-from-m1.json`.
