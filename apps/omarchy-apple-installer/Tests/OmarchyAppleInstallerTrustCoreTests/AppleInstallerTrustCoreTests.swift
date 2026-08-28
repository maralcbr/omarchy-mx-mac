import CryptoKit
import Foundation
import OmarchyAppleInstallerTrustCore
import XCTest

final class AppleInstallerTrustCoreTests: XCTestCase {
  private let core = AppleInstallerTrustCore()
  private let now = Date(timeIntervalSince1970: 1_788_000_000)

  func testSupportedTranscriptExposesValidatedSummary() throws {
    let result = try core.validateEngineTranscript(Data(makeTranscript().utf8))

    XCTAssertEqual(result.deviceIdentifier, "apple,j314s")
    XCTAssertEqual(result.support, .supported)
    XCTAssertEqual(result.plan?.sourceIdentifier, "disk0s3")
    XCTAssertEqual(result.inventory?.systemStoreIdentifier, "disk0")
    XCTAssertEqual(result.inventory?.candidates.count, 1)
    XCTAssertEqual(result.inventory?.candidates.first?.kind, "free")
    XCTAssertEqual(
      result.plan?.requiredHumanSteps,
      [
        "enterOneTrueRecovery",
        "authenticateMachineOwner",
      ])
    XCTAssertEqual(result.checkpoints.map(\.phase), ["apfs_preparation"])
    XCTAssertEqual(result.completion, .awaitingRecovery)
  }

  func testM4UnsupportedInspectionRemainsClosed() throws {
    let transcript = """
      {"schema_version":1,"sequence":1,"type":"inspection","payload":{"device_identifier":"apple,j614s","support":"unsupported"}}

      """

    let result = try core.validateEngineTranscript(Data(transcript.utf8))

    XCTAssertEqual(result.deviceIdentifier, "apple,j614s")
    XCTAssertEqual(result.support, .unsupported)
    XCTAssertNil(result.plan)
    XCTAssertTrue(result.checkpoints.isEmpty)
    XCTAssertNil(result.completion)
  }

  func testTranscriptRejectsSkippedSequence() {
    let transcript = makeTranscript().replacingOccurrences(
      of: #""sequence":4,"type":"event""#,
      with: #""sequence":8,"type":"event""#
    )

    XCTAssertThrowsError(
      try core.validateEngineTranscript(Data(transcript.utf8))
    ) {
      XCTAssertEqual(
        $0 as? EngineContractError,
        .invalidSequence(expected: 4, actual: 8)
      )
    }
  }

  func testTranscriptRejectsUnknownPlanField() {
    let transcript = makeTranscript().replacingOccurrences(
      of: #""required_human_steps":["enterOneTrueRecovery","authenticateMachineOwner"]"#,
      with:
        #""required_human_steps":["enterOneTrueRecovery","authenticateMachineOwner"],"whole_disk":true"#
    )

    XCTAssertThrowsError(
      try core.validateEngineTranscript(Data(transcript.utf8))
    ) {
      XCTAssertEqual($0 as? EngineContractError, .unknownFields(3))
    }
  }

  func testTranscriptRejectsStalePlanEvent() {
    let transcript = makeTranscript(
      eventPlanDigest: String(repeating: "c", count: 64)
    )

    XCTAssertThrowsError(
      try core.validateEngineTranscript(Data(transcript.utf8))
    ) {
      XCTAssertEqual($0 as? EngineContractError, .stalePlanDigest(4))
    }
  }

  func testSignedCatalogAdmitsOnlyEnabledModel() throws {
    let fixture = try makeCatalog(sequence: 7)

    let result = try core.validateSupportCatalog(
      payload: fixture.payload,
      signature: fixture.signature,
      trustRoot: fixture.trustRoot,
      now: now
    )

    XCTAssertEqual(result.sequence, 7)
    guard case .admitted(let record) = result.admission(for: "apple,j314s") else {
      return XCTFail("Expected the signed M1 Pro record to be admitted")
    }
    XCTAssertEqual(record.asahiInstallerTag, "v0.9.0")
    XCTAssertEqual(
      result.admission(for: "apple,j614s"),
      .unsupported(deviceIdentifier: "apple,j614s")
    )
  }

