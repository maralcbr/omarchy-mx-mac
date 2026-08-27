import CryptoKit
import Foundation
import XCTest

import OmarchyAppleInstallerTrustCore

final class ClosedEngineProcessAdapterTests: XCTestCase {
  private let adapter = ClosedEngineProcessAdapter()
  private let now = Date(timeIntervalSince1970: 1_788_000_000)

  func testCancellationStopsBeforeProcessExecution() async throws {
    let fixture = try makeFixture()
    let authorization = ControlledAuthorization(decision: .cancelled)
    let process = ControlledProcess(transcript: fixture.transcript)

    await XCTAssertThrowsErrorAsync(
      try await adapter.execute(
        fixture.request,
        authorization: authorization,
        process: process
      )
    ) {
      XCTAssertEqual(
        $0 as? ClosedEngineProcessError,
        .authorizationCancelled
      )
    }

    let authorizationAttempts = await authorization.attemptCount
    let executions = await process.executionCount
    XCTAssertEqual(authorizationAttempts, 1)
    XCTAssertEqual(executions, 0)
  }

  func testDifferentValidPlanIsRejectedAfterExecution() async throws {
    let fixture = try makeFixture()
    let substituted = makeTranscript(lengthBytes: 96_636_764_160)
    let authorization = ControlledAuthorization(decision: .granted)
    let process = ControlledProcess(transcript: substituted.data)

    await XCTAssertThrowsErrorAsync(
      try await adapter.execute(
        fixture.request,
        authorization: authorization,
        process: process
      )
    ) {
      XCTAssertEqual(
        $0 as? ClosedEngineProcessError,
        .transcriptPlanMismatch
      )
    }

    let executions = await process.executionCount
    XCTAssertEqual(executions, 1)
  }

  func testInvalidCatalogSignatureStopsBeforeAuthorization() async throws {
    let fixture = try makeFixture(mutateCatalogAfterSigning: true)
    let authorization = ControlledAuthorization(decision: .granted)
    let process = ControlledProcess(transcript: fixture.transcript)

    await XCTAssertThrowsErrorAsync(
      try await adapter.execute(
        fixture.request,
        authorization: authorization,
        process: process
      )
    ) {
      XCTAssertEqual($0 as? SupportCatalogError, .invalidSignature)
    }

    let authorizationAttempts = await authorization.attemptCount
    let executions = await process.executionCount
    XCTAssertEqual(authorizationAttempts, 0)
    XCTAssertEqual(executions, 0)
  }

  func testMalformedProcessTranscriptIsRejected() async throws {
    let fixture = try makeFixture()
    let malformed = fixture.transcript + Data("not-json\n".utf8)
    let authorization = ControlledAuthorization(decision: .granted)
    let process = ControlledProcess(transcript: malformed)

    await XCTAssertThrowsErrorAsync(
      try await adapter.execute(
        fixture.request,
        authorization: authorization,
        process: process
      )
    ) {
      XCTAssertEqual($0 as? EngineContractError, .invalidJSON(7))
    }
  }

  func testM4RemainsRejectedEvenWhenSignedCatalogEnablesIt() async throws {
    let fixture = try makeFixture(deviceIdentifier: "apple,j614s")
    let authorization = ControlledAuthorization(decision: .granted)
    let process = ControlledProcess(transcript: fixture.transcript)

    await XCTAssertThrowsErrorAsync(
      try await adapter.execute(
        fixture.request,
        authorization: authorization,
        process: process
      )
    ) {
      XCTAssertEqual(
        $0 as? ClosedEngineProcessError,
        .unsupportedDevice("apple,j614s")
      )
    }

    let authorizationAttempts = await authorization.attemptCount
    let executions = await process.executionCount
    XCTAssertEqual(authorizationAttempts, 0)
    XCTAssertEqual(executions, 0)
  }

  func testValidatedRequestReturnsExactProcessTranscript() async throws {
    let fixture = try makeFixture()
    let authorization = ControlledAuthorization(decision: .granted)
    let process = ControlledProcess(transcript: fixture.transcript)

    let result = try await adapter.execute(
      fixture.request,
      authorization: authorization,
      process: process
    )

    XCTAssertEqual(result.deviceIdentifier, "apple,j314s")
    XCTAssertEqual(result.plan?.planDigest, fixture.planDigest)
    XCTAssertEqual(result.completion, .awaitingRecovery)
    let authorizationAttempts = await authorization.attemptCount
    let executions = await process.executionCount
    XCTAssertEqual(authorizationAttempts, 1)
    XCTAssertEqual(executions, 1)
  }

  private func makeFixture(
    deviceIdentifier: String = "apple,j314s",
    mutateCatalogAfterSigning: Bool = false
  ) throws -> ClosedAdapterFixture {
    let transcript = makeTranscript(deviceIdentifier: deviceIdentifier)
    let privateKey = Curve25519.Signing.PrivateKey()
    let catalog = makeCatalog(deviceIdentifier: deviceIdentifier)
    let signature = try privateKey.signature(for: catalog)
    let deliveredCatalog = mutateCatalogAfterSigning
      ? catalog + Data(" ".utf8)
      : catalog
    let request = ClosedEngineRequest(
      planningTranscript: transcript.data,
      approvedPlanDigest: transcript.planDigest,
      catalogPayload: deliveredCatalog,
      catalogSignature: signature,
      catalogPublicKey: privateKey.publicKey.rawRepresentation,
      validationTime: now
    )
    return ClosedAdapterFixture(
      request: request,
      transcript: transcript.data,
      planDigest: transcript.planDigest
    )
  }

