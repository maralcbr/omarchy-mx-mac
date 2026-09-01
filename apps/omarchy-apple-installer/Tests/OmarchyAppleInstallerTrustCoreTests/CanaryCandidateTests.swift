import CryptoKit
import XCTest

@testable import OmarchyAppleInstallerTrustCore

final class CanaryCandidateTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_788_000_000)
  private let payloadDigest =
    "sha256:cd651bf7a610d2280084a9c1f28d0a39ac7791ef97e7725fd0627adce3ae1418"

  func testPrepareCanaryProducesSignedThinNonReleaseRepairCandidate() throws {
    let signer = Curve25519.Signing.PrivateKey()
    let instant = now
    let builder = try CandidateBuilder(
      canaryPrivateKey: signer.rawRepresentation,
      expectedTrustRootFingerprint: digest(signer.publicKey.rawRepresentation),
      now: { instant }
    )

    let candidate = try builder.prepare(.canary, validChangeSet())

    XCTAssertEqual(candidate.kind, .canary)
    XCTAssertEqual(candidate.marker, "CANARY — NOT FOR RELEASE")
    XCTAssertEqual(candidate.operation, "repair-installed-system")
    XCTAssertEqual(candidate.payload.digest, payloadDigest)
    XCTAssertEqual(candidate.payload.sizeBytes, 3_627_206_118)
    XCTAssertEqual(candidate.changedArtifacts.count, 1)
    XCTAssertLessThan(candidate.transferSizeBytes, 1_000_000)
    XCTAssertFalse(candidate.bundleFiles.contains { $0.pathExtension == "zip" })
    XCTAssertTrue(try candidate.verifySignature())
    XCTAssertThrowsError(try ReleaseCandidateVerifier().verify(candidate.manifest)) {
      XCTAssertEqual($0 as? CandidateError, .nonReleaseCandidate)
    }
  }

  func testCandidateBindsEnrollmentPayloadManifestChangesSourceAndSequence() throws {
    let signer = Curve25519.Signing.PrivateKey()
    let builder = try makeBuilder(signer)
    let baseline = try builder.prepare(.canary, validChangeSet())

    var changed = validChangeSet()
    changed.sequence += 1
    XCTAssertNotEqual(
      baseline.identityDigest,
      try builder.prepare(.canary, changed).identityDigest
    )
    changed = validChangeSet()
    changed.sourceTreeDigest = "sha256:" + String(repeating: "d", count: 64)
    XCTAssertNotEqual(
      baseline.identityDigest,
      try builder.prepare(.canary, changed).identityDigest
    )
    changed = validChangeSet()
    changed.enrollment.layoutDigest = "sha256:" + String(repeating: "e", count: 64)
    XCTAssertNotEqual(
      baseline.identityDigest,
      try builder.prepare(.canary, changed).identityDigest
    )
  }

  func testPrepareRejectsWrongOperationExpiredOrOverlongCandidate() throws {
    let signer = Curve25519.Signing.PrivateKey()
    let builder = try makeBuilder(signer)
    var changed = validChangeSet()
    changed.operation = "install"
    XCTAssertThrowsError(try builder.prepare(.canary, changed)) {
      XCTAssertEqual($0 as? CandidateError, .unsafeOperation)
    }
    changed = validChangeSet()
    changed.expiresAt = now
    XCTAssertThrowsError(try builder.prepare(.canary, changed)) {
      XCTAssertEqual($0 as? CandidateError, .expired)
    }
    changed = validChangeSet()
    changed.expiresAt = now.addingTimeInterval(3_601)
    XCTAssertThrowsError(try builder.prepare(.canary, changed)) {
      XCTAssertEqual($0 as? CandidateError, .expiryTooLong)
    }
  }

  func testThinCandidateAllowsOneEngineArchiveButRejectsReleaseSizedArtifacts() throws {
    let signer = Curve25519.Signing.PrivateKey()
    let builder = try makeBuilder(signer)
    var changed = validChangeSet()
    changed.changedArtifacts[0].sizeBytes = 64 * 1_024 * 1_024
    XCTAssertNoThrow(try builder.prepare(.canary, changed))

    changed.changedArtifacts[0].sizeBytes = 134_217_729
    XCTAssertThrowsError(try builder.prepare(.canary, changed)) {
      XCTAssertEqual($0 as? CandidateError, .unsafeArtifact)
    }
  }

  func testCachedPayloadReceiptFailsClosed() throws {
    let signer = Curve25519.Signing.PrivateKey()
    let instant = now
    let verifier = try CanaryPayloadCacheVerifier(
      publicKey: signer.publicKey.rawRepresentation,
      expectedTrustRootFingerprint: digest(signer.publicKey.rawRepresentation),
      now: { instant }
    )
    let receipt = validReceipt(signer)
    XCTAssertNoThrow(
      try verifier.verify(
        receipt,
        expected: .init(digest: payloadDigest, sizeBytes: 3_627_206_118)
      )
    )

    for mutation in ReceiptMutation.allCases {
      XCTAssertThrowsError(
        try verifier.verify(
          mutation.apply(to: receipt),
          expected: .init(digest: payloadDigest, sizeBytes: 3_627_206_118)
        ),
        "expected rejection for \(mutation)"
      )
    }
  }

  func testReleaseAndCanaryCandidateTypesRemainDistinct() {
    XCTAssertFalse(CanaryCandidate.self == ReleaseCandidate.self)
    XCTAssertEqual(CandidatePreparation.canary.kind, .canary)
    XCTAssertEqual(CandidatePreparation.release.kind, .release)
  }

  func testConfiguredCanaryRootRejectsTamperingSubstitutionAndReplay() throws {
    let signer = Curve25519.Signing.PrivateKey()
    let candidate = try makeBuilder(signer).prepare(.canary, validChangeSet())
    var guardState = CanaryReplayGuard(lastAcceptedSequence: 6)
    let verifier = try CanaryCandidateVerifier(
      publicKey: signer.publicKey.rawRepresentation,
      expectedTrustRootFingerprint: digest(signer.publicKey.rawRepresentation),
      now: { Date(timeIntervalSince1970: 1_788_000_000) }
    )

    XCTAssertNoThrow(try verifier.verify(candidate, replayGuard: &guardState))
    XCTAssertThrowsError(try verifier.verify(candidate, replayGuard: &guardState)) {
      XCTAssertEqual($0 as? CandidateError, .sequenceRollback)
    }

    var changedManifest = candidate.manifest
    changedManifest[changedManifest.startIndex] ^= 1
    let tampered = CanaryCandidate(
      operation: candidate.operation,
      payload: candidate.payload,
      repairManifest: candidate.repairManifest,
      changedArtifacts: candidate.changedArtifacts,
      manifest: changedManifest,
      signature: candidate.signature,
      publicKey: candidate.publicKey
    )
    var freshGuard = CanaryReplayGuard(lastAcceptedSequence: 6)
    XCTAssertThrowsError(try verifier.verify(tampered, replayGuard: &freshGuard)) {
      XCTAssertEqual($0 as? CandidateError, .invalidSignature)
    }

    let substitute = Curve25519.Signing.PrivateKey()
    XCTAssertThrowsError(
      try CanaryCandidateVerifier(
        publicKey: substitute.publicKey.rawRepresentation,
        expectedTrustRootFingerprint: digest(signer.publicKey.rawRepresentation)
      )
    ) {
      XCTAssertEqual($0 as? CandidateError, .invalidTrustRoot)
    }
  }

  func testThinBundleWriterStagesOnlyDeclaredSmallArtifacts() throws {
    let signer = Curve25519.Signing.PrivateKey()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "omarchy-canary-writer-\(UUID().uuidString.lowercased())",
      isDirectory: true
    )
    let sources = root.appendingPathComponent("sources", isDirectory: true)
    let output = root.appendingPathComponent("candidate", isDirectory: true)
    try FileManager.default.createDirectory(
      at: sources,
      withIntermediateDirectories: true
    )
    let repairData = Data("repair".utf8)
    let engineData = Data("changed-engine".utf8)
    let repairURL = sources.appendingPathComponent("repair-manifest.json")
    let engineURL = sources.appendingPathComponent("omarchy_repair.py")
    try repairData.write(to: repairURL)
    try engineData.write(to: engineURL)
    var changeSet = validChangeSet()
    changeSet.repairManifest = .init(
      relativePath: "repair-manifest.json",
      digest: digest(repairData),
      sizeBytes: UInt64(repairData.count)
    )
    changeSet.changedArtifacts = [
      .init(
        relativePath: "engine/omarchy_repair.py",
        digest: digest(engineData),
        sizeBytes: UInt64(engineData.count)
      )
    ]
    let candidate = try makeBuilder(signer).prepare(.canary, changeSet)

    let started = ContinuousClock.now
    let report = try CanaryCandidateBundleWriter().write(
      candidate,
      sources: [
        "repair-manifest.json": repairURL,
        "engine/omarchy_repair.py": engineURL,
      ],
      to: output
    )

    XCTAssertLessThan(started.duration(to: .now), .seconds(120))
    XCTAssertEqual(report.marker, "CANARY — NOT FOR RELEASE")
    XCTAssertEqual(report.reusedPayloadBytes, 3_627_206_118)
    XCTAssertEqual(report.copiedPayloadBytes, 0)
    XCTAssertEqual(report.cacheDecision, "reuse-verified-content-addressed-payload")
    XCTAssertEqual(
      report.phases.map(\.name),
      ["stage-declared-artifacts", "write-signed-metadata", "record-cache-decision"]
    )
    XCTAssertTrue(report.phases.allSatisfy { $0.elapsedMilliseconds < 120_000 })
    XCTAssertLessThan(report.bundleBytes, 1_000_000)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: output.appendingPathComponent("payload.zip").path
      )
    )

    let reopened = try CanaryCandidateBundleReader().read(from: output)
    XCTAssertEqual(reopened.identityDigest, candidate.identityDigest)
    XCTAssertEqual(reopened.repairManifest, candidate.repairManifest)
    XCTAssertEqual(reopened.changedArtifacts, candidate.changedArtifacts)

    let stagedEngine = output.appendingPathComponent("engine/omarchy_repair.py")
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: stagedEngine.path
    )
    try Data("tampered-engine".utf8).write(to: stagedEngine)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o400],
      ofItemAtPath: stagedEngine.path
    )
    XCTAssertThrowsError(
      try CanaryCandidateBundleReader().read(from: output)
    ) {
      XCTAssertEqual($0 as? CandidateError, .unsafeArtifact)
    }
  }

  func testCanaryAdmissionBindsLiveDeviceDiskLayoutAndPayloadReceipt() throws {
    let signer = Curve25519.Signing.PrivateKey()
    let changeSet = validChangeSet()
    let candidate = try makeBuilder(signer).prepare(.canary, changeSet)
    let fingerprint = digest(signer.publicKey.rawRepresentation)
    let adapter = try CanaryAdmissionAdapter(
      publicKey: signer.publicKey.rawRepresentation,
      expectedTrustRootFingerprint: fingerprint,
      now: { Date(timeIntervalSince1970: 1_788_000_000) }
    )
    var replay = CanaryReplayGuard(lastAcceptedSequence: 6)
    let admitted = try adapter.admit(
      candidate,
      observedEnrollment: changeSet.enrollment,
      payloadReceipt: validReceipt(signer),
      replayGuard: &replay
    )
    XCTAssertEqual(admitted.marker, "CANARY — NOT FOR RELEASE")
    XCTAssertEqual(admitted.operation, "repair-installed-system")

    var wrong = changeSet.enrollment
    wrong.diskIdentifier = "disk1"
    var fresh = CanaryReplayGuard(lastAcceptedSequence: 6)
    XCTAssertThrowsError(
      try adapter.admit(
        candidate,
        observedEnrollment: wrong,
        payloadReceipt: validReceipt(signer),
        replayGuard: &fresh
      )
    ) {
      XCTAssertEqual($0 as? CandidateError, .enrollmentMismatch)
    }
    wrong = changeSet.enrollment
    wrong.layoutDigest = "sha256:" + String(repeating: "0", count: 64)
    fresh = CanaryReplayGuard(lastAcceptedSequence: 6)
    XCTAssertThrowsError(
      try adapter.admit(
        candidate,
        observedEnrollment: wrong,
        payloadReceipt: validReceipt(signer),
        replayGuard: &fresh
      )
    ) {
      XCTAssertEqual($0 as? CandidateError, .enrollmentMismatch)
    }
  }

  private func makeBuilder(
    _ signer: Curve25519.Signing.PrivateKey
  ) throws -> CandidateBuilder {
    let instant = now
    return try CandidateBuilder(
      canaryPrivateKey: signer.rawRepresentation,
      expectedTrustRootFingerprint: digest(signer.publicKey.rawRepresentation),
      now: { instant }
    )
  }

  private func validChangeSet() -> CanaryChangeSet {
    CanaryChangeSet(
      sequence: 7,
      expiresAt: now.addingTimeInterval(900),
      sourceTreeDigest: "sha256:" + String(repeating: "a", count: 64),
      operation: "repair-installed-system",
      enrollment: .init(
        hardwareModel: "MacBookPro18,3",
        deviceIdentifier: "apple,j314s",
        enrolledDeviceIdentityDigest: "sha256:"
          + String(repeating: "f", count: 64),
        diskIdentifier: "disk0",
        layoutDigest: "sha256:" + String(repeating: "b", count: 64),
        partitionIdentifiers: ["disk0s3", "disk0s4", "disk0s5", "disk0s6"]
      ),
      payload: .init(digest: payloadDigest, sizeBytes: 3_627_206_118),
      repairManifest: .init(
        relativePath: "repair-manifest.json",
        digest: "sha256:" + String(repeating: "1", count: 64),
        sizeBytes: 4_096
      ),
      changedArtifacts: [
        .init(
          relativePath: "engine/omarchy_repair.py",
          digest: "sha256:" + String(repeating: "2", count: 64),
          sizeBytes: 24_000
        )
      ]
    )
  }

  private func validReceipt(
    _ signer: Curve25519.Signing.PrivateKey
  ) -> SignedCanaryPayloadReceipt {
    let receipt = CanaryPayloadCacheReceipt(
      format: 1,
      completed: true,
      digest: payloadDigest,
      sizeBytes: 3_627_206_118,
      path: "/var/cache/omarchy/cas/sha256/\(String(payloadDigest.dropFirst(7)))",
      ownerID: 0,
      mode: 0o400,
      verifiedAt: now.addingTimeInterval(-60),
      expiresAt: now.addingTimeInterval(900)
    )
    let payload = try! receipt.canonicalData()
    return SignedCanaryPayloadReceipt(
      receipt: receipt,
      signature: try! signer.signature(for: payload),
      publicKey: signer.publicKey.rawRepresentation
    )
  }

  private func digest(_ data: Data) -> String {
    SHA256Digest(hashing: data).rawValue
  }
}

private enum ReceiptMutation: CaseIterable {
  case incomplete, changedDigest, changedSize, mutable, unsafePath, stale, mismatchedKey

  func apply(to signed: SignedCanaryPayloadReceipt) -> SignedCanaryPayloadReceipt {
    var receipt = signed.receipt
    let signature = signed.signature
    var publicKey = signed.publicKey
    switch self {
    case .incomplete: receipt.completed = false
    case .changedDigest:
      receipt.digest = "sha256:" + String(repeating: "9", count: 64)
    case .changedSize: receipt.sizeBytes += 1
    case .mutable: receipt.mode = 0o600
    case .unsafePath: receipt.path = "/tmp/payload.zip"
    case .stale: receipt.expiresAt = Date(timeIntervalSince1970: 1)
    case .mismatchedKey:
      publicKey = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
    }
    return .init(
      receipt: receipt,
      signature: signature,
      publicKey: publicKey
    )
  }
}