  func testCatalogRejectsInvalidSignature() throws {
    let fixture = try makeCatalog(sequence: 8)
    let mutatedPayload = fixture.payload + Data(" ".utf8)

    XCTAssertThrowsError(
      try core.validateSupportCatalog(
        payload: mutatedPayload,
        signature: fixture.signature,
        trustRoot: fixture.trustRoot,
        now: now
      )
    ) {
      XCTAssertEqual($0 as? SupportCatalogError, .invalidSignature)
    }
  }

  func testCatalogRejectsExpiredManifest() throws {
    let fixture = try makeCatalog(
      sequence: 9,
      issuedAt: now.addingTimeInterval(-7_200),
      expiresAt: now.addingTimeInterval(-3_600)
    )

    XCTAssertThrowsError(
      try core.validateSupportCatalog(
        payload: fixture.payload,
        signature: fixture.signature,
        trustRoot: fixture.trustRoot,
        now: now
      )
    ) {
      XCTAssertEqual($0 as? SupportCatalogError, .expired)
    }
  }

  func testOlderCatalogCannotRollBackAcceptedIdentity() throws {
    let current = try validateCatalog(makeCatalog(sequence: 10))
    let older = try makeCatalog(sequence: 9)

    XCTAssertThrowsError(
      try core.validateSupportCatalog(
        payload: older.payload,
        signature: older.signature,
        trustRoot: older.trustRoot,
        now: now,
        previouslyAccepted: current.acceptedIdentity
      )
    ) {
      XCTAssertEqual(
        $0 as? SupportCatalogSequenceError,
        .rollback(stored: 10, candidate: 9)
      )
    }
  }

  func testDifferentPayloadCannotReuseAcceptedSequence() throws {
    let first = try validateCatalog(
      makeCatalog(sequence: 11, evidence: "evidence-a")
    )
    let replacement = try makeCatalog(
      sequence: 11,
      evidence: "evidence-b"
    )

    XCTAssertThrowsError(
      try core.validateSupportCatalog(
        payload: replacement.payload,
        signature: replacement.signature,
        trustRoot: replacement.trustRoot,
        now: now,
        previouslyAccepted: first.acceptedIdentity
      )
    ) {
      XCTAssertEqual($0 as? SupportCatalogSequenceError, .sequenceReuse(11))
    }
  }

  func testExactCatalogReplayIsIdempotent() throws {
    let fixture = try makeCatalog(sequence: 12)
    let first = try validateCatalog(fixture)
    let replay = try core.validateSupportCatalog(
      payload: fixture.payload,
      signature: fixture.signature,
      trustRoot: fixture.trustRoot,
      now: now,
      previouslyAccepted: first.acceptedIdentity
    )

    XCTAssertEqual(replay.acceptedIdentity, first.acceptedIdentity)
  }

  func testAcceptedIdentityRejectsInvalidPersistedValues() {
    XCTAssertThrowsError(
      try AcceptedCatalogIdentity(
        sequence: 0,
        payloadDigest: "sha256:" + String(repeating: "a", count: 64)
      )
    ) {
      XCTAssertEqual(
        $0 as? SupportCatalogSequenceError,
        .invalidStoredIdentity
      )
    }
  }

  private func validateCatalog(
    _ fixture: CatalogFixture
  ) throws -> ValidatedSupportCatalog {
    try core.validateSupportCatalog(
      payload: fixture.payload,
      signature: fixture.signature,
      trustRoot: fixture.trustRoot,
      now: now
    )
  }

  private func makeCatalog(
    sequence: UInt64,
    evidence: String = "evidence-1",
    issuedAt: Date? = nil,
    expiresAt: Date? = nil
  ) throws -> CatalogFixture {
    let privateKey = Curve25519.Signing.PrivateKey()
    let issued = ISO8601DateFormatter().string(
      from: issuedAt ?? now.addingTimeInterval(-3_600)
    )
    let expires = ISO8601DateFormatter().string(
      from: expiresAt ?? now.addingTimeInterval(86_400)
    )
    let models = [
      catalogModel(
        deviceIdentifier: "apple,j314s",
        status: "enabled",
        evidence: evidence
      ),
      catalogModel(
        deviceIdentifier: "apple,j614s",
        status: "disabled",
        evidence: evidence
      ),
    ].joined(separator: ",")
    let payload = Data(
      """
      {"schemaVersion":1,"sequence":\(sequence),"issuedAt":"\(issued)","expiresAt":"\(expires)","models":[\(models)]}
      """.utf8
    )
    let publicKey = privateKey.publicKey.rawRepresentation
    let fingerprint =
      "sha256:"
      + SHA256.hash(data: publicKey)
      .map { String(format: "%02x", $0) }
      .joined()
    return CatalogFixture(
      payload: payload,
      signature: try privateKey.signature(for: payload),
      trustRoot: try AppOwnedTrustRoot(
        rawRepresentation: publicKey,
        expectedFingerprint: fingerprint
      )
    )
  }

