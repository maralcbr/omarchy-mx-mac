#if os(macOS)
  import Foundation

  public enum InstallerPlanReviewError: Error, Equatable, Sendable {
    case deviceMismatch(expected: String, actual: String)
    case catalogIdentityMismatch
    case assetBindingMismatch
    case planUnavailable
    case ownerConfirmationMismatch
    case executionTranscriptMismatch
  }

  public struct InstallerPlanReviewRequest: Sendable {
    public let host: AppleSiliconHostInspection
    public let release: PreparedInstallerRelease
    public let configuration: InstallerReleaseConfiguration
    public let planningTranscript: Data
    public let validationTime: Date
    public let previouslyAcceptedCatalog: AcceptedCatalogIdentity?

    public init(
      host: AppleSiliconHostInspection,
      release: PreparedInstallerRelease,
      configuration: InstallerReleaseConfiguration,
      planningTranscript: Data,
      validationTime: Date,
      previouslyAcceptedCatalog: AcceptedCatalogIdentity? = nil
    ) {
      self.host = host
      self.release = release
      self.configuration = configuration
      self.planningTranscript = planningTranscript
      self.validationTime = validationTime
      self.previouslyAcceptedCatalog = previouslyAcceptedCatalog
    }
  }

  public struct InstallerPlanReviewCoordinator: Sendable {
    private let trustCore = AppleInstallerTrustCore()
    private let processAdapter = ClosedEngineProcessAdapter()

    public init() {}

    public func prepare(
      _ request: InstallerPlanReviewRequest
    ) throws -> InstallerPlanReview {
      let transcript = try trustCore.validateEngineTranscript(
        request.planningTranscript
      )
      let expectedDevice = request.host.identity.deviceIdentifier
      guard transcript.deviceIdentifier == expectedDevice else {
        throw InstallerPlanReviewError.deviceMismatch(
          expected: expectedDevice,
          actual: transcript.deviceIdentifier
        )
      }
      guard let plan = transcript.plan else {
        throw InstallerPlanReviewError.planUnavailable
      }

      let candidateRequest = ClosedEngineCandidateRequest(
        planningTranscript: request.planningTranscript,
        catalogPayload: request.release.catalogDocuments.payload,
        catalogSignature: request.release.catalogDocuments.signature,
        trustRoot: request.configuration.trustRoot,
        validationTime: request.validationTime,
        previouslyAcceptedCatalog: request.previouslyAcceptedCatalog
      )
      let identity = try processAdapter.candidateIdentity(
        for: candidateRequest
      )
      let assets = request.release.assets
      guard identity.catalogIdentity == assets.catalogIdentity else {
        throw InstallerPlanReviewError.catalogIdentityMismatch
      }
      guard assets.installer.deviceIdentifier == expectedDevice,
        assets.installer.engineVersion == plan.engineVersion,
        assets.engine.artifact.expectedDigest == plan.engineDigest,
        assets.metadata.artifact.expectedDigest == plan.metadataDigest,
        assets.payload.artifact.expectedDigest == plan.payloadDigest
      else {
        throw InstallerPlanReviewError.assetBindingMismatch
      }

      return InstallerPlanReview(
        identity: identity,
        plan: plan,
        assets: assets
      )
    }
  }

  public struct InstallerPlanReview: Sendable {
    public let identity: CandidateBoundPlanIdentity
    public let plan: ValidatedEnginePlan
    public let assets: PreparedInstallerAssets

    fileprivate init(
      identity: CandidateBoundPlanIdentity,
      plan: ValidatedEnginePlan,
      assets: PreparedInstallerAssets
    ) {
      self.identity = identity
      self.plan = plan
      self.assets = assets
    }

    public func approve(
      confirming confirmation: InstallerOwnerPlanConfirmation
    ) throws -> CandidateBoundPlanApproval {
      guard confirmation.bindingDigest == identity.bindingDigest,
        confirmation.planDigest == plan.planDigest,
        confirmation.deviceIdentifier == plan.deviceIdentifier,
        confirmation.storeIdentifier == plan.storeIdentifier,
        confirmation.sourceIdentifier == plan.sourceIdentifier,
        confirmation.offsetBytes == plan.offsetBytes,
        confirmation.lengthBytes == plan.lengthBytes,
        confirmation.requiredHumanSteps == plan.requiredHumanSteps
      else {
        throw InstallerPlanReviewError.ownerConfirmationMismatch
      }
      return CandidateBoundPlanApproval(
        identity: identity,
        approvedBindingDigest: confirmation.bindingDigest
      )
    }
  }

  public struct InstallerOwnerPlanConfirmation: Equatable, Sendable {
    public let bindingDigest: String
    public let planDigest: String
    public let deviceIdentifier: String
    public let storeIdentifier: String
    public let sourceIdentifier: String
    public let offsetBytes: UInt64
    public let lengthBytes: UInt64
    public let requiredHumanSteps: [String]

    public init(
      bindingDigest: String,
      planDigest: String,
      deviceIdentifier: String,
      storeIdentifier: String,
      sourceIdentifier: String,
      offsetBytes: UInt64,
      lengthBytes: UInt64,
      requiredHumanSteps: [String]
    ) {
      self.bindingDigest = bindingDigest
      self.planDigest = planDigest
      self.deviceIdentifier = deviceIdentifier
      self.storeIdentifier = storeIdentifier
      self.sourceIdentifier = sourceIdentifier
      self.offsetBytes = offsetBytes
      self.lengthBytes = lengthBytes
      self.requiredHumanSteps = requiredHumanSteps
    }
  }

  public enum InstallerNextAction: String, Equatable, Sendable {
    case continueInstallation
    case enterRecovery
    case attachInstallationMedia
    case verifyInstalledSystem
    case manualRecovery
  }

  public struct InstallerExecutionProgress: Equatable, Sendable {
    public let planDigest: String
    public let checkpoints: [ValidatedEngineCheckpoint]
    public let completion: EngineCompletionOutcome?
    public let nextAction: InstallerNextAction
    public let requiredHumanSteps: [String]

    public init(
      review: InstallerPlanReview,
      transcript: ValidatedEngineTranscript
    ) throws {
      guard transcript.deviceIdentifier == review.plan.deviceIdentifier,
        transcript.plan == review.plan
      else {
        throw InstallerPlanReviewError.executionTranscriptMismatch
      }

      planDigest = review.plan.planDigest
      checkpoints = transcript.checkpoints
      completion = transcript.completion
      requiredHumanSteps = review.plan.requiredHumanSteps
      switch transcript.completion {
      case .awaitingRecovery:
        nextAction = .enterRecovery
      case .awaitingMedia:
        nextAction = .attachInstallationMedia
      case .installed:
        nextAction = .verifyInstalledSystem
      case .manualRecoveryRequired:
        nextAction = .manualRecovery
      case nil:
        nextAction = .continueInstallation
      }
    }
  }
#endif
