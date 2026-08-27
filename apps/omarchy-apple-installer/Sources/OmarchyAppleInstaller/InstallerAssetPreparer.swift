#if os(macOS)
  import Foundation

  public struct InstallerAssetPreparationRequest: Sendable {
    public let host: AppleSiliconHostInspection
    public let catalogPayload: Data
    public let catalogSignature: Data
    public let trustRoot: AppOwnedTrustRoot
    public let validationTime: Date
    public let previouslyAcceptedCatalog: AcceptedCatalogIdentity?
    public let stagingDirectory: URL

    public init(
      host: AppleSiliconHostInspection,
      catalogPayload: Data,
      catalogSignature: Data,
      trustRoot: AppOwnedTrustRoot,
      validationTime: Date,
      previouslyAcceptedCatalog: AcceptedCatalogIdentity? = nil,
      stagingDirectory: URL
    ) {
      self.host = host
      self.catalogPayload = catalogPayload
      self.catalogSignature = catalogSignature
      self.trustRoot = trustRoot
      self.validationTime = validationTime
      self.previouslyAcceptedCatalog = previouslyAcceptedCatalog
      self.stagingDirectory = stagingDirectory
    }
  }

  public struct PreparedInstallerAssets: Sendable {
    public let catalogIdentity: AcceptedCatalogIdentity
    public let installer: PinnedInstallerRecord
    public let engine: StagedInstallerArtifact
    public let metadata: StagedInstallerArtifact
    public let payload: StagedInstallerArtifact
  }

  public enum InstallerAssetPreparationError: Error, Equatable, Sendable {
    case hostBlocked(String)
    case unsupportedDevice(String)
    case deliveryMetadataUnavailable
  }

  public struct InstallerAssetPreparer: Sendable {
    private static let explicitlyUnsupportedDevices = ["apple,j614s"]

    private let trustCore: AppleInstallerTrustCore
    private let stager: VerifiedArtifactStager

    public init() {
      trustCore = AppleInstallerTrustCore()
      stager = VerifiedArtifactStager()
    }

    init(stager: VerifiedArtifactStager) {
      trustCore = AppleInstallerTrustCore()
      self.stager = stager
    }

    public func prepare(
      _ request: InstallerAssetPreparationRequest
    ) async throws -> PreparedInstallerAssets {
      let deviceIdentifier = try validateHost(request.host)

      let catalog = try trustCore.validateSupportCatalog(
        payload: request.catalogPayload,
        signature: request.catalogSignature,
        trustRoot: request.trustRoot,
        now: request.validationTime,
        previouslyAccepted: request.previouslyAcceptedCatalog
      )
      guard case .admitted(let installer) = catalog.admission(
        for: deviceIdentifier
      ) else {
        throw InstallerAssetPreparationError.unsupportedDevice(deviceIdentifier)
      }
      guard let delivery = installer.delivery else {
        throw InstallerAssetPreparationError.deliveryMetadataUnavailable
      }

      let engine = try await stager.stage(
        delivery.engine,
        in: request.stagingDirectory
      )
      let metadata = try await stager.stage(
        delivery.metadata,
        in: request.stagingDirectory
      )
      let payload = try await stager.stage(
        delivery.payload,
        in: request.stagingDirectory
      )

      return PreparedInstallerAssets(
        catalogIdentity: catalog.acceptedIdentity,
        installer: installer,
        engine: engine,
        metadata: metadata,
        payload: payload
      )
    }

    func validateHost(
      _ host: AppleSiliconHostInspection
    ) throws -> String {
      if case .blocked(let reason) = host.eligibility {
        throw InstallerAssetPreparationError.hostBlocked(reason)
      }
      let deviceIdentifier = host.identity.deviceIdentifier
      guard !Self.explicitlyUnsupportedDevices.contains(deviceIdentifier) else {
        throw InstallerAssetPreparationError.unsupportedDevice(deviceIdentifier)
      }
      return deviceIdentifier
    }
  }
#endif
