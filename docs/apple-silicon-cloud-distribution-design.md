# Design: Cloud Distribution Seam — Multi-Part Payload + Progress

(Authoritative design produced 2026-08-31; implement faithfully.)

## 1. Multi-part payload

### 1.1 Catalog schema (schemaVersion stays 2/3; additive, optional)
`payloadArtifact` gains optional `parts` array; whole-file digest+sizeBytes remain authoritative; when parts present the whole sourceURL is informational, never fetched. Part record: {sourceURL, fileName, sizeBytes, sha256 ("sha256:<64hex>")}.
Validation (fail-closed): parts allowed ONLY on payloadArtifact (elsewhere -> SupportCatalogError.invalidField); count 2...16; each part same rules as PinnedInstallerArtifact (https, non-empty host, no user/password/fragment, safe fileName <=255B, valid prefixed digest, sizeBytes>0); part fileNames pairwise unique AND != whole fileName; overflow-checked sum of part sizes == whole sizeBytes, rejected at parse time.

### 1.2 Swift types — Sources/OmarchyAppleInstaller/VerifiedArtifactStager.swift
public struct PinnedArtifactPart: Equatable, Sendable { sourceURL, fileName, expectedDigest, expectedSizeBytes; throwing init with same guards }
PinnedInstallerArtifact: add `public let parts: [PinnedArtifactPart]` with `parts: [PinnedArtifactPart] = []` default in init (source-compatible). Init guards when non-empty: (2...16).contains(count), unique names, none == fileName, overflow-safe sum == expectedSizeBytes.
New ArtifactStageError cases: invalidPartCount(Int), invalidPartFileName(String), partSizeSumMismatch(expected: UInt64, actual: UInt64).
New ArtifactMaterialization case: assembledFromParts.

### 1.3 Stager algorithm
stage(_:in:progress:) branches after destination-exists check:
1. Whole file already staged -> verify -> reuse (unchanged); wrong bytes -> destinationConflict. On successful reuse best-effort delete leftover part files.
2. parts.isEmpty -> existing single-download path byte-for-byte (engine/metadata/repair stay here).
3. Parts present — sequential:
   - Factor current download->promote(.pending-<uuid>)->verify->rename body into: private func stageSingle(url:fileName:expectedDigest:expectedSizeBytes:in:onBytes:) async throws -> (fileURL, materialization, reused)
   - Each part staged at stagingDirectory/<part.fileName>. Existing valid part -> skip download; existing wrong bytes -> destinationConflict(part.fileName) hard fail.
   - Assembly: stream-concat all parts into stagingDirectory/.pending-<uuid> in 1 MiB chunks feeding ONE running SHA256 + size counter (no re-read, no double memory): private func assemble(parts:into:expectedDigest:expectedSizeBytes:) throws. Mismatch -> digestMismatch/sizeMismatch, delete pending (defer), KEEP verified parts.
   - Promotion: moveItem(pending -> destination) with existing lost-race fallback. Pending lives inside stagingDirectory -> always same-volume, no EXDEV. (EXDEV remains only inside per-part promote, already handled by AtomicArtifactFilePromoter copy fallback.)
   - Cleanup: on success try? delete all part files; result materialization=.assembledFromParts, reusedExistingFile=false.
Disk peak ~2x payload during assembly (documented). Parts give coarse resume for free.

## 2. Progress reporting

### 2.1 Downloader — same file
typealias ArtifactByteProgressHandler = @Sendable (_ bytesReceived: UInt64) -> Void
protocol ArtifactDownloading: Sendable { func download(from:expectedSizeBytes:onBytes:) async throws -> URL }
final class ProgressReportingArtifactDownloader: NSObject, ArtifactDownloading, URLSessionDownloadDelegate, @unchecked Sendable
- Ephemeral URLSession(configuration:.ephemeral, delegate:, delegateQueue:nil) per call; withCheckedThrowingContinuation; invalidate on completion.
- didWriteData: report totalBytesWritten throttled (>=250ms or >=16MiB delta); ENFORCE size cap: totalBytesWritten > expectedSizeBytes -> cancel task, fail sizeMismatch.
- didFinishDownloadingTo: synchronously move system temp file to downloader-owned temp path BEFORE resuming continuation (URLSession pitfall).
- Non-2xx -> unexpectedHTTPStatus. No resume in v1 (future: resumeData/Range per part).

