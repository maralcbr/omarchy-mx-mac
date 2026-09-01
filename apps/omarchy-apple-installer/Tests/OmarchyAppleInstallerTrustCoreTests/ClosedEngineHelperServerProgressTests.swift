#if os(macOS)
  import CryptoKit
  import Darwin
  import Foundation
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  /// End-to-end check of the advisory progress channel: a stub executor writes
  /// journal lines to the path the real executor derives, and the helper's
  /// tailer forwards them to the sink while the run is in flight.
  final class ClosedEngineHelperServerProgressTests: XCTestCase {
    func testProgressSinkReceivesJournalLinesInOrder() async throws {
      let fixture = try makeFixture()
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let source = try openDirectory(fixture.source)
      defer { try? source.close() }
      let sink = RecordingJournalSink()
      let executor = JournalWritingHandoffExecutor(
        transcript: fixture.transcript,
        lineDelay: .milliseconds(60)
      )
      let server = ClosedEngineHelperServer(
        workingDirectory: fixture.destination,
        executor: executor,
        credentialValidator: AcceptingProgressCredentialValidator()
      )

      let result = try await server.submit(
        packageDirectory: source,
        authorization: try machineOwnerAuthorization(),
        progress: sink
      )

      XCTAssertEqual(result, fixture.transcript)
      XCTAssertEqual(sink.text, String(decoding: fixture.transcript, as: UTF8.self))
      let journalURL = try XCTUnwrap(
        EngineJournalLocator.journalURL(
          workingDirectory: fixture.destination,
          bindingDigest: fixture.bindingDigest
        )
      )
      XCTAssertTrue(FileManager.default.fileExists(atPath: journalURL.path))
    }

    func testNilProgressKeepsExistingBehaviorAndForwardsNothing() async throws {
      let fixture = try makeFixture()
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let source = try openDirectory(fixture.source)
      defer { try? source.close() }
      let sink = RecordingJournalSink()
      let executor = JournalWritingHandoffExecutor(
        transcript: fixture.transcript,
        lineDelay: .milliseconds(0)
      )
      let server = ClosedEngineHelperServer(
        workingDirectory: fixture.destination,
        executor: executor,
        credentialValidator: AcceptingProgressCredentialValidator()
      )

      let result = try await server.submit(
        packageDirectory: source,
        authorization: try machineOwnerAuthorization()
      )

      XCTAssertEqual(result, fixture.transcript)
      XCTAssertTrue(sink.chunks.isEmpty)
    }

    func testFailedRunStillStopsTheTailer() async throws {
      let fixture = try makeFixture()
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let source = try openDirectory(fixture.source)
      defer { try? source.close() }
      let sink = RecordingJournalSink()
      let executor = JournalWritingHandoffExecutor(
        transcript: fixture.transcript,
        lineDelay: .milliseconds(0),
        failAfterWriting: true
      )
      let server = ClosedEngineHelperServer(
        workingDirectory: fixture.destination,
        executor: executor,
        credentialValidator: AcceptingProgressCredentialValidator()
      )

      do {
        _ = try await server.submit(
          packageDirectory: source,
          authorization: try machineOwnerAuthorization(),
          progress: sink
        )
        XCTFail("Expected the stub executor to fail the run")
      } catch {
        XCTAssertTrue(error is StubExecutorError)
      }

      // The advisory channel still delivered what the engine had written.
      XCTAssertEqual(sink.text, String(decoding: fixture.transcript, as: UTF8.self))
    }

    // MARK: Fixture

    private func makeFixture() throws -> ProgressFixture {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "omarchy-helper-progress-\(UUID().uuidString.lowercased())",
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
      try writePrivate(engine, to: source.appendingPathComponent("engine.tar.gz"))
      try writePrivate(
        metadata,
        to: source.appendingPathComponent("installer-data.json")
      )
      try writePrivate(
        payload,
        to: source.appendingPathComponent("omarchy.img.zst")
      )

      let layoutDigest = lengthPrefixedDigest(
        ["disk0", "free", "disk0s3", "447750000000", "107374182400"],
        prefix: "sha256:"
      )
      let requiredHumanSteps = [
        "enterOneTrueRecovery", "authenticateMachineOwner",
      ]
      let engineVersion = "v0.9.0-omarchy.1"
      let planDigest = lengthPrefixedDigest(
        [
          "apple,j314s", "disk0", layoutDigest, "free", "disk0s3",
          "447750000000", "107374182400", engineVersion,
          engineDigest, metadataDigest, payloadDigest,
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
        {"format":1,"operation":"install","plan_digest":"\(planDigest)","device_identifier":"apple,j314s","store_identifier":"disk0","layout_digest":"\(layoutDigest)","candidate_kind":"free","source_identifier":"disk0s3","offset_bytes":447750000000,"length_bytes":107374182400,"engine_version":"\(engineVersion)","required_human_steps":["enterOneTrueRecovery","authenticateMachineOwner"]}
        """.utf8
      )
      let identity = Data(
        """
        {"format":1,"binding_digest":"\(bindingDigest)","trust_root_fingerprint":"\(digest(Data("root".utf8)))","catalog_sequence":40,"catalog_payload_digest":"\(digest(Data("catalog".utf8)))","plan_digest":"\(planDigest)","engine_digest":"\(engineDigest)","metadata_digest":"\(metadataDigest)","payload_digest":"\(payloadDigest)"}
        """.utf8
      )
      try writePrivate(manifest, to: source.appendingPathComponent("manifest.json"))
      try writePrivate(request, to: source.appendingPathComponent("request.json"))
      try writePrivate(identity, to: source.appendingPathComponent("identity.json"))

      let lines = [
        #"{"schema_version":1,"sequence":1,"type":"inspection","payload":{"device_identifier":"apple,j314s","support":"supported"}}"#,
        #"{"schema_version":1,"sequence":2,"type":"inventory","payload":{"layout_digest":"\#(layoutDigest)","system_store_identifier":"disk0","candidates":[{"kind":"free","source_identifier":"disk0s3","offset_bytes":447750000000,"length_bytes":107374182400,"minimum_install_bytes":67501226240,"minimum_container_bytes":0}]}}"#,
        #"{"schema_version":1,"sequence":3,"type":"plan","payload":{"plan_digest":"\#(planDigest)","device_identifier":"apple,j314s","store_identifier":"disk0","layout_digest":"\#(layoutDigest)","candidate_kind":"free","source_identifier":"disk0s3","offset_bytes":447750000000,"length_bytes":107374182400,"engine_version":"\#(engineVersion)","engine_digest":"\#(engineDigest)","metadata_digest":"\#(metadataDigest)","payload_digest":"\#(payloadDigest)","required_human_steps":["enterOneTrueRecovery","authenticateMachineOwner"]}}"#,
        #"{"schema_version":1,"sequence":4,"type":"completion","payload":{"plan_digest":"\#(planDigest)","outcome":"awaiting_recovery"}}"#,
      ]
      let transcript = Data((lines.joined(separator: "\n") + "\n").utf8)
      return ProgressFixture(
        root: root,
        source: source,
        destination: destination,
        transcript: transcript,
        bindingDigest: bindingDigest
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

    private func digest(_ data: Data) -> String {
      "sha256:"
        + SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
    }

    private func machineOwnerAuthorization() throws -> MachineOwnerAuthorization {
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

  private enum StubExecutorError: Error {
    case stopped
  }

  /// Writes the transcript to the journal path the real executor derives, one
  /// line at a time, then returns it as the sealed reply.
  private actor JournalWritingHandoffExecutor: ImportedEngineHandoffExecuting {
    private let transcript: Data
    private let lineDelay: Duration
    private let failAfterWriting: Bool

    init(
      transcript: Data,
      lineDelay: Duration,
      failAfterWriting: Bool = false
    ) {
      self.transcript = transcript
      self.lineDelay = lineDelay
      self.failAfterWriting = failAfterWriting
    }

    func execute(
      _ package: ImportedEngineHandoffPackage,
      authorization: MachineOwnerAuthorization,
      operation: EngineHandoffOperation
    ) async throws -> Data {
      let workingDirectory = package.packageURL.deletingLastPathComponent()
      guard
        let journal = EngineJournalLocator.journalURL(
          workingDirectory: workingDirectory,
          bindingDigest: package.bindingDigest
        )
      else {
        throw StubExecutorError.stopped
      }
      try FileManager.default.createDirectory(
        at: journal.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      FileManager.default.createFile(
        atPath: journal.path,
        contents: nil,
        attributes: [.posixPermissions: 0o600]
      )
      let handle = try FileHandle(forWritingTo: journal)
      defer { try? handle.close() }

      for line in Self.lines(in: transcript) {
        try handle.write(contentsOf: line)
        try handle.synchronize()
        if lineDelay > .zero {
          try? await Task.sleep(for: lineDelay)
        }
      }
      if failAfterWriting {
        throw StubExecutorError.stopped
      }
      return transcript
    }

    private static func lines(in data: Data) -> [Data] {
      var result = [Data]()
      var start = data.startIndex
      while let newline = data[start...].firstIndex(of: 0x0A) {
        result.append(Data(data[start...newline]))
        start = data.index(after: newline)
      }
      return result
    }
  }

  private struct AcceptingProgressCredentialValidator:
    MachineOwnerCredentialValidating
  {
    func validate(_ authorization: MachineOwnerAuthorization) throws {}
  }

  private struct ProgressFixture {
    let root: URL
    let source: URL
    let destination: URL
    let transcript: Data
    let bindingDigest: String
  }
#endif
