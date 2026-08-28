#if os(macOS)
  import CryptoKit
  import Darwin
  import Foundation
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  final class ClosedEngineHandoffProcessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    func testApprovedInvocationProducesPrivateBoundPackageAndCleansIt() async throws {
      let fixture = try makeFixture()
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let submitter = RecordingHandoffSubmitter(
        transcript: fixture.executionTranscript
      )
      let process = ClosedEngineHandoffProcess(
        assets: fixture.assets,
        handoffDirectory: fixture.handoffDirectory,
        submitter: submitter
      )

      let result = try await ClosedEngineProcessAdapter().execute(
        fixture.request,
        approval: fixture.approval,
        authorization: GrantedEngineAuthorization(),
        process: process
      )

      XCTAssertEqual(result.completion, .awaitingRecovery)
      let recordedSnapshot = await submitter.snapshot
      let snapshot = try XCTUnwrap(recordedSnapshot)
      XCTAssertEqual(snapshot.packageMode, 0o700)
      XCTAssertTrue(snapshot.fileModes.allSatisfy { $0 == 0o400 })
      XCTAssertEqual(snapshot.engine, fixture.engine)
      XCTAssertEqual(snapshot.metadata, fixture.metadata)
      XCTAssertEqual(snapshot.payload, fixture.payload)
      XCTAssertFalse(
        FileManager.default.fileExists(atPath: snapshot.packageURL.path)
      )

      let request = try XCTUnwrap(
        try JSONSerialization.jsonObject(with: snapshot.request)
          as? [String: Any]
      )
      XCTAssertEqual(request["operation"] as? String, "install")
      XCTAssertEqual(request["plan_digest"] as? String, fixture.planDigest)
      let identity = try XCTUnwrap(
        try JSONSerialization.jsonObject(with: snapshot.identity)
          as? [String: Any]
      )
      XCTAssertEqual(
        identity["binding_digest"] as? String,
        fixture.approval.identity.bindingDigest
      )
      let manifest = try XCTUnwrap(
        try JSONSerialization.jsonObject(with: snapshot.manifest)
          as? [String: Any]
      )
      let manifestEngine = try XCTUnwrap(
        manifest["engine"] as? [String: Any]
      )
      XCTAssertEqual(
        manifestEngine["file_name"] as? String,
        fixture.assets.engine.artifact.fileName
      )
    }

    func testChangedEngineBytesStopBeforeSubmission() async throws {
      let fixture = try makeFixture(corruptEngine: true)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let submitter = RecordingHandoffSubmitter(
        transcript: fixture.executionTranscript
      )

      await assertThrows(
        try await ClosedEngineProcessAdapter().execute(
          fixture.request,
          approval: fixture.approval,
          authorization: GrantedEngineAuthorization(),
          process: ClosedEngineHandoffProcess(
            assets: fixture.assets,
            handoffDirectory: fixture.handoffDirectory,
            submitter: submitter
          )
        )
      ) {
        XCTAssertEqual(
          $0 as? ClosedEngineHandoffError,
          .artifactDigestMismatch("engine")
        )
      }
      let submissionCount = await submitter.submissionCount
      XCTAssertEqual(submissionCount, 0)
    }

    func testSymlinkedPayloadStopsBeforeSubmission() async throws {
      let fixture = try makeFixture(symlinkPayload: true)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let submitter = RecordingHandoffSubmitter(
        transcript: fixture.executionTranscript
      )

      await assertThrows(
        try await ClosedEngineProcessAdapter().execute(
          fixture.request,
          approval: fixture.approval,
          authorization: GrantedEngineAuthorization(),
          process: ClosedEngineHandoffProcess(
            assets: fixture.assets,
            handoffDirectory: fixture.handoffDirectory,
            submitter: submitter
          )
        )
      ) {
        XCTAssertEqual(
          $0 as? ClosedEngineHandoffError,
          .unsafeArtifact("payload")
        )
      }
      let submissionCount = await submitter.submissionCount
      XCTAssertEqual(submissionCount, 0)
    }

    private func makeFixture(
      corruptEngine: Bool = false,
      symlinkPayload: Bool = false
    ) throws -> HandoffFixture {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "omarchy-handoff-tests-\(UUID().uuidString.lowercased())",
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      let handoffDirectory = root.appendingPathComponent(
        "handoffs",
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: handoffDirectory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )

      let engine = Data("engine-a".utf8)
      let metadata = Data("metadata".utf8)
      let payload = Data("payload".utf8)
      let engineArtifact = try artifact(
        role: "engine",
        name: "engine.tar.gz",
        data: engine
      )
      let metadataArtifact = try artifact(
        role: "metadata",
        name: "installer-data.json",
        data: metadata
      )
      let payloadArtifact = try artifact(
        role: "payload",
        name: "omarchy.img.zst",
        data: payload
      )
      let engineURL = root.appendingPathComponent(engineArtifact.fileName)
      let metadataURL = root.appendingPathComponent(metadataArtifact.fileName)
      let payloadURL = root.appendingPathComponent(payloadArtifact.fileName)
      try writePrivate(
        corruptEngine ? Data("engine-b".utf8) : engine,
        to: engineURL
      )
      try writePrivate(metadata, to: metadataURL)
      if symlinkPayload {
        let target = root.appendingPathComponent("payload-target")
        try writePrivate(payload, to: target)
        try FileManager.default.createSymbolicLink(
          at: payloadURL,
          withDestinationURL: target
        )
      } else {
        try writePrivate(payload, to: payloadURL)
      }

      let delivery = PinnedInstallerDelivery(
        engine: engineArtifact,
        metadata: metadataArtifact,
        payload: payloadArtifact
      )
      let record = PinnedInstallerRecord(
        deviceIdentifier: "apple,j314s",
        asahiInstallerTag: "v0.9.0",
        asahiInstallerRevision: String(repeating: "a", count: 40),
        asahiInstallerDataRevision: String(repeating: "b", count: 40),
        downstreamRevision: String(repeating: "c", count: 40),
        engineVersion: "v0.9.0-omarchy.2",
        engineDigest: engineArtifact.expectedDigest,
        metadataDigest: metadataArtifact.expectedDigest,
        payloadDigest: payloadArtifact.expectedDigest,
        evidenceRevision: "evidence-handoff",
        delivery: delivery
      )
      let catalog = catalogPayload(
        record: record,
        engine: engineArtifact,
        metadata: metadataArtifact,
        payload: payloadArtifact
      )
      let privateKey = Curve25519.Signing.PrivateKey()
      let signature = try privateKey.signature(for: catalog)
      let publicKey = privateKey.publicKey.rawRepresentation
      let trustRoot = try AppOwnedTrustRoot(
        rawRepresentation: publicKey,
        expectedFingerprint: digest(publicKey)
      )
      let catalogIdentity = try AcceptedCatalogIdentity(
        sequence: 40,
        payloadDigest: digest(catalog)
      )
      let transcript = transcript(
        engineDigest: record.engineDigest,
        metadataDigest: record.metadataDigest,
        payloadDigest: record.payloadDigest
      )
      let request = ClosedEngineCandidateRequest(
        planningTranscript: transcript.planning,
        catalogPayload: catalog,
        catalogSignature: signature,
        trustRoot: trustRoot,
        validationTime: now
      )
      let identity = try ClosedEngineProcessAdapter().candidateIdentity(
        for: request
      )
      let assets = PreparedInstallerAssets(
        catalogIdentity: catalogIdentity,
        installer: record,
        engine: StagedInstallerArtifact(
          artifact: engineArtifact,
          fileURL: engineURL,
          reusedExistingFile: false
        ),
        metadata: StagedInstallerArtifact(
          artifact: metadataArtifact,
          fileURL: metadataURL,
          reusedExistingFile: false
        ),
        payload: StagedInstallerArtifact(
          artifact: payloadArtifact,
          fileURL: payloadURL,
          reusedExistingFile: false
        )
      )
      return HandoffFixture(
        root: root,
        handoffDirectory: handoffDirectory,
        request: request,
        approval: CandidateBoundPlanApproval(
          identity: identity,
          approvedBindingDigest: identity.bindingDigest
        ),
        assets: assets,
        executionTranscript: transcript.execution,
        planDigest: transcript.planDigest,
        engine: engine,
        metadata: metadata,
        payload: payload
      )
    }

    private func artifact(
      role: String,
      name: String,
      data: Data
    ) throws -> PinnedInstallerArtifact {
      try PinnedInstallerArtifact(
        role: role,
        sourceURL: URL(
          string: "https://downloads.example.com/\(name)"
        )!,
        fileName: name,
        expectedDigest: digest(data),
        expectedSizeBytes: UInt64(data.count)
      )
    }

    private func catalogPayload(
      record: PinnedInstallerRecord,
      engine: PinnedInstallerArtifact,
      metadata: PinnedInstallerArtifact,
      payload: PinnedInstallerArtifact
    ) -> Data {
      let issued = ISO8601DateFormatter().string(
        from: now.addingTimeInterval(-3_600)
      )
      let expires = ISO8601DateFormatter().string(
        from: now.addingTimeInterval(86_400)
      )
      let catalog = Data(
        """
        {"schemaVersion":2,"sequence":40,"issuedAt":"\(issued)","expiresAt":"\(expires)","models":[{"deviceIdentifier":"\(record.deviceIdentifier)","status":"enabled","asahiInstallerTag":"\(record.asahiInstallerTag)","asahiInstallerRevision":"\(record.asahiInstallerRevision)","asahiInstallerDataRevision":"\(record.asahiInstallerDataRevision)","downstreamRevision":"\(record.downstreamRevision)","engineDigest":"\(record.engineDigest)","metadataDigest":"\(record.metadataDigest)","payloadDigest":"\(record.payloadDigest)","evidenceRevision":"\(record.evidenceRevision)","engineArtifact":{"sourceURL":"\(engine.sourceURL.absoluteString)","fileName":"\(engine.fileName)","sizeBytes":\(engine.expectedSizeBytes)},"metadataArtifact":{"sourceURL":"\(metadata.sourceURL.absoluteString)","fileName":"\(metadata.fileName)","sizeBytes":\(metadata.expectedSizeBytes)},"payloadArtifact":{"sourceURL":"\(payload.sourceURL.absoluteString)","fileName":"\(payload.fileName)","sizeBytes":\(payload.expectedSizeBytes)}}]}
        """.utf8
      )
      let text = String(decoding: catalog, as: UTF8.self)
      let marker = ",\"engineDigest\":"
      let engineVersion = record.engineVersion ?? ""
      let replacement =
        ",\"engineVersion\":\"\(engineVersion)\",\"engineDigest\":"
      return Data(
        text.replacingOccurrences(of: marker, with: replacement).utf8
      )
    }

    private func transcript(
      engineDigest: String,
      metadataDigest: String,
      payloadDigest: String
    ) -> HandoffTranscript {
      let layoutDigest = lengthPrefixedDigest(
        ["disk0", "free", "disk0s3", "2000", "1000", "100", "0"],
        prefix: "sha256:"
      )
      let humanSteps = [
        "enterOneTrueRecovery",
        "authenticateMachineOwner",
      ]
      let planDigest = lengthPrefixedDigest(
        [
          "apple,j314s", "disk0", layoutDigest, "free", "disk0s3",
          "2000", "1000", "v0.9.0-omarchy.2", engineDigest,
          metadataDigest, payloadDigest, humanSteps.joined(separator: ","),
        ],
        prefix: ""
      )
      let records = [
        #"{"schema_version":1,"sequence":1,"type":"inspection","payload":{"device_identifier":"apple,j314s","support":"supported"}}"#,
        #"{"schema_version":1,"sequence":2,"type":"inventory","payload":{"layout_digest":"\#(layoutDigest)","system_store_identifier":"disk0","candidates":[{"kind":"free","source_identifier":"disk0s3","offset_bytes":2000,"length_bytes":1000,"minimum_install_bytes":100,"minimum_container_bytes":0}]}}"#,
        #"{"schema_version":1,"sequence":3,"type":"plan","payload":{"plan_digest":"\#(planDigest)","device_identifier":"apple,j314s","store_identifier":"disk0","layout_digest":"\#(layoutDigest)","candidate_kind":"free","source_identifier":"disk0s3","offset_bytes":2000,"length_bytes":1000,"engine_version":"v0.9.0-omarchy.2","engine_digest":"\#(engineDigest)","metadata_digest":"\#(metadataDigest)","payload_digest":"\#(payloadDigest)","required_human_steps":["enterOneTrueRecovery","authenticateMachineOwner"]}}"#,
      ]
      let planning = Data((records.joined(separator: "\n") + "\n").utf8)
      let completion =
        #"{"schema_version":1,"sequence":4,"type":"completion","payload":{"plan_digest":"\#(planDigest)","outcome":"awaiting_recovery"}}"#
      let execution = Data(
        (records.joined(separator: "\n") + "\n" + completion + "\n").utf8
      )
      return HandoffTranscript(
        planning: planning,
        execution: execution,
        planDigest: planDigest
      )
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
      try data.write(to: url, options: .withoutOverwriting)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o400],
        ofItemAtPath: url.path
      )
    }

    private func digest(_ data: Data) -> String {
      "sha256:"
        + SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
    }

    private func lengthPrefixedDigest(
      _ fields: [String],
      prefix: String
    ) -> String {
      let canonical =
        fields
        .map { "\($0.utf8.count):\($0)" }
        .joined(separator: "|")
      return prefix
        + SHA256.hash(data: Data(canonical.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
    }
  }

  private struct GrantedEngineAuthorization: EngineExecutionAuthorizing {
    func decision(
      for invocation: ClosedEngineInvocation
    ) async -> EngineAuthorizationDecision {
      .granted
    }
  }

  private actor RecordingHandoffSubmitter: EngineHandoffSubmitting {
    private let transcript: Data
    private(set) var submissionCount = 0
    private(set) var snapshot: HandoffSnapshot?

    init(transcript: Data) {
      self.transcript = transcript
    }

    func submit(_ handoff: PreparedEngineHandoff) async throws -> Data {
      submissionCount += 1
      snapshot = try HandoffSnapshot(handoff: handoff)
      return transcript
    }
  }

  private struct HandoffSnapshot: Sendable {
    let packageURL: URL
    let packageMode: mode_t
    let fileModes: [mode_t]
    let manifest: Data
    let request: Data
    let identity: Data
    let engine: Data
    let metadata: Data
    let payload: Data

    init(handoff: PreparedEngineHandoff) throws {
      packageURL = handoff.packageURL
      packageMode = try Self.mode(handoff.packageURL)
      let files = [
        handoff.manifestURL,
        handoff.requestURL,
        handoff.identityURL,
        handoff.engineURL,
        handoff.metadataURL,
        handoff.payloadURL,
      ]
      fileModes = try files.map(Self.mode)
      manifest = try Data(contentsOf: handoff.manifestURL)
      request = try Data(contentsOf: handoff.requestURL)
      identity = try Data(contentsOf: handoff.identityURL)
      engine = try Data(contentsOf: handoff.engineURL)
      metadata = try Data(contentsOf: handoff.metadataURL)
      payload = try Data(contentsOf: handoff.payloadURL)
    }

    private static func mode(_ url: URL) throws -> mode_t {
      var status = stat()
      guard lstat(url.path, &status) == 0 else {
        throw CocoaError(.fileReadUnknown)
      }
      return status.st_mode & 0o777
    }
  }

  private struct HandoffFixture {
    let root: URL
    let handoffDirectory: URL
    let request: ClosedEngineCandidateRequest
    let approval: CandidateBoundPlanApproval
    let assets: PreparedInstallerAssets
    let executionTranscript: Data
    let planDigest: String
    let engine: Data
    let metadata: Data
    let payload: Data
  }

  private struct HandoffTranscript {
    let planning: Data
    let execution: Data
    let planDigest: String
  }

  private func assertThrows<T>(
    _ expression: @autoclosure () async throws -> T,
    handler: (any Error) -> Void
  ) async {
    do {
      _ = try await expression()
      XCTFail("Expected expression to throw")
    } catch {
      handler(error)
    }
  }
#endif