### 2.2 Progress model + threading
public struct ArtifactStagingProgress: Equatable, Sendable { enum Phase { downloading, assembling, verified }; role: String; fileName: String; phase; partIndex: Int?; partCount: Int?; bytesCompleted: UInt64; totalBytes: UInt64 }
public typealias ArtifactStagingProgressHandler = @Sendable (ArtifactStagingProgress) -> Void
Signature changes, all with `= nil` defaults so existing callers/tests compile:
- VerifiedArtifactStager.stage(_:in:progress:)
- InstallerAssetPreparer.prepare(_:progress:)  (passes handler to its four concurrent async-let stage calls; events disambiguated by role)
- InstallerReleaseAssetCoordinator.prepare(_:progress:) and prepareRelease(_:progress:)
For parts: bytesCompleted = sum(finished/reused part sizes) + current part onBytes value (monotonic per role; reused parts appear as jumps). Final .verified event per role.
App consumption: @State stagingProgress: [String: ArtifactStagingProgress] keyed by role, main-actor hop in the closure.

## 3. Generator — scripts/make-unsigned-catalog.py (durable home, from v7 candidate copy)
argparse: --base-url (no trailing slash; GitHub release download base), --validity-days default 90, --output, --assets-dir. Parts emission: discover "<PAYLOAD_NAME>.partNN" beside payload (sorted zero-padded); >=2 -> emit parts array (sourceURL=f"{base}/{name}") with SELF-CHECK: sum sizes == whole size AND sha256 over parts concatenated == whole digest, abort otherwise; exactly 1 part file -> error; 0 -> single-URL unchanged. sequence=int(issued.timestamp()) unchanged. Splitting happens in publisher, not here.

## 4. Publisher — scripts/publish-m1-release (new bash, house style: #!/bin/bash, 2-space, [[ ]]/(( )))
Subcommand `prepare --payload <zip> --engine <tar.gz> --metadata <json> [--repair-manifest <f>] --tag <TAG> --repo <owner/repo> --out-dir dist/m1-release/<TAG>`:
1 validate inputs; 2 payload > 1992294400 bytes -> split -b 1900m then RENAME to <name>.part00/.part01... (avoids BSD/GNU suffix differences); <=16 parts; 3 shasum -a 256 all assets -> SHA256SUMS; 4 emit release-urls.env (BASE_URL=https://github.com/<repo>/releases/download/<tag> + asset names); 5 idempotent: re-run compares bytes, differing -> hard error without --force.
Subcommand `publish --dir <out-dir> --app <app zip> --tag <TAG> --repo <repo> --notes-file <md>`:
1 preconditions: gh active login == maralcbr (gh api user --jq .login), tag pushed (git ls-remote --exact-match origin refs/tags/$tag), interactive owner confirmation; 2 release absent -> gh release create "$tag" --verify-tag --title ... --notes-file, then gh release upload per asset (parts, engine, metadata, optional repair manifest, app zip, SHA256SUMS); 3 release exists -> per-asset compare via gh api (size + digest where populated): match->skip, missing->upload, mismatch->HARD ERROR never --clobber; 4 print final URLs and verify == release-urls.env.
Pipeline order: prepare -> make-unsigned-catalog (URLs deterministic pre-release) -> sign catalog -> build+sign app with sealed catalog -> notarize -> publish. Tag frozen once catalog signed.

## 5. Tests — Tests/OmarchyAppleInstallerTrustCoreTests/VerifiedArtifactStagerTests.swift
RoutedFixtureDownloader actor (responses: [URL: Data], downloadCount, requestedURLs; invokes onBytes).
Descriptor: 1 part rejected invalidPartCount(1); 17 rejected; 2 and 16 accepted; dup name + name==whole -> invalidPartFileName; unsafe names rejected; sum mismatch -> partSizeSumMismatch pre-network.
Stager: happy 2-part (bytes==concat, .assembledFromParts, downloadCount==2, only whole file remains, progress monotonic ending .verified at total); part digest mismatch (part00 kept, no destination, no pendings); whole-digest mismatch w/ valid parts (parts kept); whole reuse (2nd call reused, count unchanged); partial part reuse (count==1); conflicting existing part (destinationConflict, zero downloads); single-URL regression (existing tests unchanged); size-cap (overfeed -> sizeMismatch, nothing staged); single-file progress events.
Catalog tests: v2 payloadArtifact parts decode into PinnedInstallerArtifact.parts; parts on engineArtifact -> invalidField; malformed parts -> invalidField. Preparer: prepare(_:progress:) forwards; default-nil compiles.

## Risks
Disk peak ~7GiB staging; MainActor flooding (mitigated by throttle); ArtifactMaterialization new case — audit exhaustive switches; URLSession temp lifetime; tag/asset immutability procedural (publisher never-clobber); BSD split suffixes (rename step). Future hardening: host allowlist pin to github.com.
