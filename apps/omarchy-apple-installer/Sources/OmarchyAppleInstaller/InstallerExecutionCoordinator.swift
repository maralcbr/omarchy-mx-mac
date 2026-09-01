#if os(macOS)
  import Foundation

  public struct InstallerExecutionCoordinator: Sendable {
    private let processAdapter = ClosedEngineProcessAdapter()

    public init() {}

    public func execute(
      _ prepared: PreparedInstallerPlanExecution,
      approval: CandidateBoundPlanApproval,
      configuration: InstallerReleaseConfiguration,
      handoffDirectory: URL,
      machineOwnerAuthorization: MachineOwnerAuthorization,
      journalProgress: (@Sendable (Data) -> Void)? = nil
    ) async throws -> InstallerExecutionProgress {
      try await execute(
        prepared,
        approval: approval,
        configuration: configuration,
        handoffDirectory: handoffDirectory,
        machineOwnerAuthorization: machineOwnerAuthorization,
        operation: .install,
        journalProgress: journalProgress
      )
    }

    public func retryRecoveryAuthorization(
      _ prepared: PreparedInstallerPlanExecution,
      approval: CandidateBoundPlanApproval,
      configuration: InstallerReleaseConfiguration,
      handoffDirectory: URL,
      machineOwnerAuthorization: MachineOwnerAuthorization,
      journalProgress: (@Sendable (Data) -> Void)? = nil
    ) async throws -> InstallerExecutionProgress {
      try await execute(
        prepared,
        approval: approval,
        configuration: configuration,
        handoffDirectory: handoffDirectory,
        machineOwnerAuthorization: machineOwnerAuthorization,
        operation: .retryRecoveryAuthorization,
        journalProgress: journalProgress
      )
    }

    private func execute(
      _ prepared: PreparedInstallerPlanExecution,
      approval: CandidateBoundPlanApproval,
      configuration: InstallerReleaseConfiguration,
      handoffDirectory: URL,
      machineOwnerAuthorization: MachineOwnerAuthorization,
      operation: EngineHandoffOperation,
      journalProgress: (@Sendable (Data) -> Void)?
    ) async throws -> InstallerExecutionProgress {
      let submitter = try AuthenticatedEngineXPCSubmitter(
        machServiceName: configuration.helperMachServiceName,
        helperCodeSigningRequirement:
          configuration.helperCodeSigningRequirement,
        journalProgress: journalProgress
      )
      let process = ClosedEngineHandoffProcess(
        assets: prepared.review.assets,
        handoffDirectory: handoffDirectory,
        submitter: submitter,
        authorization: machineOwnerAuthorization,
        operation: operation
      )
      return try await execute(
        prepared,
        approval: approval,
        process: process
      )
    }

    func execute(
      _ prepared: PreparedInstallerPlanExecution,
      approval: CandidateBoundPlanApproval,
      process: any EngineProcessExecuting
    ) async throws -> InstallerExecutionProgress {
      let transcript = try await processAdapter.execute(
        prepared.candidateRequest,
        approval: approval,
        authorization: CandidateBoundExecutionAuthorization(
          approval: approval
        ),
        process: process
      )
      return try InstallerExecutionProgress(
        review: prepared.review,
        transcript: transcript
      )
    }
  }

  private struct CandidateBoundExecutionAuthorization:
    EngineExecutionAuthorizing
  {
    let approval: CandidateBoundPlanApproval

    func decision(
      for invocation: ClosedEngineInvocation
    ) async -> EngineAuthorizationDecision {
      guard approval.identity == invocation.candidateIdentity,
        approval.approvedBindingDigest
          == invocation.candidateIdentity.bindingDigest
      else {
        return .cancelled
      }
      return .granted
    }
  }
#endif