  private func catalogModel(
    deviceIdentifier: String,
    status: String,
    evidence: String
  ) -> String {
    """
    {"deviceIdentifier":"\(deviceIdentifier)","status":"\(status)","asahiInstallerTag":"v0.9.0","asahiInstallerRevision":"\(String(repeating: "a", count: 40))","asahiInstallerDataRevision":"\(String(repeating: "b", count: 40))","downstreamRevision":"\(String(repeating: "c", count: 40))","engineDigest":"sha256:\(String(repeating: "d", count: 64))","metadataDigest":"sha256:\(String(repeating: "e", count: 64))","payloadDigest":"sha256:\(String(repeating: "f", count: 64))","evidenceRevision":"\(evidence)"}
    """
  }

  private func makeTranscript(
    eventPlanDigest: String? = nil
  ) -> String {
    let layoutDigest = lengthPrefixedDigest(
      [
        "disk0", "free", "disk0s3", "447750000000", "107374182400",
        "67501226240", "0",
      ],
      prefix: "sha256:"
    )
    let requiredHumanSteps = [
      "enterOneTrueRecovery",
      "authenticateMachineOwner",
    ]
    let planDigest = lengthPrefixedDigest(
      [
        "apple,j314s", "disk0", layoutDigest, "free", "disk0s3",
        "447750000000", "107374182400", "v0.9.0-omarchy.1",
        "sha256:" + String(repeating: "d", count: 64),
        "sha256:" + String(repeating: "e", count: 64),
        "sha256:" + String(repeating: "f", count: 64),
        requiredHumanSteps.joined(separator: ","),
      ],
      prefix: ""
    )
    let eventDigest = eventPlanDigest ?? planDigest
    let evidenceDigest = "sha256:" + String(repeating: "b", count: 64)

    return [
      #"{"schema_version":1,"sequence":1,"type":"inspection","payload":{"device_identifier":"apple,j314s","support":"supported"}}"#,
      #"{"schema_version":1,"sequence":2,"type":"inventory","payload":{"layout_digest":"\#(layoutDigest)","system_store_identifier":"disk0","candidates":[{"kind":"free","source_identifier":"disk0s3","offset_bytes":447750000000,"length_bytes":107374182400,"minimum_install_bytes":67501226240,"minimum_container_bytes":0}]}}"#,
      #"{"schema_version":1,"sequence":3,"type":"plan","payload":{"plan_digest":"\#(planDigest)","device_identifier":"apple,j314s","store_identifier":"disk0","layout_digest":"\#(layoutDigest)","candidate_kind":"free","source_identifier":"disk0s3","offset_bytes":447750000000,"length_bytes":107374182400,"engine_version":"v0.9.0-omarchy.1","engine_digest":"sha256:\#(String(repeating: "d", count: 64))","metadata_digest":"sha256:\#(String(repeating: "e", count: 64))","payload_digest":"sha256:\#(String(repeating: "f", count: 64))","required_human_steps":["enterOneTrueRecovery","authenticateMachineOwner"]}}"#,
      #"{"schema_version":1,"sequence":4,"type":"event","payload":{"plan_digest":"\#(eventDigest)","name":"apfs_preparation_started"}}"#,
      #"{"schema_version":1,"sequence":5,"type":"checkpoint","payload":{"plan_digest":"\#(planDigest)","identifier":"cp-1","phase":"apfs_preparation","evidence_digest":"\#(evidenceDigest)"}}"#,
      #"{"schema_version":1,"sequence":6,"type":"completion","payload":{"plan_digest":"\#(planDigest)","outcome":"awaiting_recovery"}}"#,
    ].joined(separator: "\n") + "\n"
  }

  private func lengthPrefixedDigest(
    _ fields: [String],
    prefix: String
  ) -> String {
    let canonical =
      fields
      .map { "\($0.utf8.count):\($0)" }
      .joined(separator: "|")
    let digest = SHA256.hash(data: Data(canonical.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    return prefix + digest
  }
}

private struct CatalogFixture {
  let payload: Data
  let signature: Data
  let trustRoot: AppOwnedTrustRoot
}
