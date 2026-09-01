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
        submitter: submitter,
        authorization: try machineOwnerAuthorization()
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
            submitter: submitter,
            authorization: try machineOwnerAuthorization()
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

    func testRepairInvocationCarriesSignedManifestThroughHandoff() async throws {
      let fixture = try makeFixture(repair: true)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let submitter = RecordingHandoffSubmitter(
        transcript: fixture.executionTranscript
      )

      _ = try await ClosedEngineProcessAdapter().execute(
        fixture.request,
        approval: fixture.approval,
        authorization: GrantedEngineAuthorization(),
        process: ClosedEngineHandoffProcess(
          assets: fixture.assets,
          handoffDirectory: fixture.handoffDirectory,
          submitter: submitter,
          authorization: try machineOwnerAuthorization()
        )
      )

      let recordedSnapshot = await submitter.snapshot
      let snapshot = try XCTUnwrap(recordedSnapshot)
      let repairManifest = try XCTUnwrap(fixture.repairManifest)
      XCTAssertEqual(snapshot.repairManifest, repairManifest)
      let request = try XCTUnwrap(
        try JSONSerialization.jsonObject(with: snapshot.request)
          as? [String: Any]
      )
      XCTAssertEqual(request["operation"] as? String, "repair-installed-system")
      let identity = try XCTUnwrap(
        try JSONSerialization.jsonObject(with: snapshot.identity)
          as? [String: Any]
      )
      XCTAssertEqual(
        identity["repair_manifest_digest"] as? String,
        fixture.assets.installer.repairManifestDigest
      )
      let manifest = try XCTUnwrap(
        try JSONSerialization.jsonObject(with: snapshot.manifest)
          as? [String: Any]
      )
      XCTAssertNotNil(manifest["repair_manifest"])
    }

    func testReplaceInvocationRunsUnderInstallOperationWithoutManifest()
      async throws
    {
      let fixture = try makeFixture(replace: true)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let submitter = RecordingHandoffSubmitter(
        transcript: fixture.executionTranscript
      )

      let result = try await ClosedEngineProcessAdapter().execute(
        fixture.request,
        approval: fixture.approval,
        authorization: GrantedEngineAuthorization(),
        process: ClosedEngineHandoffProcess(
          assets: fixture.assets,
          handoffDirectory: fixture.handoffDirectory,
          submitter: submitter,
          authorization: try machineOwnerAuthorization()
        )
      )

      XCTAssertEqual(result.completion, .awaitingRecovery)
      let recordedSnapshot = await submitter.snapshot
      let snapshot = try XCTUnwrap(recordedSnapshot)
      XCTAssertNil(snapshot.repairManifest)
      let request = try XCTUnwrap(
        try JSONSerialization.jsonObject(with: snapshot.request)
          as? [String: Any]
      )
      XCTAssertEqual(request["operation"] as? String, "install")
      XCTAssertEqual(request["candidate_kind"] as? String, "replace")
      let identity = try XCTUnwrap(
        try JSONSerialization.jsonObject(with: snapshot.identity)
          as? [String: Any]
      )
      XCTAssertNil(identity["repair_manifest_digest"])
      let manifest = try XCTUnwrap(
        try JSONSerialization.jsonObject(with: snapshot.manifest)
          as? [String: Any]
      )
      XCTAssertNil(manifest["repair_manifest"])
    }

    func testReplacePlanWithRepairManifestAssetStopsBeforeSubmission()
      async throws
    {
      let fixture = try makeFixture(
        replace: true,
        strayRepairManifestAsset: true
      )
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
            submitter: submitter,
            authorization: try machineOwnerAuthorization()
          )
        )
      ) {
        XCTAssertEqual(
          $0 as? ClosedEngineHandoffError,
          .assetBindingMismatch
        )
      }
      let submissionCount = await submitter.submissionCount
      XCTAssertEqual(submissionCount, 0)
    }

    func testRecoveryRetryPreservesInstallRequestAndSelectsRetryOperation()
      async throws
    {
      let fixture = try makeFixture()
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let submitter = RecordingHandoffSubmitter(
        transcript: fixture.executionTranscript
      )
      let process = ClosedEngineHandoffProcess(
        assets: fixture.assets,
        handoffDirectory: fixture.handoffDirectory,
        submitter: submitter,
        authorization: try machineOwnerAuthorization(),
        operation: .retryRecoveryAuthorization
      )

      _ = try await ClosedEngineProcessAdapter().execute(
        fixture.request,
        approval: fixture.approval,
        authorization: GrantedEngineAuthorization(),
        process: process
      )

      let operation = await submitter.operation
      let recordedSnapshot = await submitter.snapshot
      let snapshot = try XCTUnwrap(recordedSnapshot)
      let request = try XCTUnwrap(
        try JSONSerialization.jsonObject(with: snapshot.request)
          as? [String: Any]
      )
      XCTAssertEqual(operation, .retryRecoveryAuthorization)
      XCTAssertEqual(request["operation"] as? String, "install")
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
            submitter: submitter,
            authorization: try machineOwnerAuthorization()
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
      symlinkPayload: Bool = false,
      repair: Bool = false,
      replace: Bool = false,
      strayRepairManifestAsset: Bool = false
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
      let repairManifest = Data("{\"operation\":\"repair-installed-system\"}".utf8)
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
      let repairArtifact = try artifact(
        role: "repair-manifest",
        name: "repair.json",
        data: repairManifest
      )
      let engineURL = root.appendingPathComponent(engineArtifact.fileName)
      let metadataURL = root.appendingPathComponent(metadataArtifact.fileName)
      let payloadURL = root.appendingPathComponent(payloadArtifact.fileName)
      let repairURL = root.appendingPathComponent(repairArtifact.fileName)
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
      if repair || strayRepairManifestAsset {
        try writePrivate(repairManifest, to: repairURL)
      }

      let delivery = PinnedInstallerDelivery(
        engine: engineArtifact,
        metadata: metadataArtifact,
        payload: payloadArtifact,
        repairManifest: repair ? repairArtifact : nil
      )
      let record = PinnedInstallerRecord(
        deviceIdentifier: "apple,j314s",
        operation: repair ? "repair-installed-system" : "install",
        asahiInstallerTag: "v0.9.0",
        asahiInstallerRevision: String(repeating: "a", count: 40),
        asahiInstallerDataRevision: String(repeating: "b", count: 40),
        downstreamRevision: String(repeating: "c", count: 40),
        engineVersion: "v0.9.0-omarchy.2",
        engineDigest: engineArtifact.expectedDigest,
        metadataDigest: metadataArtifact.expectedDigest,
        payloadDigest: payloadArtifact.expectedDigest,
        repairManifestDigest: repair ? repairArtifact.expectedDigest : nil,
        evidenceRevision: "evidence-handoff",
        delivery: delivery
      )
      let catalog = catalogPayload(
        record: record,
        engine: engineArtifact,
        metadata: metadataArtifact,
        payload: payloadArtifact,
        repairManifest: repair ? repairArtifact : nil
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
        candidateKind: repair ? "repair" : replace ? "replace" : "free",
        engineDigest: record.engineDigest,
        metadataDigest: record.metadataDigest,
        payloadDigest: record.payloadDigest,
        repairManifestDigest: record.repairManifestDigest
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
        ),
        repairManifest: repair || strayRepairManifestAsset
          ? StagedInstallerArtifact(
            artifact: repairArtifact,
            fileURL: repairURL,
            reusedExistingFile: false
          )
          : nil
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
        payload: payload,
        repairManifest: repair ? repairManifest : nil
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
      payload: PinnedInstallerArtifact,
      repairManifest: PinnedInstallerArtifact?
    ) -> Data {
      let issued = ISO8601DateFormatter().string(
        from: now.addingTimeInterval(-3_600)
      )
      let expires = ISO8601DateFormatter().string(
        from: now.addingTimeInterval(86_400)
      )
      let schemaVersion = repairManifest == nil ? 2 : 3
      let operation =
        repairManifest == nil
        ? ""
        : ",\"operation\":\"repair-installed-system\""
      let repairFields =
        repairManifest.map {
          ",\"repairManifestDigest\":\"\($0.expectedDigest)\",\"repairManifestArtifact\":{\"sourceURL\":\"\($0.sourceURL.absoluteString)\",\"fileName\":\"\($0.fileName)\",\"sizeBytes\":\($0.expectedSizeBytes)}"
        } ?? ""
      let catalog = Data(
        """
        {"schemaVersion":\(schemaVersion),"sequence":40,"issuedAt":"\(issued)","expiresAt":"\(expires)","models":[{"deviceIdentifier":"\(record.deviceIdentifier)","status":"enabled"\(operation),"asahiInstallerTag":"\(record.asahiInstallerTag)","asahiInstallerRevision":"\(record.asahiInstallerRevision)","asahiInstallerDataRevision":"\(record.asahiInstallerDataRevision)","downstreamRevision":"\(record.downstreamRevision)","engineDigest":"\(record.engineDigest)","metadataDigest":"\(record.metadataDigest)","payloadDigest":"\(record.payloadDigest)"\(repairFields),"evidenceRevision":"\(record.evidenceRevision)","engineArtifact":{"sourceURL":"\(engine.sourceURL.absoluteString)","fileName":"\(engine.fileName)","sizeBytes":\(engine.expectedSizeBytes)},"metadataArtifact":{"sourceURL":"\(metadata.sourceURL.absoluteString)","fileName":"\(metadata.fileName)","sizeBytes":\(metadata.expectedSizeBytes)},"payloadArtifact":{"sourceURL":"\(payload.sourceURL.absoluteString)","fileName":"\(payload.fileName)","sizeBytes":\(payload.expectedSizeBytes)}}]}
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
      candidateKind: String,
      engineDigest: String,
      metadataDigest: String,
      payloadDigest: String,
      repairManifestDigest: String?
    ) -> HandoffTranscript {
      let identityDigest = "sha256:" + String(repeating: "9", count: 64)
      let identityBoundKind = ["repair", "replace"].contains(candidateKind)
      var layoutFields = ["disk0", candidateKind, "disk0s3", "2000", "1000"]
      if identityBoundKind {
        layoutFields.append(identityDigest)
      }
      let layoutDigest = lengthPrefixedDigest(layoutFields, prefix: "sha256:")
      let humanSteps = [
        "enterOneTrueRecovery",
        "authenticateMachineOwner",
      ]
      var planFields = [
        "apple,j314s", "disk0", layoutDigest, candidateKind, "disk0s3",
        "2000", "1000", "v0.9.0-omarchy.2", engineDigest,
        metadataDigest, payloadDigest,
      ]
      if let repairManifestDigest {
        planFields.append(repairManifestDigest)
      }
      planFields.append(humanSteps.joined(separator: ","))
      let planDigest = lengthPrefixedDigest(
        planFields,
        prefix: ""
      )
      let identityInventoryField =
        identityBoundKind
        ? ",\"identity_digest\":\"\(identityDigest)\""
        : ""
      let repairPlanField =
        repairManifestDigest.map {
          ",\"repair_manifest_digest\":\"\($0)\""
        } ?? ""
      let minimumInstallBytes =
        candidateKind == "repair" ? 1000 : candidateKind == "replace" ? 800 : 100
      let records = [
        #"{"schema_version":1,"sequence":1,"type":"inspection","payload":{"device_identifier":"apple,j314s","support":"supported"}}"#,
        #"{"schema_version":1,"sequence":2,"type":"inventory","payload":{"layout_digest":"\#(layoutDigest)","system_store_identifier":"disk0","candidates":[{"kind":"\#(candidateKind)","source_identifier":"disk0s3","offset_bytes":2000,"length_bytes":1000,"minimum_install_bytes":\#(minimumInstallBytes),"minimum_container_bytes":0\#(identityInventoryField)}]}}"#,
        #"{"schema_version":1,"sequence":3,"type":"plan","payload":{"plan_digest":"\#(planDigest)","device_identifier":"apple,j314s","store_identifier":"disk0","layout_digest":"\#(layoutDigest)","candidate_kind":"\#(candidateKind)","source_identifier":"disk0s3","offset_bytes":2000,"length_bytes":1000,"engine_version":"v0.9.0-omarchy.2","engine_digest":"\#(engineDigest)","metadata_digest":"\#(metadataDigest)","payload_digest":"\#(payloadDigest)"\#(repairPlanField),"required_human_steps":["enterOneTrueRecovery","authenticateMachineOwner"]}}"#,
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

    private func machineOwnerAuthorization() throws
      -> MachineOwnerAuthorization
    {
      try MachineOwnerAuthorization(
        username: "mina",
        password: Data("owner-password".utf8)
      )
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
    private(set) var operation: EngineHandoffOperation?

    init(transcript: Data) {
      self.transcript = transcript
    }

    func submit(
      _ handoff: PreparedEngineHandoff,
      authorization: MachineOwnerAuthorization,
      operation: EngineHandoffOperation
    ) async throws -> Data {
      submissionCount += 1
      self.operation = operation
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
    let repairManifest: Data?

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
      repairManifest = try handoff.repairManifestURL.map {
        try Data(contentsOf: $0)
      }
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
    let repairManifest: Data?
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
