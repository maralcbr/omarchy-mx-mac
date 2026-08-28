import Foundation

public struct ClosedEngineCandidateRequest: Sendable {
  public let planningTranscript: Data
  public let catalogPayload: Data
  public let catalogSignature: Data
  public let trustRoot: AppOwnedTrustRoot
  public let validationTime: Date
  public let previouslyAcceptedCatalog: AcceptedCatalogIdentity?

  public init(
    planningTranscript: Data,
    catalogPayload: Data,
    catalogSignature: Data,
    trustRoot: AppOwnedTrustRoot,
    validationTime: Date,
    previouslyAcceptedCatalog: AcceptedCatalogIdentity? = nil
  ) {
    self.planningTranscript = planningTranscript
    self.catalogPayload = catalogPayload
    self.catalogSignature = catalogSignature
    self.trustRoot = trustRoot
    self.validationTime = validationTime
    self.previouslyAcceptedCatalog = previouslyAcceptedCatalog
  }
}

public struct ClosedEngineInvocation: Sendable {
  public let candidateIdentity: CandidateBoundPlanIdentity
  public let plan: ValidatedEnginePlan
  public let pinnedInstaller: PinnedInstallerRecord
  public let catalogIdentity: AcceptedCatalogIdentity

  fileprivate init(
    candidateIdentity: CandidateBoundPlanIdentity,
    plan: ValidatedEnginePlan,
    pinnedInstaller: PinnedInstallerRecord,
    catalogIdentity: AcceptedCatalogIdentity
  ) {
    self.candidateIdentity = candidateIdentity
    self.plan = plan
    self.pinnedInstaller = pinnedInstaller
    self.catalogIdentity = catalogIdentity
  }
}

public enum EngineAuthorizationDecision: Equatable, Sendable {
  case granted
  case cancelled
}

public protocol EngineExecutionAuthorizing: Sendable {
  func decision(
    for invocation: ClosedEngineInvocation
  ) async -> EngineAuthorizationDecision
}

public protocol EngineProcessExecuting: Sendable {
  func execute(_ invocation: ClosedEngineInvocation) async throws -> Data
}

public enum ClosedEngineProcessError: Error, Equatable, Sendable {
  case authorizationCancelled
  case candidateIdentityMismatch
  case catalogPlanMismatch
  case planUnavailable
  case staleCandidateApproval
  case transcriptDeviceMismatch
  case transcriptIncomplete
  case transcriptPlanMismatch
  case unsupportedDevice(String)
}

public struct ClosedEngineProcessAdapter: Sendable {
  private static let explicitlyUnsupportedDevices = ["apple,j614s"]
  private let trustCore: AppleInstallerTrustCore

  public init() {
    trustCore = AppleInstallerTrustCore()
  }

  public func candidateIdentity(
    for request: ClosedEngineCandidateRequest
  ) throws -> CandidateBoundPlanIdentity {
    try prepare(request).candidateIdentity
  }

  public func execute(
    _ request: ClosedEngineCandidateRequest,
    approval: CandidateBoundPlanApproval,
    authorization: any EngineExecutionAuthorizing,
    process: any EngineProcessExecuting
  ) async throws -> ValidatedEngineTranscript {
    let invocation = try prepare(request)
    guard
      approval.approvedBindingDigest
        == approval.identity.bindingDigest
    else {
      throw ClosedEngineProcessError.staleCandidateApproval
    }
    guard approval.identity == invocation.candidateIdentity else {
      throw ClosedEngineProcessError.candidateIdentityMismatch
    }

    guard await authorization.decision(for: invocation) == .granted else {
      throw ClosedEngineProcessError.authorizationCancelled
    }

    let result = try await process.execute(invocation)
    let transcript = try trustCore.validateEngineTranscript(result)
    try validate(transcript, against: invocation)
    return transcript
  }

  private func prepare(
    _ request: ClosedEngineCandidateRequest
  ) throws -> ClosedEngineInvocation {
    let catalog = try trustCore.validateSupportCatalog(
      payload: request.catalogPayload,
      signature: request.catalogSignature,
      trustRoot: request.trustRoot,
      now: request.validationTime,
      previouslyAccepted: request.previouslyAcceptedCatalog
    )
    let transcript = try trustCore.validateEngineTranscript(
      request.planningTranscript
    )

    guard transcript.support == .supported,
      !Self.explicitlyUnsupportedDevices.contains(transcript.deviceIdentifier)
    else {
      throw ClosedEngineProcessError.unsupportedDevice(
        transcript.deviceIdentifier
      )
    }
    guard
      case .admitted(let pinnedInstaller) = catalog.admission(
        for: transcript.deviceIdentifier
      )
    else {
      throw ClosedEngineProcessError.unsupportedDevice(
        transcript.deviceIdentifier
      )
    }
    guard let plan = transcript.plan else {
      throw ClosedEngineProcessError.planUnavailable
    }
    guard plan.deviceIdentifier == transcript.deviceIdentifier,
      pinnedInstaller.engineVersion == nil
        || plan.engineVersion == pinnedInstaller.engineVersion,
      plan.engineDigest == pinnedInstaller.engineDigest,
      plan.metadataDigest == pinnedInstaller.metadataDigest,
      plan.payloadDigest == pinnedInstaller.payloadDigest
    else {
      throw ClosedEngineProcessError.catalogPlanMismatch
    }

    let candidateIdentity = CandidateBoundPlanIdentity(
      plan: plan,
      catalogIdentity: catalog.acceptedIdentity,
      trustRootFingerprint: request.trustRoot.fingerprint
    )
    return ClosedEngineInvocation(
      candidateIdentity: candidateIdentity,
      plan: plan,
      pinnedInstaller: pinnedInstaller,
      catalogIdentity: catalog.acceptedIdentity
    )
  }

  private func validate(
    _ transcript: ValidatedEngineTranscript,
    against invocation: ClosedEngineInvocation
  ) throws {
    guard transcript.deviceIdentifier == invocation.plan.deviceIdentifier else {
      throw ClosedEngineProcessError.transcriptDeviceMismatch
    }
    guard transcript.support == .supported,
      !Self.explicitlyUnsupportedDevices.contains(transcript.deviceIdentifier)
    else {
      throw ClosedEngineProcessError.unsupportedDevice(
        transcript.deviceIdentifier
      )
    }
    guard transcript.plan == invocation.plan else {
      throw ClosedEngineProcessError.transcriptPlanMismatch
    }
    guard transcript.completion != nil else {
      throw ClosedEngineProcessError.transcriptIncomplete
    }
  }
}
