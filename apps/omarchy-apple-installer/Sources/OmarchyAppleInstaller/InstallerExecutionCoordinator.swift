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
      InstallerDiagnosticLog.shared.record("authorization_requested")
      let submitter = try await TemporaryInstallerWorker.shared.ready(
        journalProgress: journalProgress)
      InstallerDiagnosticLog.shared.record("worker_ready")
      let process = ClosedEngineHandoffProcess(
        assets: prepared.review.assets,
        handoffDirectory: handoffDirectory,
        submitter: submitter,
        authorization: machineOwnerAuthorization,
        operation: operation
      )
      do {
        let result = try await execute(prepared, approval: approval, process: process)
        InstallerDiagnosticLog.shared.record("validated_execution_reply")
        await TemporaryInstallerWorker.shared.finish(submitter)
        InstallerDiagnosticLog.shared.record("worker_finish_returned")
        return result
      } catch {
        InstallerDiagnosticLog.shared.record("execution_failed", code: (error as NSError).code)
        // Credential correction and narrow Recovery retry reuse this worker.
        let submission = error as? EngineXPCSubmissionError
        if submission != .machineOwnerCredentialsRejected
          && submission != .recoveryAuthorizationFailed
        {
          await TemporaryInstallerWorker.shared.finish(submitter)
        }
        throw error
      }
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