  private func makeCatalog(deviceIdentifier: String) -> Data {
    let issued = ISO8601DateFormatter().string(
      from: now.addingTimeInterval(-3_600)
    )
    let expires = ISO8601DateFormatter().string(
      from: now.addingTimeInterval(86_400)
    )
    return Data(
      """
      {"schemaVersion":1,"sequence":20,"issuedAt":"\(issued)","expiresAt":"\(expires)","models":[{"deviceIdentifier":"\(deviceIdentifier)","status":"enabled","asahiInstallerTag":"v0.9.0","asahiInstallerRevision":"\(String(repeating: "a", count: 40))","asahiInstallerDataRevision":"\(String(repeating: "b", count: 40))","downstreamRevision":"\(String(repeating: "c", count: 40))","engineDigest":"sha256:\(String(repeating: "d", count: 64))","metadataDigest":"sha256:\(String(repeating: "e", count: 64))","payloadDigest":"sha256:\(String(repeating: "f", count: 64))","evidenceRevision":"evidence-s2"}]}
      """.utf8
    )
  }

  private func makeTranscript(
    deviceIdentifier: String = "apple,j314s",
    lengthBytes: UInt64 = 107_374_182_400
  ) -> TranscriptFixture {
    let layoutDigest = lengthPrefixedDigest(
      [
        "disk0", "free", "disk0s3", "447750000000",
        String(lengthBytes), "67501226240", "0",
      ],
      prefix: "sha256:"
    )
    let humanSteps = [
      "enterOneTrueRecovery",
      "authenticateMachineOwner",
    ]
    let planDigest = lengthPrefixedDigest(
      [
        deviceIdentifier, "disk0", layoutDigest, "free", "disk0s3",
        "447750000000", String(lengthBytes), "v0.9.0-omarchy.1",
        "sha256:" + String(repeating: "d", count: 64),
        "sha256:" + String(repeating: "e", count: 64),
        "sha256:" + String(repeating: "f", count: 64),
        humanSteps.joined(separator: ","),
      ],
      prefix: ""
    )
    let evidence = "sha256:" + String(repeating: "b", count: 64)
    let records = [
      #"{"schema_version":1,"sequence":1,"type":"inspection","payload":{"device_identifier":"\#(deviceIdentifier)","support":"supported"}}"#,
      #"{"schema_version":1,"sequence":2,"type":"inventory","payload":{"layout_digest":"\#(layoutDigest)","system_store_identifier":"disk0","candidates":[{"kind":"free","source_identifier":"disk0s3","offset_bytes":447750000000,"length_bytes":\#(lengthBytes),"minimum_install_bytes":67501226240,"minimum_container_bytes":0}]}}"#,
      #"{"schema_version":1,"sequence":3,"type":"plan","payload":{"plan_digest":"\#(planDigest)","device_identifier":"\#(deviceIdentifier)","store_identifier":"disk0","layout_digest":"\#(layoutDigest)","candidate_kind":"free","source_identifier":"disk0s3","offset_bytes":447750000000,"length_bytes":\#(lengthBytes),"engine_version":"v0.9.0-omarchy.1","engine_digest":"sha256:\#(String(repeating: "d", count: 64))","metadata_digest":"sha256:\#(String(repeating: "e", count: 64))","payload_digest":"sha256:\#(String(repeating: "f", count: 64))","required_human_steps":["enterOneTrueRecovery","authenticateMachineOwner"]}}"#,
      #"{"schema_version":1,"sequence":4,"type":"event","payload":{"plan_digest":"\#(planDigest)","name":"apfs_preparation_started"}}"#,
      #"{"schema_version":1,"sequence":5,"type":"checkpoint","payload":{"plan_digest":"\#(planDigest)","identifier":"cp-1","phase":"apfs_preparation","evidence_digest":"\#(evidence)"}}"#,
      #"{"schema_version":1,"sequence":6,"type":"completion","payload":{"plan_digest":"\#(planDigest)","outcome":"awaiting_recovery"}}"#,
    ]
    return TranscriptFixture(
      data: Data((records.joined(separator: "\n") + "\n").utf8),
      planDigest: planDigest
    )
  }

  private func lengthPrefixedDigest(
    _ fields: [String],
    prefix: String
  ) -> String {
    let canonical = fields
      .map { "\($0.utf8.count):\($0)" }
      .joined(separator: "|")
    let digest = SHA256.hash(data: Data(canonical.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    return prefix + digest
  }
}

private actor ControlledAuthorization: EngineExecutionAuthorizing {
  private(set) var attemptCount = 0
  private let storedDecision: EngineAuthorizationDecision

  init(decision: EngineAuthorizationDecision) {
    storedDecision = decision
  }

  func decision(
    for invocation: ClosedEngineInvocation
  ) async -> EngineAuthorizationDecision {
    attemptCount += 1
    return storedDecision
  }
}

private actor ControlledProcess: EngineProcessExecuting {
  private(set) var executionCount = 0
  private let transcript: Data

  init(transcript: Data) {
    self.transcript = transcript
  }

  func execute(_ invocation: ClosedEngineInvocation) async throws -> Data {
    executionCount += 1
    return transcript
  }
}

private struct ClosedAdapterFixture {
  let request: ClosedEngineRequest
  let transcript: Data
  let planDigest: String
}

private struct TranscriptFixture {
  let data: Data
  let planDigest: String
}

private func XCTAssertThrowsErrorAsync<T>(
  _ expression: @autoclosure () async throws -> T,
  _ errorHandler: (any Error) -> Void = { _ in }
) async {
  do {
    _ = try await expression()
    XCTFail("Expected expression to throw")
  } catch {
    errorHandler(error)
  }
}
