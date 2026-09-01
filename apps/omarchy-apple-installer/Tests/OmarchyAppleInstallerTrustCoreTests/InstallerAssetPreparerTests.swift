#if os(macOS)
  import CryptoKit
  import Foundation
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  final class InstallerAssetPreparerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    func testSignedSchemaTwoCatalogStagesExactAdmittedAssets() async throws {
      let fixture = try makeFixture(schemaVersion: 2)
      let directory = temporaryDirectory()
      defer { try? FileManager.default.removeItem(at: directory) }

      let result = try await fixture.preparer.prepare(
        fixture.request(stagingDirectory: directory)
      )

      XCTAssertEqual(result.catalogIdentity.sequence, 30)
      XCTAssertEqual(result.installer.deviceIdentifier, "apple,j314s")
      XCTAssertEqual(try Data(contentsOf: result.engine.fileURL), fixture.engine)
      XCTAssertEqual(try Data(contentsOf: result.metadata.fileURL), fixture.metadata)
      XCTAssertEqual(try Data(contentsOf: result.payload.fileURL), fixture.payload)
      let downloadCount = await fixture.downloader.downloadCount
      let maximumConcurrentDownloads = await fixture.downloader.maximumConcurrentDownloads
      XCTAssertEqual(downloadCount, 3)
      XCTAssertEqual(maximumConcurrentDownloads, 3)
    }

    func testSignedRepairCatalogStagesExactRepairManifest() async throws {
      let fixture = try makeFixture(schemaVersion: 3)
      let directory = temporaryDirectory()
      defer { try? FileManager.default.removeItem(at: directory) }

      let result = try await fixture.preparer.prepare(
        fixture.request(stagingDirectory: directory)
      )

      let repairManifest = try XCTUnwrap(result.repairManifest)
      XCTAssertEqual(
        try Data(contentsOf: repairManifest.fileURL),
        fixture.repairManifest
      )
      let downloadCount = await fixture.downloader.downloadCount
      let maximumConcurrentDownloads = await fixture.downloader.maximumConcurrentDownloads
      XCTAssertEqual(downloadCount, 4)
      XCTAssertEqual(maximumConcurrentDownloads, 4)
    }

    func testReleaseCoordinatorFetchesSignedCatalogThenStagesExactAssets()
      async throws
    {
      let fixture = try makeFixture(schemaVersion: 2)
      let directory = temporaryDirectory()
      defer { try? FileManager.default.removeItem(at: directory) }
      let coordinator = InstallerReleaseAssetCoordinator(
        catalogFetcher: InstallerReleaseCatalogFetcher(
          downloader: fixture.releaseDownloader
        ),
        assetPreparer: fixture.preparer
      )

      let result = try await coordinator.prepare(
        InstallerReleasePreparationRequest(
          host: fixture.host,
          configuration: fixture.releaseConfiguration,
          validationTime: now,
          stagingDirectory: directory
        )
      )

      XCTAssertEqual(result.catalogIdentity.sequence, 30)
      XCTAssertEqual(try Data(contentsOf: result.engine.fileURL), fixture.engine)
      XCTAssertEqual(try Data(contentsOf: result.payload.fileURL), fixture.payload)
      let releaseDownloadCount = await fixture.releaseDownloader.downloadCount
      let artifactDownloadCount = await fixture.downloader.downloadCount
      XCTAssertEqual(releaseDownloadCount, 2)
      XCTAssertEqual(artifactDownloadCount, 3)
    }

    func testReleaseCoordinatorBlocksM4BeforeCatalogNetwork() async throws {
      let fixture = try makeFixture(
        schemaVersion: 2,
        host: host(
          deviceIdentifier: "apple,j614s",
          eligibility: .blocked(reason: "M4 is not enabled")
        )
      )
      let directory = temporaryDirectory()
      defer { try? FileManager.default.removeItem(at: directory) }
      let coordinator = InstallerReleaseAssetCoordinator(
        catalogFetcher: InstallerReleaseCatalogFetcher(
          downloader: fixture.releaseDownloader
        ),
        assetPreparer: fixture.preparer
      )

      await assertAssetPreparationThrows(
        try await coordinator.prepare(
          InstallerReleasePreparationRequest(
            host: fixture.host,
            configuration: fixture.releaseConfiguration,
            validationTime: now,
            stagingDirectory: directory
          )
        )
      ) {
        XCTAssertEqual(
          $0 as? InstallerAssetPreparationError,
          .hostBlocked("M4 is not enabled")
        )
      }
      let releaseDownloadCount = await fixture.releaseDownloader.downloadCount
      let artifactDownloadCount = await fixture.downloader.downloadCount
      XCTAssertEqual(releaseDownloadCount, 0)
      XCTAssertEqual(artifactDownloadCount, 0)
    }

    func testSchemaOneCatalogCannotDriveDownloads() async throws {
      let fixture = try makeFixture(schemaVersion: 1)
      let directory = temporaryDirectory()
      defer { try? FileManager.default.removeItem(at: directory) }

      await assertAssetPreparationThrows(
        try await fixture.preparer.prepare(
          fixture.request(stagingDirectory: directory)
        )
      ) {
        XCTAssertEqual(
          $0 as? InstallerAssetPreparationError,
          .deliveryMetadataUnavailable
        )
      }
      let downloadCount = await fixture.downloader.downloadCount
      XCTAssertEqual(downloadCount, 0)
    }

    func testM4StopsBeforeCatalogValidationOrDownload() async throws {
      let fixture = try makeFixture(
        schemaVersion: 2,
        host: host(
          deviceIdentifier: "apple,j614s",
          eligibility: .blocked(reason: "M4 is not enabled")
        )
      )
      let directory = temporaryDirectory()
      defer { try? FileManager.default.removeItem(at: directory) }

      await assertAssetPreparationThrows(
        try await fixture.preparer.prepare(
          fixture.request(stagingDirectory: directory)
        )
      ) {
        XCTAssertEqual(
          $0 as? InstallerAssetPreparationError,
          .hostBlocked("M4 is not enabled")
        )
      }
      let downloadCount = await fixture.downloader.downloadCount
      XCTAssertEqual(downloadCount, 0)
    }

    func testInvalidCatalogSignatureStopsBeforeDownload() async throws {
      let fixture = try makeFixture(schemaVersion: 2, invalidateSignature: true)
      let directory = temporaryDirectory()
      defer { try? FileManager.default.removeItem(at: directory) }

      await assertAssetPreparationThrows(
        try await fixture.preparer.prepare(
          fixture.request(stagingDirectory: directory)
        )
      ) {
        XCTAssertEqual($0 as? SupportCatalogError, .invalidSignature)
      }
      let downloadCount = await fixture.downloader.downloadCount
      XCTAssertEqual(downloadCount, 0)
    }

    func testSchemaTwoCatalogRequiresSignedEngineVersionBeforeDownload()
      async throws
    {
      let fixture = try makeFixture(
        schemaVersion: 2,
        omitEngineVersion: true
      )
      let directory = temporaryDirectory()
      defer { try? FileManager.default.removeItem(at: directory) }

      await assertAssetPreparationThrows(
        try await fixture.preparer.prepare(
          fixture.request(stagingDirectory: directory)
        )
      ) {
        XCTAssertEqual(
          $0 as? SupportCatalogError,
          .invalidField("models[0].engineVersion")
        )
      }
      let downloadCount = await fixture.downloader.downloadCount
      XCTAssertEqual(downloadCount, 0)
    }

    func testPrepareForwardsStagingProgressForEveryRole() async throws {
      let fixture = try makeFixture(schemaVersion: 2)
      let directory = temporaryDirectory()
      defer { try? FileManager.default.removeItem(at: directory) }
      let recorder = AssetStagingProgressRecorder()

      let result = try await fixture.preparer.prepare(
        fixture.request(stagingDirectory: directory),
        progress: recorder.handler
      )

      let events = recorder.events
      XCTAssertEqual(
        Set(events.filter { $0.phase == .verified }.map(\.role)),
        ["engine", "metadata", "payload"]
      )
      XCTAssertTrue(
        events.allSatisfy { $0.bytesCompleted == $0.totalBytes }
      )
      XCTAssertEqual(
        events.first(where: { $0.role == "payload" })?.totalBytes,
        UInt64(fixture.payload.count)
      )
      XCTAssertEqual(
        try Data(contentsOf: result.payload.fileURL),
        fixture.payload
      )
    }

    private func makeFixture(
      schemaVersion: Int,
      host: AppleSiliconHostInspection? = nil,
      invalidateSignature: Bool = false,
      omitEngineVersion: Bool = false
    ) throws -> AssetPreparationFixture {
      let engine = Data("engine archive".utf8)
      let metadata = Data("installer metadata".utf8)
      let payload = Data("omarchy payload".utf8)
      let repairManifest = Data("{\"operation\":\"repair-installed-system\"}".utf8)
      var artifacts = [
        URL(string: "https://downloads.example.com/engine.tar.gz")!: engine,
        URL(string: "https://downloads.example.com/installer-data.json")!: metadata,
        URL(string: "https://downloads.example.com/omarchy.img.zst")!: payload,
      ]
      artifacts[
        URL(string: "https://downloads.example.com/repair.json")!
      ] = repairManifest
      let downloader = CatalogFixtureDownloader(artifacts: artifacts)
      let privateKey = Curve25519.Signing.PrivateKey()
      let payloadData = catalog(
        schemaVersion: schemaVersion,
        engine: engine,
        metadata: metadata,
        payload: payload,
        repairManifest: repairManifest,
        omitEngineVersion: omitEngineVersion
      )
      let signature = try privateKey.signature(for: payloadData)
      let deliveredSignature =
        invalidateSignature
        ? Data(repeating: 0, count: signature.count)
        : signature
      let publicKey = privateKey.publicKey.rawRepresentation
      let trustRoot = try AppOwnedTrustRoot(
        rawRepresentation: publicKey,
        expectedFingerprint: digest(publicKey)
      )
      let catalogURL = URL(
        string: "https://releases.example.com/apple/catalog.json"
      )!
      let signatureURL = URL(
        string: "https://releases.example.com/apple/catalog.json.sig"
      )!
      let releaseDownloader = ReleaseCatalogFixtureDownloader(values: [
        catalogURL: payloadData,
        signatureURL: deliveredSignature,
      ])
      let releaseConfiguration = InstallerReleaseConfiguration(
        catalogURL: catalogURL,
        catalogSignatureURL: signatureURL,
        trustRoot: trustRoot,
        helperMachServiceName: "com.omarchy.apple-installer.helper",
        helperCodeSigningRequirement:
          #"identifier "com.omarchy.apple-installer.helper""#
      )

      return AssetPreparationFixture(
        preparer: InstallerAssetPreparer(
          stager: VerifiedArtifactStager(downloader: downloader)
        ),
        downloader: downloader,
        host: host
          ?? self.host(
            deviceIdentifier: "apple,j314s",
            eligibility: .requiresSignedCatalog
          ),
        catalogPayload: payloadData,
        catalogSignature: deliveredSignature,
        trustRoot: trustRoot,
        releaseConfiguration: releaseConfiguration,
        releaseDownloader: releaseDownloader,
        validationTime: now,
        engine: engine,
        metadata: metadata,
        payload: payload,
        repairManifest: repairManifest
      )
    }

    private func catalog(
      schemaVersion: Int,
      engine: Data,
      metadata: Data,
      payload: Data,
      repairManifest: Data,
      omitEngineVersion: Bool
    ) -> Data {
      let issued = ISO8601DateFormatter().string(
        from: now.addingTimeInterval(-3_600)
      )
      let expires = ISO8601DateFormatter().string(
        from: now.addingTimeInterval(86_400)
      )
      let engineVersion =
        omitEngineVersion
        ? ""
        : ",\"engineVersion\":\"v0.9.0-omarchy.2\""
      let repairDelivery =
        schemaVersion == 3
        ? ",\"operation\":\"repair-installed-system\",\"repairManifestDigest\":\"\(digest(repairManifest))\",\"repairManifestArtifact\":{\"sourceURL\":\"https://downloads.example.com/repair.json\",\"fileName\":\"repair.json\",\"sizeBytes\":\(repairManifest.count)}"
        : ""
      let delivery =
        schemaVersion >= 2
        ? """
        \(engineVersion),"engineArtifact":{"sourceURL":"https://downloads.example.com/engine.tar.gz","fileName":"engine.tar.gz","sizeBytes":\(engine.count)},"metadataArtifact":{"sourceURL":"https://downloads.example.com/installer-data.json","fileName":"installer-data.json","sizeBytes":\(metadata.count)},"payloadArtifact":{"sourceURL":"https://downloads.example.com/omarchy.img.zst","fileName":"omarchy.img.zst","sizeBytes":\(payload.count)}\(repairDelivery)
        """
        : ""
      return Data(
        """
        {"schemaVersion":\(schemaVersion),"sequence":30,"issuedAt":"\(issued)","expiresAt":"\(expires)","models":[{"deviceIdentifier":"apple,j314s","status":"enabled","asahiInstallerTag":"v0.9.0","asahiInstallerRevision":"\(String(repeating: "a", count: 40))","asahiInstallerDataRevision":"\(String(repeating: "b", count: 40))","downstreamRevision":"\(String(repeating: "c", count: 40))","engineDigest":"\(digest(engine))","metadataDigest":"\(digest(metadata))","payloadDigest":"\(digest(payload))","evidenceRevision":"evidence-s4"\(delivery)}]}
        """.utf8
      )
    }

    private func host(
      deviceIdentifier: String,
      eligibility: AppleSiliconInstallEligibility
    ) -> AppleSiliconHostInspection {
      AppleSiliconHostInspection(
        identity: AppleMacIdentity(
          model: "MacBookPro18,3",
          chip: "Apple M1 Pro",
          deviceIdentifier: deviceIdentifier
        ),
        eligibility: eligibility,
        macOSVersion: "Version 15.6",
        powerSource: .ac,
        fileVaultEnabled: true,
        storage: APFSStorageInspection(
          containerIdentifier: "disk3",
          physicalStoreIdentifier: "disk0s2",
          isInternal: true,
          containerSizeBytes: 1_000,
          containerFreeBytes: 500,
          minimumPreferredSizeBytes: 600
        )
      )
    }

    private func digest(_ data: Data) -> String {
      "sha256:"
        + SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
    }

    private func temporaryDirectory() -> URL {
      FileManager.default.temporaryDirectory.appendingPathComponent(
        "omarchy-asset-preparer-\(UUID().uuidString.lowercased())",
        isDirectory: true
      )
    }
  }

  private actor CatalogFixtureDownloader: ArtifactDownloading {
    let artifacts: [URL: Data]
    private(set) var downloadCount = 0
    private(set) var maximumConcurrentDownloads = 0
    private var concurrentDownloads = 0

    init(artifacts: [URL: Data]) {
      self.artifacts = artifacts
    }

    func download(from sourceURL: URL) async throws -> URL {
      guard let data = artifacts[sourceURL] else {
        throw URLError(.fileDoesNotExist)
      }
      downloadCount += 1
      concurrentDownloads += 1
      maximumConcurrentDownloads = max(
        maximumConcurrentDownloads,
        concurrentDownloads
      )
      defer { concurrentDownloads -= 1 }
      try await Task.sleep(for: .milliseconds(20))
      let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "omarchy-catalog-download-\(UUID().uuidString.lowercased())"
      )
      try data.write(to: fileURL, options: .withoutOverwriting)
      return fileURL
    }
  }

  private actor ReleaseCatalogFixtureDownloader:
    ReleaseDocumentDownloading
  {
    let values: [URL: Data]
    private(set) var downloadCount = 0

    init(values: [URL: Data]) {
      self.values = values
    }

    func download(
      from url: URL,
      maximumBytes: Int,
      role: String
    ) async throws -> Data {
      guard let data = values[url],
        !data.isEmpty,
        data.count <= maximumBytes
      else {
        throw InstallerReleaseConfigurationError.oversizedDocument(role)
      }
      downloadCount += 1
      return data
    }
  }

  private final class AssetStagingProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = [ArtifactStagingProgress]()

    var events: [ArtifactStagingProgress] {
      lock.lock()
      defer { lock.unlock() }
      return storage
    }

    var handler: ArtifactStagingProgressHandler {
      { [self] event in
        lock.lock()
        storage.append(event)
        lock.unlock()
      }
    }
  }

  private struct AssetPreparationFixture {
    let preparer: InstallerAssetPreparer
    let downloader: CatalogFixtureDownloader
    let host: AppleSiliconHostInspection
    let catalogPayload: Data
    let catalogSignature: Data
    let trustRoot: AppOwnedTrustRoot
    let releaseConfiguration: InstallerReleaseConfiguration
    let releaseDownloader: ReleaseCatalogFixtureDownloader
    let validationTime: Date
    let engine: Data
    let metadata: Data
    let payload: Data
    let repairManifest: Data

    func request(stagingDirectory: URL) -> InstallerAssetPreparationRequest {
      InstallerAssetPreparationRequest(
        host: host,
        catalogPayload: catalogPayload,
        catalogSignature: catalogSignature,
        trustRoot: trustRoot,
        validationTime: validationTime,
        stagingDirectory: stagingDirectory
      )
    }
  }

  private func assertAssetPreparationThrows<T>(
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
