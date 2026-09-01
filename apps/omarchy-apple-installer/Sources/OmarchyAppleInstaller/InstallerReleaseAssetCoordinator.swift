#if os(macOS)
  import Foundation

  public struct InstallerReleasePreparationRequest: Sendable {
    public let host: AppleSiliconHostInspection
    public let configuration: InstallerReleaseConfiguration
    public let validationTime: Date
    public let previouslyAcceptedCatalog: AcceptedCatalogIdentity?
    public let stagingDirectory: URL

    public init(
      host: AppleSiliconHostInspection,
      configuration: InstallerReleaseConfiguration,
      validationTime: Date,
      previouslyAcceptedCatalog: AcceptedCatalogIdentity? = nil,
      stagingDirectory: URL
    ) {
      self.host = host
      self.configuration = configuration
      self.validationTime = validationTime
      self.previouslyAcceptedCatalog = previouslyAcceptedCatalog
      self.stagingDirectory = stagingDirectory
    }
  }

  public struct PreparedInstallerRelease: Sendable {
    public let assets: PreparedInstallerAssets
    public let catalogDocuments: InstallerReleaseCatalogDocuments
  }

  public struct InstallerReleaseAssetCoordinator: Sendable {
    private let catalogFetcher: InstallerReleaseCatalogFetcher
    private let assetPreparer: InstallerAssetPreparer

    public init() {
      catalogFetcher = InstallerReleaseCatalogFetcher()
      assetPreparer = InstallerAssetPreparer()
    }

    init(
      catalogFetcher: InstallerReleaseCatalogFetcher,
      assetPreparer: InstallerAssetPreparer
    ) {
      self.catalogFetcher = catalogFetcher
      self.assetPreparer = assetPreparer
    }

    public func prepare(
      _ request: InstallerReleasePreparationRequest,
      progress: ArtifactStagingProgressHandler? = nil
    ) async throws -> PreparedInstallerAssets {
      try await prepareRelease(request, progress: progress).assets
    }

    public func prepareRelease(
      _ request: InstallerReleasePreparationRequest,
      progress: ArtifactStagingProgressHandler? = nil
    ) async throws -> PreparedInstallerRelease {
      _ = try assetPreparer.validateHost(request.host)
      let catalog = try await catalogFetcher.fetch(
        configuration: request.configuration
      )
      let assets = try await assetPreparer.prepare(
        InstallerAssetPreparationRequest(
          host: request.host,
          catalogPayload: catalog.payload,
          catalogSignature: catalog.signature,
          trustRoot: request.configuration.trustRoot,
          validationTime: request.validationTime,
          previouslyAcceptedCatalog: request.previouslyAcceptedCatalog,
          stagingDirectory: request.stagingDirectory
        ),
        progress: progress
      )
      return PreparedInstallerRelease(
        assets: assets,
        catalogDocuments: catalog
      )
    }
  }
#endif
