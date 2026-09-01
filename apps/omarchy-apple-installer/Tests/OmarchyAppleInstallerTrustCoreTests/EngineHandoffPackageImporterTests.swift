#if os(macOS)
  import CryptoKit
  import Darwin
  import Foundation
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  final class EngineHandoffPackageImporterTests: XCTestCase {
    func testValidPackageIsRecopiedIntoPrivateHelperDirectory() throws {
      let fixture = try makeFixture()
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let source = try openDirectory(fixture.source)
      defer { try? source.close() }

      let imported = try EngineHandoffPackageImporter().prepare(
        from: source,
        in: fixture.destination
      )
      defer { try? FileManager.default.removeItem(at: imported.packageURL) }

      XCTAssertEqual(try mode(imported.packageURL), 0o700)
      XCTAssertEqual(try mode(imported.engineURL), 0o400)
      XCTAssertEqual(try Data(contentsOf: imported.engineURL), fixture.engine)
      XCTAssertEqual(
        try Data(contentsOf: imported.metadataURL),
        fixture.metadata
      )
      XCTAssertEqual(
        try Data(contentsOf: imported.payloadURL),
        fixture.payload
      )

      try FileManager.default.removeItem(at: fixture.engineURL)
      try writePrivate(Data("changed!".utf8), to: fixture.engineURL)
      XCTAssertEqual(try Data(contentsOf: imported.engineURL), fixture.engine)
    }

    func testUnknownManifestFieldIsRejectedBeforeImport() throws {
      let fixture = try makeFixture(extraManifestField: true)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let source = try openDirectory(fixture.source)
      defer { try? source.close() }

      XCTAssertThrowsError(
        try EngineHandoffPackageImporter().prepare(
          from: source,
          in: fixture.destination
        )
      ) {
        XCTAssertEqual(
          $0 as? EngineHandoffImportError,
          .invalidManifest
        )
      }
      XCTAssertTrue(try importedEntries(in: fixture.destination).isEmpty)
    }

    func testRepairPackageImportsManifestBoundToPlanIdentity() throws {
      let fixture = try makeFixture(repair: true)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let source = try openDirectory(fixture.source)
      defer { try? source.close() }

      let imported = try EngineHandoffPackageImporter().prepare(
        from: source,
        in: fixture.destination
      )
      defer { try? FileManager.default.removeItem(at: imported.packageURL) }

      XCTAssertEqual(
        try Data(contentsOf: try XCTUnwrap(imported.repairManifestURL)),
        try XCTUnwrap(fixture.repairManifest)
      )
    }

    func testReplacePackageImportsUnderInstallOperation() throws {
      let fixture = try makeFixture(replace: true)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let source = try openDirectory(fixture.source)
      defer { try? source.close() }

      let imported = try EngineHandoffPackageImporter().prepare(
        from: source,
        in: fixture.destination
      )
      defer { try? FileManager.default.removeItem(at: imported.packageURL) }

      XCTAssertNil(imported.repairManifestURL)
      XCTAssertEqual(try Data(contentsOf: imported.engineURL), fixture.engine)
    }

    func testReplacePackageWithRepairManifestIsRejected() throws {
      let fixture = try makeFixture(replace: true, strayRepairManifest: true)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let source = try openDirectory(fixture.source)
      defer { try? source.close() }

      XCTAssertThrowsError(
        try EngineHandoffPackageImporter().prepare(
          from: source,
          in: fixture.destination
        )
      ) {
        XCTAssertEqual(
          $0 as? EngineHandoffImportError,
          .bindingMismatch
        )
      }
      XCTAssertTrue(try importedEntries(in: fixture.destination).isEmpty)
    }

    func testReplacePackageUnderRepairOperationIsRejected() throws {
      let fixture = try makeFixture(replace: true)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let original = try String(
        contentsOf: fixture.requestURL,
        encoding: .utf8
      )
      let changed = original.replacingOccurrences(
        of: #""operation":"install""#,
        with: #""operation":"repair-installed-system""#
      )
      try FileManager.default.removeItem(at: fixture.requestURL)
      try writePrivate(Data(changed.utf8), to: fixture.requestURL)
      let source = try openDirectory(fixture.source)
      defer { try? source.close() }

      XCTAssertThrowsError(
        try EngineHandoffPackageImporter().prepare(
          from: source,
          in: fixture.destination
        )
      ) {
        XCTAssertEqual(
          $0 as? EngineHandoffImportError,
          .invalidRequest
        )
      }
      XCTAssertTrue(try importedEntries(in: fixture.destination).isEmpty)
    }

    func testNulArtifactFileNameIsRejectedBeforeImport() throws {
      let fixture = try makeFixture(nulEngineFileName: true)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let source = try openDirectory(fixture.source)
      defer { try? source.close() }

      XCTAssertThrowsError(
        try EngineHandoffPackageImporter().prepare(
          from: source,
          in: fixture.destination
        )
      ) {
        XCTAssertEqual(
          $0 as? EngineHandoffImportError,
          .invalidManifest
        )
      }
      XCTAssertTrue(try importedEntries(in: fixture.destination).isEmpty)
    }

    func testChangedPayloadIsRejectedAndPartialImportIsRemoved() throws {
      let fixture = try makeFixture(corruptPayload: true)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let source = try openDirectory(fixture.source)
      defer { try? source.close() }

      XCTAssertThrowsError(
        try EngineHandoffPackageImporter().prepare(
          from: source,
          in: fixture.destination
        )
      ) {
        XCTAssertEqual(
          $0 as? EngineHandoffImportError,
          .digestMismatch("payload")
        )
      }
      XCTAssertTrue(try importedEntries(in: fixture.destination).isEmpty)
    }

    func testChangedRequestExtentIsRejectedBeforeImport() throws {
      let fixture = try makeFixture()
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let original = try String(
        contentsOf: fixture.requestURL,
        encoding: .utf8
      )
      let changed = original.replacingOccurrences(
        of: #""offset_bytes":2000"#,
        with: #""offset_bytes":3000"#
      )
      try FileManager.default.removeItem(at: fixture.requestURL)
      try writePrivate(Data(changed.utf8), to: fixture.requestURL)
      let source = try openDirectory(fixture.source)
      defer { try? source.close() }

      XCTAssertThrowsError(
        try EngineHandoffPackageImporter().prepare(
          from: source,
          in: fixture.destination
        )
      ) {
        XCTAssertEqual(
          $0 as? EngineHandoffImportError,
          .bindingMismatch
        )
      }
      XCTAssertTrue(try importedEntries(in: fixture.destination).isEmpty)
    }

    func testSymlinkedEngineIsRejectedAndPartialImportIsRemoved() throws {
      let fixture = try makeFixture(symlinkEngine: true)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let source = try openDirectory(fixture.source)
      defer { try? source.close() }

      XCTAssertThrowsError(
        try EngineHandoffPackageImporter().prepare(
          from: source,
          in: fixture.destination
        )
      ) {
        XCTAssertEqual(
          $0 as? EngineHandoffImportError,
          .unsafeFile("engine")
        )
      }
      XCTAssertTrue(try importedEntries(in: fixture.destination).isEmpty)
    }

    private func makeFixture(
      extraManifestField: Bool = false,
      corruptPayload: Bool = false,
      symlinkEngine: Bool = false,
      nulEngineFileName: Bool = false,
      repair: Bool = false,
      replace: Bool = false,
      strayRepairManifest: Bool = false
    ) throws -> ImportFixture {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "omarchy-helper-import-\(UUID().uuidString.lowercased())",
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
      let repairManifest = Data("{\"operation\":\"repair-installed-system\"}".utf8)
      let engineURL = source.appendingPathComponent("engine.tar.gz")
      let metadataURL = source.appendingPathComponent("installer-data.json")
      let payloadURL = source.appendingPathComponent("omarchy.img.zst")
      let repairURL = source.appendingPathComponent("repair.json")
      if symlinkEngine {
        let target = source.appendingPathComponent("engine-target")
        try writePrivate(engine, to: target)
        try FileManager.default.createSymbolicLink(
          at: engineURL,
          withDestinationURL: target
        )
      } else {
        try writePrivate(engine, to: engineURL)
      }
      try writePrivate(metadata, to: metadataURL)
      try writePrivate(
        corruptPayload ? Data("payload-b".utf8) : payload,
        to: payloadURL
      )
      let includeRepairManifest = repair || strayRepairManifest
      if includeRepairManifest {
        try writePrivate(repairManifest, to: repairURL)
      }

      let bindingDigest = digest(Data("binding".utf8))
      let engineDigest = digest(engine)
      let metadataDigest = digest(metadata)
      let payloadDigest = digest(payload)
      let repairDigest = digest(repairManifest)
      let layoutDigest = digest(Data("layout".utf8))
      let engineVersion = "v0.9.0-omarchy.2"
      let candidateKind = repair ? "repair" : replace ? "replace" : "free"
      var planFields = [
        "apple,j314s", "disk0", layoutDigest, "free", "disk0s3",
        "2000", "1000", engineVersion, engineDigest, metadataDigest,
        payloadDigest,
      ]
      planFields[3] = candidateKind
      if includeRepairManifest {
        planFields.append(repairDigest)
      }
      planFields.append("enterOneTrueRecovery,authenticateMachineOwner")
      let planDigest = lengthPrefixedDigest(planFields)
      let extraField = extraManifestField ? #","unexpected":true"# : ""
      let engineFileName =
        nulEngineFileName
        ? #"engine\u0000ignored.tar.gz"#
        : "engine.tar.gz"
      let repairManifestField =
        includeRepairManifest
        ? ",\"repair_manifest\":{\"file_name\":\"repair.json\",\"digest\":\"\(repairDigest)\",\"size_bytes\":\(repairManifest.count)}"
        : ""
      let manifest = Data(
        """
        {"format":1,"binding_digest":"\(bindingDigest)","request_file":"request.json","identity_file":"identity.json","engine":{"file_name":"\(engineFileName)","digest":"\(engineDigest)","size_bytes":\(engine.count)},"metadata":{"file_name":"installer-data.json","digest":"\(metadataDigest)","size_bytes":\(metadata.count)},"payload":{"file_name":"omarchy.img.zst","digest":"\(payloadDigest)","size_bytes":\(payload.count)}\(repairManifestField)\(extraField)}
        """.utf8
      )
      let request = Data(
        """
        {"format":1,"operation":"\(repair ? "repair-installed-system" : "install")","plan_digest":"\(planDigest)","device_identifier":"apple,j314s","store_identifier":"disk0","layout_digest":"\(layoutDigest)","candidate_kind":"\(candidateKind)","source_identifier":"disk0s3","offset_bytes":2000,"length_bytes":1000,"engine_version":"\(engineVersion)","required_human_steps":["enterOneTrueRecovery","authenticateMachineOwner"]}
        """.utf8
      )
      let identity = Data(
        """
        {"format":1,"binding_digest":"\(bindingDigest)","trust_root_fingerprint":"\(digest(Data("root".utf8)))","catalog_sequence":40,"catalog_payload_digest":"\(digest(Data("catalog".utf8)))","plan_digest":"\(planDigest)","engine_digest":"\(engineDigest)","metadata_digest":"\(metadataDigest)","payload_digest":"\(payloadDigest)"\(includeRepairManifest ? ",\"repair_manifest_digest\":\"\(repairDigest)\"" : "")}
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

      return ImportFixture(
        root: root,
        source: source,
        destination: destination,
        engineURL: engineURL,
        requestURL: source.appendingPathComponent("request.json"),
        engine: engine,
        metadata: metadata,
        payload: payload,
        repairManifest: includeRepairManifest ? repairManifest : nil
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

    private func mode(_ url: URL) throws -> mode_t {
      var status = stat()
      guard lstat(url.path, &status) == 0 else {
        throw CocoaError(.fileReadUnknown)
      }
      return status.st_mode & 0o777
    }

    private func digest(_ data: Data) -> String {
      "sha256:"
        + SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
    }

    private func lengthPrefixedDigest(_ fields: [String]) -> String {
      let canonical =
        fields
        .map { "\($0.utf8.count):\($0)" }
        .joined(separator: "|")
      return SHA256.hash(data: Data(canonical.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
    }
  }

  private struct ImportFixture {
    let root: URL
    let source: URL
    let destination: URL
    let engineURL: URL
    let requestURL: URL
    let engine: Data
    let metadata: Data
    let payload: Data
    let repairManifest: Data?
  }
#endif
