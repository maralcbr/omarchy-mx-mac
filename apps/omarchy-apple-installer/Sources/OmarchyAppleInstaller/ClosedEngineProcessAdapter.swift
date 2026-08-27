import Foundation

public struct ClosedEngineRequest: Sendable {
  public let planningTranscript: Data
  public let approvedPlanDigest: String
  public let catalogPayload: Data
  public let catalogSignature: Data
  public let catalogPublicKey: Data
  public let validationTime: Date
  public let previouslyAcceptedCatalog: AcceptedCatalogIdentity?

  public init(
    planningTranscript: Data,
    approvedPlanDigest: String,
    catalogPayload: Data,
    catalogSignature: Data,
    catalogPublicKey: Data,
    validationTime: Date,
    previouslyAcceptedCatalog: AcceptedCatalogIdentity? = nil
  ) {
    self.planningTranscript = planningTranscript
    self.approvedPlanDigest = approvedPlanDigest
    self.catalogPayload = catalogPayload
    self.catalogSignature = catalogSignature
    self.catalogPublicKey = catalogPublicKey
    self.validationTime = validationTime
    self.previouslyAcceptedCatalog = previouslyAcceptedCatalog
  }
}

public struct ClosedEngineInvocation: Sendable {
  public let plan: ValidatedEnginePlan
  public let pinnedInstaller: PinnedInstallerRecord
  public let catalogIdentity: AcceptedCatalogIdentity

  fileprivate init(
    plan: ValidatedEnginePlan,
    pinnedInstaller: PinnedInstallerRecord,
    catalogIdentity: AcceptedCatalogIdentity
  ) {
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
  case catalogPlanMismatch
  case planUnavailable
  case stalePlanApproval
  case transcriptDeviceMismatch
  case transcriptPlanMismatch
  case unsupportedDevice(String)
}

public struct ClosedEngineProcessAdapter: Sendable {
  private static let explicitlyUnsupportedDevices = ["apple,j614s"]
  private let trustCore: AppleInstallerTrustCore

  public init() {
    trustCore = AppleInstallerTrustCore()
  }

  public func execute(
    _ request: ClosedEngineRequest,
    authorization: any EngineExecutionAuthorizing,
    process: any EngineProcessExecuting
  ) async throws -> ValidatedEngineTranscript {
    let invocation = try prepare(request)

    guard await authorization.decision(for: invocation) == .granted else {
      throw ClosedEngineProcessError.authorizationCancelled
    }

    let result = try await process.execute(invocation)
    let transcript = try trustCore.validateEngineTranscript(result)
    try validate(transcript, against: invocation)
    return transcript
  }

  private func prepare(
    _ request: ClosedEngineRequest
  ) throws -> ClosedEngineInvocation {
    let catalog = try trustCore.validateSupportCatalog(
      payload: request.catalogPayload,
      signature: request.catalogSignature,
      publicKey: request.catalogPublicKey,
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
    guard case .admitted(let pinnedInstaller) = catalog.admission(
      for: transcript.deviceIdentifier
    ) else {
      throw ClosedEngineProcessError.unsupportedDevice(
        transcript.deviceIdentifier
      )
    }
    guard let plan = transcript.plan else {
      throw ClosedEngineProcessError.planUnavailable
    }
    guard request.approvedPlanDigest == plan.planDigest else {
      throw ClosedEngineProcessError.stalePlanApproval
    }
    guard plan.deviceIdentifier == transcript.deviceIdentifier,
      plan.engineDigest == pinnedInstaller.engineDigest,
      plan.metadataDigest == pinnedInstaller.metadataDigest,
      plan.payloadDigest == pinnedInstaller.payloadDigest
    else {
      throw ClosedEngineProcessError.catalogPlanMismatch
    }

    return ClosedEngineInvocation(
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
  }
}
