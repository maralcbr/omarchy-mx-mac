#if os(macOS)
  import Foundation

  public enum InstallerPlanPreparationError:
    Error, Equatable, Sendable
  {
    case unsupportedDevice(String)
    case inventoryUnavailable
    case engineVersionUnavailable
  }

  public protocol InstallerPlanExecuting: Sendable {
    func plan(
      _ archive: PinnedAsahiEngineArchive,
      request: PinnedAsahiPlanRequest,
      identity: PinnedAsahiPlanIdentity,
      repairManifestURL: URL?,
      in scratchDirectory: URL
    ) async throws -> Data
  }

  extension PinnedAsahiEngineExecutor: InstallerPlanExecuting {}

  public struct InstallerPlanPreparationRequest: Sendable {
    public let host: AppleSiliconHostInspection
    public let release: PreparedInstallerRelease
    public let configuration: InstallerReleaseConfiguration
    public let inspectionTranscript: Data
    public let candidate: ValidatedEngineCandidate
    public let requestedLengthBytes: UInt64
    public let validationTime: Date
    public let previouslyAcceptedCatalog: AcceptedCatalogIdentity?
    public let scratchDirectory: URL

    public init(
      host: AppleSiliconHostInspection,
      release: PreparedInstallerRelease,
      configuration: InstallerReleaseConfiguration,
      inspectionTranscript: Data,
      candidate: ValidatedEngineCandidate,
      requestedLengthBytes: UInt64,
      validationTime: Date,
      previouslyAcceptedCatalog: AcceptedCatalogIdentity? = nil,
      scratchDirectory: URL
    ) {
      self.host = host
      self.release = release
      self.configuration = configuration
      self.inspectionTranscript = inspectionTranscript
      self.candidate = candidate
      self.requestedLengthBytes = requestedLengthBytes
      self.validationTime = validationTime
      self.previouslyAcceptedCatalog = previouslyAcceptedCatalog
      self.scratchDirectory = scratchDirectory
    }
  }

  public struct PreparedInstallerPlanExecution: Sendable {
    public let review: InstallerPlanReview
    public let candidateRequest: ClosedEngineCandidateRequest

    fileprivate init(
      review: InstallerPlanReview,
      candidateRequest: ClosedEngineCandidateRequest
    ) {
      self.review = review
      self.candidateRequest = candidateRequest
    }
  }

  public struct InstallerPlanPreparationCoordinator: Sendable {
    private let trustCore: AppleInstallerTrustCore
    private let planner: any InstallerPlanExecuting
    private let reviewCoordinator: InstallerPlanReviewCoordinator

    public init() {
      trustCore = AppleInstallerTrustCore()
      planner = PinnedAsahiEngineExecutor()
      reviewCoordinator = InstallerPlanReviewCoordinator()
    }

    init(planner: any InstallerPlanExecuting) {
      trustCore = AppleInstallerTrustCore()
      self.planner = planner
      reviewCoordinator = InstallerPlanReviewCoordinator()
    }

    public func prepare(
      _ request: InstallerPlanPreparationRequest
    ) async throws -> InstallerPlanReview {
      try await prepareExecution(request).review
    }

    public func prepareExecution(
      _ request: InstallerPlanPreparationRequest
    ) async throws -> PreparedInstallerPlanExecution {
      let inspection = try trustCore.validateEngineTranscript(
        request.inspectionTranscript
      )
      let deviceIdentifier = request.host.identity.deviceIdentifier
      guard inspection.deviceIdentifier == deviceIdentifier,
        inspection.support == .supported
      else {
        throw InstallerPlanPreparationError.unsupportedDevice(
          deviceIdentifier
        )
      }
      guard let inventory = inspection.inventory else {
        throw InstallerPlanPreparationError.inventoryUnavailable
      }
      guard let engineVersion = request.release.assets.installer.engineVersion
      else {
        throw InstallerPlanPreparationError.engineVersionUnavailable
      }

      let planRequest = try PinnedAsahiPlanRequest(
        inventory: inventory,
        candidate: request.candidate,
        requestedLengthBytes: request.requestedLengthBytes
      )
      let planIdentity = try PinnedAsahiPlanIdentity(
        engineVersion: engineVersion,
        installer: request.release.assets.installer
      )
      let engine = request.release.assets.engine
      let archive = try PinnedAsahiEngineArchive(
        fileURL: engine.fileURL,
        expectedDigest: engine.artifact.expectedDigest,
        expectedSizeBytes: engine.artifact.expectedSizeBytes
      )
      let planningTranscript = try await planner.plan(
        archive,
        request: planRequest,
        identity: planIdentity,
        repairManifestURL: request.release.assets.repairManifest?.fileURL,
        in: request.scratchDirectory
      )
      let review = try reviewCoordinator.prepare(
        InstallerPlanReviewRequest(
          host: request.host,
          release: request.release,
          configuration: request.configuration,
          planningTranscript: planningTranscript,
          validationTime: request.validationTime,
          previouslyAcceptedCatalog: request.previouslyAcceptedCatalog
        )
      )
      let candidateRequest = ClosedEngineCandidateRequest(
        planningTranscript: planningTranscript,
        catalogPayload: request.release.catalogDocuments.payload,
        catalogSignature: request.release.catalogDocuments.signature,
        trustRoot: request.configuration.trustRoot,
        validationTime: request.validationTime,
        previouslyAcceptedCatalog: request.previouslyAcceptedCatalog
      )
      return PreparedInstallerPlanExecution(
        review: review,
        candidateRequest: candidateRequest
      )
    }
  }
#endif
