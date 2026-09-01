#if os(macOS)
  import CryptoKit
  import Darwin
  import Foundation
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  final class ClosedEngineHelperServerTests: XCTestCase {
    func testValidPackageExecutesAndImportedCopyIsRemoved() async throws {
      let fixture = try makeFixture()
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let source = try openDirectory(fixture.source)
      defer { try? source.close() }
      let executor = RecordingHandoffExecutor(result: fixture.transcript)
      let server = ClosedEngineHelperServer(
        workingDirectory: fixture.destination,
        executor: executor,
        credentialValidator: AcceptingMachineOwnerCredentialValidator()
      )

      let result = try await server.submit(
        packageDirectory: source,
        authorization: try machineOwnerAuthorization()
      )
      let executionCount = await executor.executionCount

      XCTAssertEqual(result, fixture.transcript)
      XCTAssertEqual(executionCount, 1)
      XCTAssertTrue(try importedEntries(in: fixture.destination).isEmpty)
    }

    func testM4PackageIsRejectedBeforeExecution() async throws {
      let fixture = try makeFixture(deviceIdentifier: "apple,j614s")
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let source = try openDirectory(fixture.source)
      defer { try? source.close() }
      let executor = RecordingHandoffExecutor(result: fixture.transcript)
      let server = ClosedEngineHelperServer(
        workingDirectory: fixture.destination,
        executor: executor,
        credentialValidator: AcceptingMachineOwnerCredentialValidator()
      )

      await assertThrowsErrorAsync(
        try await server.submit(
          packageDirectory: source,
          authorization: try machineOwnerAuthorization()
        )
      ) {
        XCTAssertEqual(
          $0 as? ClosedEngineHelperError,
          .unsupportedDevice("apple,j614s")
        )
      }
      let executionCount = await executor.executionCount
      XCTAssertEqual(executionCount, 0)
      XCTAssertTrue(try importedEntries(in: fixture.destination).isEmpty)
    }

    func testTranscriptForSubstitutedPlanIsRejected() async throws {
      let fixture = try makeFixture(
        transcriptPlanMismatch: true
      )
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let source = try openDirectory(fixture.source)
      defer { try? source.close() }
      let executor = RecordingHandoffExecutor(result: fixture.transcript)
      let server = ClosedEngineHelperServer(
        workingDirectory: fixture.destination,
        executor: executor,
        credentialValidator: AcceptingMachineOwnerCredentialValidator()
      )

      await assertThrowsErrorAsync(
        try await server.submit(
          packageDirectory: source,
          authorization: try machineOwnerAuthorization()
        )
      ) {
        XCTAssertEqual(
          $0 as? ClosedEngineHelperError,
          .transcriptPlanMismatch
        )
      }
      XCTAssertTrue(try importedEntries(in: fixture.destination).isEmpty)
    }

    func testTranscriptWithoutCompletionIsRejected() async throws {
      let fixture = try makeFixture(includeCompletion: false)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let source = try openDirectory(fixture.source)
      defer { try? source.close() }
      let executor = RecordingHandoffExecutor(result: fixture.transcript)
      let server = ClosedEngineHelperServer(
        workingDirectory: fixture.destination,
        executor: executor,
        credentialValidator: AcceptingMachineOwnerCredentialValidator()
      )

      await assertThrowsErrorAsync(
        try await server.submit(
          packageDirectory: source,
          authorization: try machineOwnerAuthorization()
        )
      ) {
        XCTAssertEqual(
          $0 as? ClosedEngineHelperError,
          .transcriptIncomplete
        )
      }
      XCTAssertTrue(try importedEntries(in: fixture.destination).isEmpty)
    }

    func testRejectedCredentialCannotReachEngineOrImportedState() async throws {
      let fixture = try makeFixture()
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let source = try openDirectory(fixture.source)
      defer { try? source.close() }
      let executor = RecordingHandoffExecutor(result: fixture.transcript)
      let server = ClosedEngineHelperServer(
        workingDirectory: fixture.destination,
        executor: executor,
        credentialValidator: RejectingMachineOwnerCredentialValidator()
      )

      await assertThrowsErrorAsync(
        try await server.submit(
          packageDirectory: source,
          authorization: try machineOwnerAuthorization()
        )
      ) {
        XCTAssertEqual(
          $0 as? ClosedEngineHelperError,
          .invalidMachineOwnerCredentials
        )
      }
      let executionCount = await executor.executionCount
      XCTAssertEqual(executionCount, 0)
      XCTAssertTrue(try importedEntries(in: fixture.destination).isEmpty)
    }

    private func makeFixture(
      deviceIdentifier: String = "apple,j314s",
      transcriptPlanMismatch: Bool = false,
      includeCompletion: Bool = true
    ) throws -> HelperServerFixture {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "omarchy-helper-server-\(UUID().uuidString.lowercased())",
        isDirectory: true
      )
      let source = root.appendingPathComponent("source", isDirectory: true)
      let destination = root.appendingPathComponent(
        "destination",
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: source,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try FileManager.default.createDirectory(
        at: destination,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )

      let engine = Data("engine-a".utf8)
      let metadata = Data("metadata".utf8)
      let payload = Data("payload-a".utf8)
      let engineDigest = digest(engine)
      let metadataDigest = digest(metadata)
      let payloadDigest = digest(payload)
      try writePrivate(
        engine,
        to: source.appendingPathComponent("engine.tar.gz")
      )
      try writePrivate(
        metadata,
        to: source.appendingPathComponent("installer-data.json")
      )
      try writePrivate(
        payload,
        to: source.appendingPathComponent("omarchy.img.zst")
      )

      let layoutDigest = lengthPrefixedDigest(
        [
          "disk0", "free", "disk0s3", "447750000000", "107374182400",
        ],
        prefix: "sha256:"
      )
      let requiredHumanSteps = [
        "enterOneTrueRecovery",
        "authenticateMachineOwner",
      ]
      let engineVersion = "v0.9.0-omarchy.1"
      let requestPlanDigest = lengthPrefixedDigest(
        [
          deviceIdentifier, "disk0", layoutDigest, "free", "disk0s3",
          "447750000000", "107374182400", engineVersion,
          engineDigest, metadataDigest, payloadDigest,
          requiredHumanSteps.joined(separator: ","),
        ],
        prefix: ""
      )
      let transcriptEngineDigest =
        transcriptPlanMismatch
        ? "sha256:" + String(repeating: "d", count: 64)
        : engineDigest
      let transcriptMetadataDigest =
        transcriptPlanMismatch
        ? "sha256:" + String(repeating: "e", count: 64)
        : metadataDigest
      let transcriptPayloadDigest =
        transcriptPlanMismatch
        ? "sha256:" + String(repeating: "f", count: 64)
        : payloadDigest
      let transcriptPlanDigest = lengthPrefixedDigest(
        [
          "apple,j314s", "disk0", layoutDigest, "free", "disk0s3",
          "447750000000", "107374182400", engineVersion,
          transcriptEngineDigest, transcriptMetadataDigest,
          transcriptPayloadDigest,
          requiredHumanSteps.joined(separator: ","),
        ],
        prefix: ""
      )
      let bindingDigest = digest(Data("binding".utf8))
      let manifest = Data(
        """
        {"format":1,"binding_digest":"\(bindingDigest)","request_file":"request.json","identity_file":"identity.json","engine":{"file_name":"engine.tar.gz","digest":"\(engineDigest)","size_bytes":\(engine.count)},"metadata":{"file_name":"installer-data.json","digest":"\(metadataDigest)","size_bytes":\(metadata.count)},"payload":{"file_name":"omarchy.img.zst","digest":"\(payloadDigest)","size_bytes":\(payload.count)}}
        """.utf8
      )
      let request = Data(
        """
        {"format":1,"operation":"install","plan_digest":"\(requestPlanDigest)","device_identifier":"\(deviceIdentifier)","store_identifier":"disk0","layout_digest":"\(layoutDigest)","candidate_kind":"free","source_identifier":"disk0s3","offset_bytes":447750000000,"length_bytes":107374182400,"engine_version":"\(engineVersion)","required_human_steps":["enterOneTrueRecovery","authenticateMachineOwner"]}
        """.utf8
      )
      let identity = Data(
        """
        {"format":1,"binding_digest":"\(bindingDigest)","trust_root_fingerprint":"\(digest(Data("root".utf8)))","catalog_sequence":40,"catalog_payload_digest":"\(digest(Data("catalog".utf8)))","plan_digest":"\(requestPlanDigest)","engine_digest":"\(engineDigest)","metadata_digest":"\(metadataDigest)","payload_digest":"\(payloadDigest)"}
        """.utf8
      )
      try writePrivate(
        manifest,
        to: source.appendingPathComponent("manifest.json")
      )
      try writePrivate(
        request,
        to: source.appendingPathComponent("request.json")
      )
      try writePrivate(
        identity,
        to: source.appendingPathComponent("identity.json")
      )

      var lines = [
        #"{"schema_version":1,"sequence":1,"type":"inspection","payload":{"device_identifier":"apple,j314s","support":"supported"}}"#,
        #"{"schema_version":1,"sequence":2,"type":"inventory","payload":{"layout_digest":"\#(layoutDigest)","system_store_identifier":"disk0","candidates":[{"kind":"free","source_identifier":"disk0s3","offset_bytes":447750000000,"length_bytes":107374182400,"minimum_install_bytes":67501226240,"minimum_container_bytes":0}]}}"#,
        #"{"schema_version":1,"sequence":3,"type":"plan","payload":{"plan_digest":"\#(transcriptPlanDigest)","device_identifier":"apple,j314s","store_identifier":"disk0","layout_digest":"\#(layoutDigest)","candidate_kind":"free","source_identifier":"disk0s3","offset_bytes":447750000000,"length_bytes":107374182400,"engine_version":"\#(engineVersion)","engine_digest":"\#(transcriptEngineDigest)","metadata_digest":"\#(transcriptMetadataDigest)","payload_digest":"\#(transcriptPayloadDigest)","required_human_steps":["enterOneTrueRecovery","authenticateMachineOwner"]}}"#,
      ]
      if includeCompletion {
        lines.append(
          #"{"schema_version":1,"sequence":4,"type":"completion","payload":{"plan_digest":"\#(transcriptPlanDigest)","outcome":"awaiting_recovery"}}"#
        )
      }
      let transcript = Data((lines.joined(separator: "\n") + "\n").utf8)
      return HelperServerFixture(
        root: root,
        source: source,
        destination: destination,
        transcript: transcript
      )
    }

    private func openDirectory(_ url: URL) throws -> FileHandle {
      let descriptor = Darwin.open(
        url.path,
        O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
      )
      guard descriptor >= 0 else {
        throw CocoaError(.fileReadUnknown)
      }
      return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
      try data.write(to: url, options: .withoutOverwriting)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o400],
        ofItemAtPath: url.path
      )
    }

    private func importedEntries(in directory: URL) throws -> [URL] {
      try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
      )
    }

    private func digest(_ data: Data) -> String {
      "sha256:"
        + SHA256.hash(data: data)
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

    private func lengthPrefixedDigest(
      _ fields: [String],
      prefix: String
    ) -> String {
      let canonical =
        fields
        .map { "\($0.utf8.count):\($0)" }
        .joined(separator: "|")
      let value = SHA256.hash(data: Data(canonical.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
      return prefix + value
    }
  }

  private actor RecordingHandoffExecutor: ImportedEngineHandoffExecuting {
    private(set) var executionCount = 0
    private let result: Data

    init(result: Data) {
      self.result = result
    }

    func execute(
      _ package: ImportedEngineHandoffPackage,
      authorization: MachineOwnerAuthorization,
      operation: EngineHandoffOperation
    ) async throws -> Data {
      executionCount += 1
      return result
    }
  }

  private struct AcceptingMachineOwnerCredentialValidator:
    MachineOwnerCredentialValidating
  {
    func validate(_ authorization: MachineOwnerAuthorization) throws {}
  }

  private struct RejectingMachineOwnerCredentialValidator:
    MachineOwnerCredentialValidating
  {
    func validate(_ authorization: MachineOwnerAuthorization) throws {
      throw MachineOwnerCredentialValidationError.rejected
    }
  }

  private struct HelperServerFixture {
    let root: URL
    let source: URL
    let destination: URL
    let transcript: Data
  }

  private func assertThrowsErrorAsync<T>(
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
#endif
