#if os(macOS)
  import CryptoKit
  import Foundation
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  final class PinnedAsahiEngineExecutorTests: XCTestCase {
    func testVerifiedReadOnlyInspectionRunsWithoutRootAndCleansExecutionRoot()
      async throws
    {
      let transcript = Data(
        """
        {"schema_version":1,"sequence":1,"type":"inspection","payload":{"device_identifier":"apple,j614s","support":"unsupported"}}

        """.utf8
      )
      let fixture = try makeFixture(transcript: transcript)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let scratch = fixture.root.appendingPathComponent(
        "inspection-scratch",
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: scratch,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      let archive = try PinnedAsahiEngineArchive(
        fileURL: fixture.package.engineURL,
        expectedDigest: try digest(of: fixture.package.engineURL),
        expectedSizeBytes: try size(of: fixture.package.engineURL)
      )
      let executor = PinnedAsahiEngineExecutor(effectiveUserID: { 501 })

      let result = try await executor.inspect(archive, in: scratch)

      XCTAssertEqual(result, transcript)
      XCTAssertTrue(try executionEntries(in: scratch).isEmpty)
    }

    func testReadOnlyInspectionRejectsChangedArchiveDigest() async throws {
      let fixture = try makeFixture()
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let scratch = fixture.root.appendingPathComponent(
        "inspection-scratch",
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: scratch,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      let archive = try PinnedAsahiEngineArchive(
        fileURL: fixture.package.engineURL,
        expectedDigest: "sha256:" + String(repeating: "0", count: 64),
        expectedSizeBytes: try size(of: fixture.package.engineURL)
      )
      let executor = PinnedAsahiEngineExecutor(effectiveUserID: { 501 })

      await assertThrowsErrorAsync(
        try await executor.inspect(archive, in: scratch)
      ) {
        XCTAssertEqual(
          $0 as? PinnedAsahiEngineExecutionError,
          .archiveDigestMismatch
        )
      }
      XCTAssertTrue(try executionEntries(in: scratch).isEmpty)
    }

    func testVerifiedPlanReceivesPrivateInputsAndCleansAllTemporaryState()
      async throws
    {
      let fixture = try makeFixture()
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let scratch = fixture.root.appendingPathComponent(
        "planning-scratch",
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: scratch,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      let archive = try PinnedAsahiEngineArchive(
        fileURL: fixture.package.engineURL,
        expectedDigest: try digest(of: fixture.package.engineURL),
        expectedSizeBytes: try size(of: fixture.package.engineURL)
      )
      let candidate = ValidatedEngineCandidate(
        kind: "free",
        sourceIdentifier: "disk0s3",
        offsetBytes: 128 * 1_048_576,
        lengthBytes: 128 * 1_048_576,
        minimumInstallBytes: 64 * 1_048_576,
        minimumContainerBytes: 0
      )
      let request = try PinnedAsahiPlanRequest(
        inventory: ValidatedEngineInventory(
          layoutDigest: "sha256:" + String(repeating: "c", count: 64),
          systemStoreIdentifier: "disk0",
          candidates: [candidate]
        ),
        candidate: candidate,
        requestedLengthBytes: 96 * 1_048_576
      )
      let identity = try PinnedAsahiPlanIdentity(
        engineVersion: "v0.9.0-omarchy.2",
        engineDigest: "sha256:" + String(repeating: "d", count: 64),
        metadataDigest: "sha256:" + String(repeating: "e", count: 64),
        payloadDigest: "sha256:" + String(repeating: "f", count: 64)
      )
      let executor = PinnedAsahiEngineExecutor(effectiveUserID: { 501 })

      let result = try await executor.plan(
        archive,
        request: request,
        identity: identity,
        in: scratch
      )

      XCTAssertEqual(result, fixture.transcript)
      XCTAssertTrue(try executionEntries(in: scratch).isEmpty)
      XCTAssertTrue(try planningInputEntries(in: scratch).isEmpty)
    }

    func testNonRootExecutionIsRejectedBeforeArchiveAccess() async throws {
      let package = importedPackage(
        at: URL(fileURLWithPath: "/does-not-exist")
      )
      let executor = PinnedAsahiEngineExecutor(effectiveUserID: { 501 })

      await assertThrowsErrorAsync(
        try await executor.execute(
          package,
          authorization: try machineOwnerAuthorization()
        )
      ) {
        XCTAssertEqual(
          $0 as? PinnedAsahiEngineExecutionError,
          .privilegeRequired
        )
      }
    }

    func testValidPinnedBundleReceivesBoundInputsAndCleansExecutionRoot()
      async throws
    {
      let fixture = try makeFixture()
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let executor = PinnedAsahiEngineExecutor(effectiveUserID: { 0 })

      let transcript = try await executor.execute(
        fixture.package,
        authorization: try machineOwnerAuthorization()
      )

      XCTAssertEqual(transcript, fixture.transcript)
      XCTAssertTrue(try executionEntries(in: fixture.root).isEmpty)
      let journals = try journalEntries(in: fixture.root)
      XCTAssertEqual(journals.count, 1)
      XCTAssertEqual(try Data(contentsOf: journals[0]), fixture.transcript)
    }

    func testRecoveryRetryUsesDedicatedEngineMode() async throws {
      let fixture = try makeFixture(
        expectedInstallMode: "retry-recovery-authorization"
      )
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let executor = PinnedAsahiEngineExecutor(effectiveUserID: { 0 })

      let transcript = try await executor.execute(
        fixture.package,
        authorization: try machineOwnerAuthorization(),
        operation: .retryRecoveryAuthorization
      )

      XCTAssertEqual(transcript, fixture.transcript)
      XCTAssertTrue(try executionEntries(in: fixture.root).isEmpty)
    }

    func testRepairExecutionReceivesImportedRepairManifest() async throws {
      let fixture = try makeFixture(
        repairManifest: Data("{\"operation\":\"repair-installed-system\"}".utf8)
      )
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let executor = PinnedAsahiEngineExecutor(effectiveUserID: { 0 })

      let transcript = try await executor.execute(
        fixture.package,
        authorization: try machineOwnerAuthorization()
      )

      XCTAssertEqual(transcript, fixture.transcript)
    }

    func testRootStyleExtractionNormalizesGroupWritableArchiveModes()
      async throws
    {
      let fixture = try makeFixture(groupWritableBundleEntry: true)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let executor = PinnedAsahiEngineExecutor(
        effectiveUserID: { 0 },
        extractionOptions: ["--preserve-permissions"]
      )

      let transcript = try await executor.execute(
        fixture.package,
        authorization: try machineOwnerAuthorization()
      )

      XCTAssertEqual(transcript, fixture.transcript)
      XCTAssertTrue(try executionEntries(in: fixture.root).isEmpty)
    }

    func testEscapingBundleSymlinkIsRejected() async throws {
      let fixture = try makeFixture(escapingSymlink: true)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let executor = PinnedAsahiEngineExecutor(effectiveUserID: { 0 })

      await assertThrowsErrorAsync(
        try await executor.execute(
          fixture.package,
          authorization: try machineOwnerAuthorization()
        )
      ) {
        XCTAssertEqual(
          $0 as? PinnedAsahiEngineExecutionError,
          .invalidBundle
        )
      }
      XCTAssertTrue(try executionEntries(in: fixture.root).isEmpty)
    }

    func testNonzeroEngineExitIsRejectedAndExecutionRootIsCleaned()
      async throws
    {
      let fixture = try makeFixture(exitCode: 17)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let executor = PinnedAsahiEngineExecutor(effectiveUserID: { 0 })

      await assertThrowsErrorAsync(
        try await executor.execute(
          fixture.package,
          authorization: try machineOwnerAuthorization()
        )
      ) {
        XCTAssertEqual(
          $0 as? PinnedAsahiEngineExecutionError,
          .engineExited(17)
        )
      }
      XCTAssertTrue(try executionEntries(in: fixture.root).isEmpty)
      XCTAssertEqual(try journalEntries(in: fixture.root).count, 1)
    }

    func testRecoveryAuthorizationFailureRequiresExactRetryCheckpoint()
      async throws
    {
      let targetEvidence = Data("target-readback".utf8)
      let installedEvidence = Data("installed-readback".utf8)
      let transcript = recoveryRetryTranscript(
        targetEvidence: targetEvidence,
        installedEvidence: installedEvidence
      )
      let fixture = try makeFixture(
        exitCode: 17,
        transcript: transcript,
        checkpointEvidence: [
          "apfs-target-prepared": targetEvidence,
          "stub-and-esp-installed": installedEvidence,
        ]
      )
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let executor = PinnedAsahiEngineExecutor(effectiveUserID: { 0 })

      await assertThrowsErrorAsync(
        try await executor.execute(
          fixture.package,
          authorization: try machineOwnerAuthorization()
        )
      ) {
        XCTAssertEqual(
          $0 as? PinnedAsahiEngineExecutionError,
          .recoveryAuthorizationFailed
        )
      }
      XCTAssertTrue(try executionEntries(in: fixture.root).isEmpty)
    }

    func testReplaceTranscriptIsRejectedByRecoveryRetryCheckpoint() {
      let targetEvidence = Data("target-readback".utf8)
      let installedEvidence = Data("installed-readback".utf8)
      let evidence = [
        "apfs-target-prepared": targetEvidence,
        "stub-and-esp-installed": installedEvidence,
      ]
      let planDigest = String(repeating: "a", count: 64)

      XCTAssertTrue(
        RecoveryAuthorizationRetryCheckpoint.isEligible(
          transcript: recoveryRetryTranscript(
            targetEvidence: targetEvidence,
            installedEvidence: installedEvidence
          ),
          planDigest: planDigest,
          deviceIdentifier: "apple,j314s",
          storeIdentifier: "disk0",
          checkpointEvidence: evidence
        )
      )
      XCTAssertFalse(
        RecoveryAuthorizationRetryCheckpoint.isEligible(
          transcript: replaceRecoveryRetryTranscript(
            targetEvidence: targetEvidence,
            installedEvidence: installedEvidence,
            removalEvidence: Data("removal-readback".utf8)
          ),
          planDigest: planDigest,
          deviceIdentifier: "apple,j314s",
          storeIdentifier: "disk0",
          checkpointEvidence: evidence
        )
      )
    }

    func testTruncatedTranscriptIsRejected() async throws {
      let fixture = try makeFixture(transcript: Data("truncated".utf8))
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let executor = PinnedAsahiEngineExecutor(effectiveUserID: { 0 })

      await assertThrowsErrorAsync(
        try await executor.execute(
          fixture.package,
          authorization: try machineOwnerAuthorization()
        )
      ) {
        XCTAssertEqual(
          $0 as? PinnedAsahiEngineExecutionError,
          .unsafeTranscript
        )
      }
      XCTAssertTrue(try executionEntries(in: fixture.root).isEmpty)
    }

    func testUnsafeExistingJournalDirectoryIsRejected() async throws {
      let fixture = try makeFixture()
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let journalDirectory = fixture.root.appendingPathComponent(
        "execution-journals",
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: journalDirectory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o755]
      )
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: journalDirectory.path
      )
      let executor = PinnedAsahiEngineExecutor(effectiveUserID: { 0 })

      await assertThrowsErrorAsync(
        try await executor.execute(
          fixture.package,
          authorization: try machineOwnerAuthorization()
        )
      ) {
        XCTAssertEqual(
          $0 as? PinnedAsahiEngineExecutionError,
          .unsafeTranscript
        )
      }
      XCTAssertTrue(try executionEntries(in: fixture.root).isEmpty)
    }

    private func makeFixture(
      escapingSymlink: Bool = false,
      groupWritableBundleEntry: Bool = false,
      exitCode: Int32 = 0,
      transcript: Data = Data("validated-transcript\n".utf8),
      expectedInstallMode: String = "install",
      checkpointEvidence: [String: Data] = [:],
      repairManifest: Data? = nil
    ) throws -> PinnedExecutorFixture {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "omarchy-pinned-executor-\(UUID().uuidString.lowercased())",
        isDirectory: true
      )
      let packageURL = root.appendingPathComponent(
        "imported-handoff",
        isDirectory: true
      )
      let bundleSource = root.appendingPathComponent(
        "bundle-source",
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: packageURL,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try FileManager.default.createDirectory(
        at: bundleSource,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )

      let main = bundleSource.appendingPathComponent("main.py")
      try writePrivate(Data("# synthetic engine\n".utf8), to: main)
      var checkpointCommands = [String]()
      for (identifier, evidence) in checkpointEvidence.sorted(
        by: { $0.key < $1.key }
      ) {
        let fileName = "checkpoint-\(identifier)"
        try writePrivate(
          evidence,
          to: bundleSource.appendingPathComponent(fileName)
        )
        checkpointCommands.append(
          #"/bin/cp "$PWD/\#(fileName)" "$OMARCHY_ENGINE_JOURNAL.\#(identifier).evidence""#
        )
      }
      if groupWritableBundleEntry {
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o460],
          ofItemAtPath: main.path
        )
      }
      if escapingSymlink {
        try FileManager.default.createSymbolicLink(
          at: bundleSource.appendingPathComponent("escape"),
          withDestinationURL: URL(fileURLWithPath: "/private/tmp")
        )
      }
      let python = bundleSource.appendingPathComponent(
        "Frameworks/Python.framework/Versions/3.13/bin/python3.13"
      )
      try FileManager.default.createDirectory(
        at: python.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      let script = """
        #!/bin/sh
        case "$OMARCHY_ENGINE_MODE" in
          inspect) ;;
          plan)
            [ -r "$OMARCHY_ENGINE_REQUEST" ] || exit 77
            [ -r "$OMARCHY_ENGINE_IDENTITY" ] || exit 78
            /usr/bin/grep -q '"candidate_kind":"free"' "$OMARCHY_ENGINE_REQUEST" || exit 79
            /usr/bin/grep -q '"requested_length_bytes":100663296' "$OMARCHY_ENGINE_REQUEST" || exit 80
            /usr/bin/grep -q '"engine_version":"v0.9.0-omarchy.2"' "$OMARCHY_ENGINE_IDENTITY" || exit 81
            ;;
          install|retry-recovery-authorization)
            [ "$OMARCHY_ENGINE_MODE" = "\(expectedInstallMode)" ] || exit 64
            [ "$DISTRO" = "Omarchy MX Mac" ] || exit 68
            [ "$DISTRO_DOCS" = "https://omarchy.org/manual/" ] || exit 69
            [ "$OMARCHY_MACHINE_OWNER" = "mina" ] || exit 67
            IFS= read -r owner_password || exit 66
            [ "$owner_password" = "owner-password" ] || exit 65
            [ "$OMARCHY_ENGINE_PLAN_DIGEST" = "\(String(repeating: "a", count: 64))" ] || exit 71
            [ "$OMARCHY_ENGINE_BINDING_DIGEST" = "sha256:\(String(repeating: "b", count: 64))" ] || exit 72
            [ -r "$OMARCHY_ENGINE_REQUEST" ] || exit 73
            [ -r "$OMARCHY_ENGINE_IDENTITY" ] || exit 74
            [ -r "$OMARCHY_ENGINE_METADATA" ] || exit 75
            [ -r "$OMARCHY_ENGINE_PAYLOAD" ] || exit 76
            \(repairManifest == nil ? "" : "[ -r \"$OMARCHY_ENGINE_REPAIR_MANIFEST\" ] || exit 82")
            ;;
          *) exit 70 ;;
        esac
        /bin/cp "$PWD/transcript.jsonl" "$OMARCHY_ENGINE_JOURNAL"
        \(checkpointCommands.joined(separator: "\n"))
        exit \(exitCode)
        """
      try script.data(using: .utf8)?.write(
        to: python,
        options: .withoutOverwriting
      )
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o500],
        ofItemAtPath: python.path
      )
      try writePrivate(
        transcript,
        to: bundleSource.appendingPathComponent("transcript.jsonl")
      )

      let engineURL = packageURL.appendingPathComponent("engine.tar.gz")
      try createArchive(from: bundleSource, at: engineURL)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o400],
        ofItemAtPath: engineURL.path
      )
      let manifestURL = packageURL.appendingPathComponent("manifest.json")
      let requestURL = packageURL.appendingPathComponent("request.json")
      let identityURL = packageURL.appendingPathComponent("identity.json")
      let metadataURL = packageURL.appendingPathComponent(
        "installer-data.json"
      )
      let payloadURL = packageURL.appendingPathComponent("omarchy.img.zst")
      let repairManifestURL = repairManifest.map { _ in
        packageURL.appendingPathComponent("repair.json")
      }
      for url in [manifestURL, requestURL, identityURL, metadataURL, payloadURL] {
        try writePrivate(Data("fixture".utf8), to: url)
      }
      if let repairManifest, let repairManifestURL {
        try writePrivate(repairManifest, to: repairManifestURL)
      }

      return PinnedExecutorFixture(
        root: root,
        package: ImportedEngineHandoffPackage(
          packageURL: packageURL,
          manifestURL: manifestURL,
          requestURL: requestURL,
          identityURL: identityURL,
          engineURL: engineURL,
          metadataURL: metadataURL,
          payloadURL: payloadURL,
          repairManifestURL: repairManifestURL,
          bindingDigest: "sha256:" + String(repeating: "b", count: 64),
          planDigest: String(repeating: "a", count: 64),
          deviceIdentifier: "apple,j314s",
          storeIdentifier: "disk0"
        ),
        transcript: transcript
      )
    }

    private func recoveryRetryTranscript(
      targetEvidence: Data,
      installedEvidence: Data
    ) -> Data {
      let planDigest = String(repeating: "a", count: 64)
      let targetDigest = digest(targetEvidence)
      let installedDigest = digest(installedEvidence)
      let lines = [
        #"{"schema_version":1,"sequence":1,"type":"inspection","payload":{"device_identifier":"apple,j314s","support":"supported"}}"#,
        #"{"schema_version":1,"sequence":2,"type":"inventory","payload":{"layout_digest":"sha256:\#(String(repeating: "c", count: 64))","system_store_identifier":"disk0","candidates":[]}}"#,
        #"{"schema_version":1,"sequence":3,"type":"plan","payload":{"plan_digest":"\#(planDigest)","device_identifier":"apple,j314s","store_identifier":"disk0"}}"#,
        #"{"schema_version":1,"sequence":4,"type":"event","payload":{"plan_digest":"\#(planDigest)","name":"apfs_preparation_started"}}"#,
        #"{"schema_version":1,"sequence":5,"type":"checkpoint","payload":{"plan_digest":"\#(planDigest)","identifier":"apfs-target-prepared","phase":"apfs_preparation","evidence_digest":"\#(targetDigest)"}}"#,
        #"{"schema_version":1,"sequence":6,"type":"event","payload":{"plan_digest":"\#(planDigest)","name":"stub_and_esp_started"}}"#,
        #"{"schema_version":1,"sequence":7,"type":"checkpoint","payload":{"plan_digest":"\#(planDigest)","identifier":"stub-and-esp-installed","phase":"stub_and_esp","evidence_digest":"\#(installedDigest)"}}"#,
        #"{"schema_version":1,"sequence":8,"type":"event","payload":{"plan_digest":"\#(planDigest)","name":"recovery_handoff_started"}}"#,
      ]
      return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private func replaceRecoveryRetryTranscript(
      targetEvidence: Data,
      installedEvidence: Data,
      removalEvidence: Data
    ) -> Data {
      let planDigest = String(repeating: "a", count: 64)
      let removalDigest = digest(removalEvidence)
      let targetDigest = digest(targetEvidence)
      let installedDigest = digest(installedEvidence)
      let lines = [
        #"{"schema_version":1,"sequence":1,"type":"inspection","payload":{"device_identifier":"apple,j314s","support":"supported"}}"#,
        #"{"schema_version":1,"sequence":2,"type":"inventory","payload":{"layout_digest":"sha256:\#(String(repeating: "c", count: 64))","system_store_identifier":"disk0","candidates":[]}}"#,
        #"{"schema_version":1,"sequence":3,"type":"plan","payload":{"plan_digest":"\#(planDigest)","device_identifier":"apple,j314s","store_identifier":"disk0"}}"#,
        #"{"schema_version":1,"sequence":4,"type":"event","payload":{"plan_digest":"\#(planDigest)","name":"existing_removal_started"}}"#,
        #"{"schema_version":1,"sequence":5,"type":"checkpoint","payload":{"plan_digest":"\#(planDigest)","identifier":"existing-install-removed","phase":"existing_removal","evidence_digest":"\#(removalDigest)"}}"#,
        #"{"schema_version":1,"sequence":6,"type":"event","payload":{"plan_digest":"\#(planDigest)","name":"apfs_preparation_started"}}"#,
        #"{"schema_version":1,"sequence":7,"type":"checkpoint","payload":{"plan_digest":"\#(planDigest)","identifier":"apfs-target-prepared","phase":"apfs_preparation","evidence_digest":"\#(targetDigest)"}}"#,
        #"{"schema_version":1,"sequence":8,"type":"event","payload":{"plan_digest":"\#(planDigest)","name":"stub_and_esp_started"}}"#,
        #"{"schema_version":1,"sequence":9,"type":"checkpoint","payload":{"plan_digest":"\#(planDigest)","identifier":"stub-and-esp-installed","phase":"stub_and_esp","evidence_digest":"\#(installedDigest)"}}"#,
        #"{"schema_version":1,"sequence":10,"type":"event","payload":{"plan_digest":"\#(planDigest)","name":"recovery_handoff_started"}}"#,
      ]
      return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private func createArchive(from source: URL, at archive: URL) throws {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
      process.arguments = [
        "-czf", archive.path, "-C", source.path, ".",
      ]
      process.environment = [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "LC_ALL": "C",
      ]
      process.standardInput = FileHandle.nullDevice
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      try process.run()
      process.waitUntilExit()
      guard process.terminationReason == .exit,
        process.terminationStatus == 0
      else {
        throw CocoaError(.fileWriteUnknown)
      }
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
      try data.write(to: url, options: .withoutOverwriting)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o400],
        ofItemAtPath: url.path
      )
    }

    private func executionEntries(in root: URL) throws -> [URL] {
      try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil
      ).filter { $0.lastPathComponent.hasPrefix("engine-execution-") }
    }

    private func planningInputEntries(in root: URL) throws -> [URL] {
      try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil
      ).filter { $0.lastPathComponent.hasPrefix("engine-plan-input-") }
    }

    private func digest(of url: URL) throws -> String {
      let data = try Data(contentsOf: url)
      return digest(data)
    }

    private func digest(_ data: Data) -> String {
      return "sha256:"
        + SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
    }

    private func size(of url: URL) throws -> UInt64 {
      let attributes = try FileManager.default.attributesOfItem(
        atPath: url.path
      )
      return (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func machineOwnerAuthorization() throws
      -> MachineOwnerAuthorization
    {
      try MachineOwnerAuthorization(
        username: "mina",
        password: Data("owner-password".utf8)
      )
    }

    private func journalEntries(in root: URL) throws -> [URL] {
      let directory = root.appendingPathComponent(
        "execution-journals",
        isDirectory: true
      )
      return try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
      )
    }

    private func importedPackage(at packageURL: URL)
      -> ImportedEngineHandoffPackage
    {
      ImportedEngineHandoffPackage(
        packageURL: packageURL,
        manifestURL: packageURL.appendingPathComponent("manifest.json"),
        requestURL: packageURL.appendingPathComponent("request.json"),
        identityURL: packageURL.appendingPathComponent("identity.json"),
        engineURL: packageURL.appendingPathComponent("engine.tar.gz"),
        metadataURL: packageURL.appendingPathComponent("installer-data.json"),
        payloadURL: packageURL.appendingPathComponent("omarchy.img.zst"),
        bindingDigest: "sha256:" + String(repeating: "b", count: 64),
        planDigest: String(repeating: "a", count: 64),
        deviceIdentifier: "apple,j314s",
        storeIdentifier: "disk0"
      )
    }
  }

  private struct PinnedExecutorFixture {
    let root: URL
    let package: ImportedEngineHandoffPackage
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
