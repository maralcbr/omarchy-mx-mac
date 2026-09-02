import AppKit
import Foundation
import OmarchyAppleInstallerTrustCore
import OmarchyInstallerUXCore

/// The real installer environment.
///
/// It owns the trust objects the screens must never see — the host inspection,
/// the engine transcripts, the prepared plan, the review, the approval, and the
/// release configuration — and hands the UI only render-only display models.
/// Approval is always rebuilt from the retained review, never from a display
/// model, and no credential is ever stored here.
final class LiveInstallerEnvironment: InstallerEnvironment, @unchecked Sendable {
  private let lock = NSLock()
  private let helperService =
    InstallerHelperServiceManager.preinstalledSystemDaemon()

  private var hostInspection: AppleSiliconHostInspection?
  private var engineInspection: ValidatedEngineTranscript?
  private var engineInspectionTranscript: Data?
  private var engineInspectionFailure: String?
  private var planReview: InstallerPlanReview?
  private var preparedPlan: PreparedInstallerPlanExecution?
  private var planApproval: CandidateBoundPlanApproval?
  private var releaseConfiguration: InstallerReleaseConfiguration?

  // MARK: Fail-closed gates

  var installationBlocked: Bool {
    lock.withLock {
      guard let hostInspection else {
        return true
      }
      if case .blocked = hostInspection.eligibility {
        return true
      }
      return false
    }
  }

  var engineSupported: Bool {
    lock.withLock { engineInspection?.support == .supported }
  }

  var hasApprovedPlan: Bool {
    lock.withLock {
      preparedPlan != nil && planApproval != nil && releaseConfiguration != nil
    }
  }

  var helperStatus: HelperDisplay {
    let status = helperService.status
    return HelperDisplay(
      status: status,
      summary: PlainLanguage.helperSummary(status)
    )
  }

  // MARK: Inspection

  func inspect() async throws -> HostDisplay {
    let host = try await Task.detached(priority: .userInitiated) {
      try AppleSiliconHostInspector().inspect()
    }.value

    var engine: ValidatedEngineTranscript?
    var transcript: Data?
    var engineFailure: String?
    do {
      let inspection = try await EngineInspectionRunner().inspect()
      guard
        inspection.validated.deviceIdentifier == host.identity.deviceIdentifier
      else {
        engineFailure = PlainLanguage.engineIdentityMismatch
        throw InstallerAppError.hostChanged
      }
      engine = inspection.validated
      transcript = inspection.transcript
    } catch ValidationEngineArtifactError.unavailable {
      engineFailure = PlainLanguage.engineUnavailable
    } catch InstallerAppError.hostChanged {
      // engineFailure already set above.
    } catch {
      engineFailure =
        "Pinned engine inspection failed validation (\(String(describing: error))). Installation remains locked."
    }

    lock.withLock {
      hostInspection = host
      engineInspection = engine
      engineInspectionTranscript = transcript
      engineInspectionFailure = engineFailure
      planReview = nil
      preparedPlan = nil
      planApproval = nil
      releaseConfiguration = nil
    }

    return display(
      host: host,
      engine: engine,
      engineFailure: engineFailure,
      catalogSequence: nil
    )
  }

  // MARK: Plan preparation

  func preparePlan(
    selection: InstallTargetSelection,
    omarchyBytes: UInt64?,
    progress: @escaping @Sendable (AssetProgressUpdate) -> Void
  ) async throws -> PlanPreparationDisplay {
    let (host, hasTranscript) = lock.withLock {
      let retained = (hostInspection, engineInspectionTranscript != nil)
      planReview = nil
      preparedPlan = nil
      planApproval = nil
      releaseConfiguration = nil
      return retained
    }

    guard let host, hasTranscript else {
      throw InstallerAppError.inspectionRequired
    }

    progress(AssetProgressUpdate(stage: .fetchingCatalog))

    let configuration = try InstallerReleaseConfigurationLocator()
      .loadFromMainBundle()
    let workspace = try installerWorkspace()
    let catalogStore = AcceptedCatalogIdentityStore(directory: workspace.state)
    let previouslyAcceptedCatalog = try catalogStore.load()
    let validationTime = Date()

    let collector = StagingProgressCollector(publish: progress)
    let release = try await InstallerReleaseAssetCoordinator()
      .prepareRelease(
        InstallerReleasePreparationRequest(
          host: host,
          configuration: configuration,
          validationTime: validationTime,
          previouslyAcceptedCatalog: previouslyAcceptedCatalog,
          stagingDirectory: workspace.staging
        ),
        progress: { event in
          collector.record(event)
        }
      )
    try catalogStore.store(release.assets.catalogIdentity)

    progress(
      AssetProgressUpdate(stage: .inspectingEngine, rows: collector.rows())
    )

    let stagedEngine = release.assets.engine
    let archive = try PinnedAsahiEngineArchive(
      fileURL: stagedEngine.fileURL,
      expectedDigest: stagedEngine.artifact.expectedDigest,
      expectedSizeBytes: stagedEngine.artifact.expectedSizeBytes
    )
    let signedInspection = try await EngineInspectionRunner().inspect(archive)
    guard
      signedInspection.validated.deviceIdentifier
        == host.identity.deviceIdentifier,
      signedInspection.validated.support == .supported,
      let inventory = signedInspection.validated.inventory
    else {
      throw InstallerPlanPreparationError.unsupportedDevice(
        host.identity.deviceIdentifier
      )
    }

    progress(AssetProgressUpdate(stage: .planning, rows: collector.rows()))

    // Existing installs are never replaced silently: with no explicit
    // selection the choice goes back to the owner, and a replace plan is
    // built only for a candidate the engine itself surfaced.
    let replaceCandidates = inventory.candidates.filter { $0.kind == "replace" }
    let candidate: ValidatedEngineCandidate
    let requestedLengthBytes: UInt64
    switch selection {
    case .automatic where !replaceCandidates.isEmpty:
      return .existingInstallChoice(
        replaceCandidates.map { existing in
          ExistingInstallDisplay(
            sourceIdentifier: existing.sourceIdentifier,
            sizeDescription: PlainLanguage.bytes(existing.lengthBytes)
          )
        }
      )
    case .replaceExisting(let sourceIdentifier):
      guard
        let replace = replaceCandidates.first(where: {
          $0.sourceIdentifier == sourceIdentifier
        })
      else {
        throw InstallerAppError.existingInstallUnavailable
      }
      candidate = replace
      requestedLengthBytes = replace.lengthBytes
    case .automatic, .installAlongside:
      let recommendation = try InstallerAllocationRecommendation(
        inventory: inventory,
        targetBytes: omarchyBytes ?? InstallerAllocationRecommendation.balancedTargetBytes
      )
      candidate = recommendation.candidate
      requestedLengthBytes = recommendation.requestedLengthBytes
    }

    let prepared = try await InstallerPlanPreparationCoordinator()
      .prepareExecution(
        InstallerPlanPreparationRequest(
          host: host,
          release: release,
          configuration: configuration,
          inspectionTranscript: signedInspection.transcript,
          candidate: candidate,
          requestedLengthBytes: requestedLengthBytes,
          validationTime: validationTime,
          previouslyAcceptedCatalog: previouslyAcceptedCatalog,
          scratchDirectory: workspace.scratch
        )
      )

    lock.withLock {
      preparedPlan = prepared
      planReview = prepared.review
      releaseConfiguration = configuration
    }

    return .plan(Self.planDisplay(review: prepared.review, host: host))
  }

  // MARK: Approval

  /// The confirmation is rebuilt field by field from the retained review — the
  /// same values the Exact plan panel rendered — and `approve(confirming:)`
  /// re-checks every one of them.
  func approve() throws {
    let review = lock.withLock { planReview }

    guard let review else {
      throw InstallerAppError.approvalUnavailable
    }
    let confirmation = InstallerOwnerPlanConfirmation(
      bindingDigest: review.identity.bindingDigest,
      planDigest: review.plan.planDigest,
      deviceIdentifier: review.plan.deviceIdentifier,
      storeIdentifier: review.plan.storeIdentifier,
      sourceIdentifier: review.plan.sourceIdentifier,
      offsetBytes: review.plan.offsetBytes,
      lengthBytes: review.plan.lengthBytes,
      requiredHumanSteps: review.plan.requiredHumanSteps
    )
    do {
      let approval = try review.approve(confirming: confirmation)
      lock.withLock { planApproval = approval }
    } catch {
      lock.withLock { planApproval = nil }
      throw error
    }
  }

  func discardApproval() {
    lock.withLock { planApproval = nil }
  }

  // MARK: Helper

  func refreshHelperStatus() -> HelperDisplay {
    helperStatus
  }

  // MARK: Shutdown

  /// The graceful route: the same Apple Event the Apple menu sends. Apps with
  /// unsaved work can still object, and nothing here needs the privileged
  /// helper.
  func requestShutdown() -> Bool {
    let target = NSAppleEventDescriptor(
      bundleIdentifier: "com.apple.loginwindow"
    )
    let event = NSAppleEventDescriptor(
      eventClass: AEEventClass(kCoreEventClass),
      eventID: AEEventID(kAEShutDown),
      targetDescriptor: target,
      returnID: AEReturnID(kAutoGenerateReturnID),
      transactionID: AETransactionID(kAnyTransactionID)
    )
    do {
      _ = try event.sendEvent(options: [.noReply], timeout: 3)
      return true
    } catch {
      return false
    }
  }

  // MARK: Execution

  func execute(
    operation: InstallOperationKind,
    authorization: MachineOwnerAuthorization,
    journal: @escaping @Sendable (Data) -> Void
  ) async throws -> CompletionDisplay {
    let (prepared, approval, configuration, host) = lock.withLock {
      (preparedPlan, planApproval, releaseConfiguration, hostInspection)
    }

    guard let prepared, let approval, let configuration, let host else {
      throw InstallerAppError.approvalUnavailable
    }

    // Re-inspection identity match: the Mac that is about to be written to
    // must still be the Mac the plan was bound to.
    let currentHost = try AppleSiliconHostInspector().inspect()
    guard
      currentHost.identity.deviceIdentifier == host.identity.deviceIdentifier
    else {
      throw InstallerAppError.hostChanged
    }

    let workspace = try installerWorkspace()
    let coordinator = InstallerExecutionCoordinator()
    let progress: InstallerExecutionProgress
    switch operation {
    case .install:
      progress = try await coordinator.execute(
        prepared,
        approval: approval,
        configuration: configuration,
        handoffDirectory: workspace.handoff,
        machineOwnerAuthorization: authorization,
        journalProgress: journal
      )
    case .retryRecoveryAuthorization:
      progress = try await coordinator.retryRecoveryAuthorization(
        prepared,
        approval: approval,
        configuration: configuration,
        handoffDirectory: workspace.handoff,
        machineOwnerAuthorization: authorization,
        journalProgress: journal
      )
    }
    return Self.completionDisplay(progress)
  }

  // MARK: Display mapping

  private func display(
    host: AppleSiliconHostInspection,
    engine: ValidatedEngineTranscript?,
    engineFailure: String?,
    catalogSequence: UInt64?
  ) -> HostDisplay {
    let blocked: Bool
    if case .blocked = host.eligibility {
      blocked = true
    } else {
      blocked = false
    }
    let required = InstallerAllocationRecommendation.balancedTargetBytes
    let helper = helperStatus
    let engineValue: String
    if let engine {
      engineValue =
        engine.support == .supported
        ? "Verified • supported" : "Verified • unsupported"
    } else {
      engineValue = engineFailure == nil ? "Pending" : "Unavailable • locked"
    }

    let checks = [
      PreflightCheck(
        id: "model",
        label: "Model",
        value: "\(host.identity.model) (\(host.identity.chip))",
        satisfied: !blocked,
        tooltip:
          "Support is per exact model. The list is signed and fails closed."
      ),
      PreflightCheck(
        id: "macos",
        label: "MacOS",
        value: host.macOSVersion,
        satisfied: true,
        tooltip: "A current MacOS is required for the Recovery handoff."
      ),
      PreflightCheck(
        id: "power",
        label: "Power",
        value: host.powerSource == .ac ? "Connected" : "On battery",
        satisfied: host.powerSource == .ac,
        tooltip:
          "The install writes many gigabytes. Wall power avoids surprises."
      ),
      PreflightCheck(
        id: "filevault",
        label: "FileVault",
        value: host.fileVaultEnabled ? "On, stays on" : "Off",
        satisfied: true,
        tooltip: "Read only. Your MacOS data stays encrypted."
      ),
      PreflightCheck(
        id: "space",
        label: "Free space",
        value:
          "\(PlainLanguage.bytes(host.storage.containerFreeBytes)) · \(PlainLanguage.bytes(required)) needed",
        satisfied: host.storage.containerFreeBytes >= required,
        tooltip:
          "Omarchy takes a fixed \(PlainLanguage.bytes(required)). The engine confirms the real minimum before planning."
      ),
      PreflightCheck(
        id: "engine",
        label: "Engine",
        value: engineValue,
        satisfied: engine?.support == .supported,
        tooltip:
          "A pinned, checksum-verified build of the Asahi installer does the disk work."
      ),
      PreflightCheck(
        id: "helper",
        label: "Helper",
        value: helper.summary,
        satisfied: helper.isEnabled,
        tooltip:
          "Does the privileged work. Installed as a system service by the installer package."
      ),
      PreflightCheck(
        id: "downloads",
        label: "Downloads",
        value: catalogSequence.map { "Verified, catalog \($0)" }
          ?? "Awaiting signed catalog",
        satisfied: catalogSequence != nil,
        tooltip:
          "Every file is checked against a signed catalog before use."
      ),
    ]

    return HostDisplay(
      modelName: host.identity.model,
      chipAndSpace:
        "\(host.identity.chip) · \(PlainLanguage.bytes(host.storage.containerFreeBytes)) free",
      deviceIdentifier: host.identity.deviceIdentifier,
      supported: !blocked && engine?.support == .supported,
      checks: checks,
      helper: helper,
      blockingReason: blockingReason(host: host, engineFailure: engineFailure)
    )
  }

  private func blockingReason(
    host: AppleSiliconHostInspection,
    engineFailure: String?
  ) -> String? {
    if case .blocked(let reason) = host.eligibility {
      return reason
    }
    return engineFailure
  }

  static func planDisplay(
    review: InstallerPlanReview,
    host: AppleSiliconHostInspection
  ) -> PlanDisplay {
    let length = review.plan.lengthBytes
    let total = max(host.storage.containerSizeBytes, length)
    let assets = review.assets
    var artifacts = [
      PlanArtifactDisplay(
        role: assets.payload.artifact.role,
        fileName: assets.payload.artifact.fileName,
        expectedBytes: assets.payload.artifact.expectedSizeBytes
      ),
      PlanArtifactDisplay(
        role: assets.metadata.artifact.role,
        fileName: assets.metadata.artifact.fileName,
        expectedBytes: assets.metadata.artifact.expectedSizeBytes
      ),
      PlanArtifactDisplay(
        role: assets.engine.artifact.role,
        fileName: assets.engine.artifact.fileName,
        expectedBytes: assets.engine.artifact.expectedSizeBytes
      ),
    ]
    if let repair = assets.repairManifest {
      artifacts.append(
        PlanArtifactDisplay(
          role: repair.artifact.role,
          fileName: repair.artifact.fileName,
          expectedBytes: repair.artifact.expectedSizeBytes
        )
      )
    }

    let files =
      artifacts
      .map { "\($0.fileName) \(PlainLanguage.bytes($0.expectedBytes))" }
      .joined(separator: " · ")

    let facts = [
      PlanFactRow(label: "Device", value: review.plan.deviceIdentifier),
      PlanFactRow(
        label: "Store",
        value:
          "\(review.plan.storeIdentifier) · \(review.plan.candidateKind) \(review.plan.sourceIdentifier)"
      ),
      PlanFactRow(
        label: "Offset",
        value: PlainLanguage.exactBytes(review.plan.offsetBytes)
      ),
      PlanFactRow(
        label: "Length",
        value:
          "\(PlainLanguage.exactBytes(length)) (\(PlainLanguage.bytes(length)))"
      ),
      PlanFactRow(label: "Engine", value: review.plan.engineVersion),
      PlanFactRow(label: "Files", value: files + ", each verified (SHA-256)"),
      PlanFactRow(
        label: "Catalog",
        value: "sequence \(assets.catalogIdentity.sequence)"
      ),
      PlanFactRow(
        label: "Plan digest",
        value: review.plan.planDigest,
        isMonospaced: true
      ),
      PlanFactRow(
        label: "Binding",
        value: review.identity.bindingDigest,
        isMonospaced: true
      ),
      PlanFactRow(
        label: "Rollback",
        value:
          "MacOS untouched until approval; every write is checkpointed and journaled"
      ),
    ]

    return PlanDisplay(
      headline: "\(PlainLanguage.bytes(length)) for Omarchy",
      subheadline: PlainLanguage.planSubheadline,
      diskTotalBytes: total,
      omarchyBytes: length,
      macOSBytes: total > length ? total - length : 0,
      bindingDigest: review.identity.bindingDigest,
      planDigest: review.plan.planDigest,
      artifacts: artifacts,
      facts: facts
    )
  }

  static func completionDisplay(
    _ progress: InstallerExecutionProgress
  ) -> CompletionDisplay {
    let handoff: HandoffDisplay?
    switch progress.nextAction {
    case .enterRecovery:
      handoff = HandoffDisplay(
        headline: PlainLanguage.recoveryHeadline,
        subheadline: PlainLanguage.recoverySubheadline,
        steps: PlainLanguage.recoverySteps(for: progress.requiredHumanSteps),
        explainer: PlainLanguage.recoveryExplainer,
        hint: ""
      )
    case .attachInstallationMedia:
      handoff = HandoffDisplay(
        headline: PlainLanguage.mediaHeadline,
        subheadline: PlainLanguage.mediaSubheadline,
        steps: PlainLanguage.recoverySteps(for: progress.requiredHumanSteps),
        explainer: PlainLanguage.recoveryExplainer,
        hint: ""
      )
    default:
      handoff = nil
    }

    return CompletionDisplay(
      nextAction: progress.nextAction,
      headline: progress.nextAction == .verifyInstalledSystem
        ? PlainLanguage.doneHeadline : PlainLanguage.recoveryHeadline,
      subheadline: PlainLanguage.nextActionMessage(progress.nextAction),
      verified: PlainLanguage.doneVerifiedRows,
      handoff: handoff
    )
  }

  // MARK: Workspace

  private func installerWorkspace() throws
    -> (staging: URL, scratch: URL, state: URL, handoff: URL)
  {
    guard
      let applicationSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw InstallerAppError.workspaceUnavailable
    }
    let base = applicationSupport.appendingPathComponent(
      "com.omarchy.mx.installer",
      isDirectory: true
    )
    let staging = base.appendingPathComponent("staging", isDirectory: true)
    let scratch = base.appendingPathComponent("scratch", isDirectory: true)
    let state = base.appendingPathComponent("state", isDirectory: true)
    let handoff = base.appendingPathComponent("handoff", isDirectory: true)
    try createPrivateDirectoryIfMissing(base)
    try createPrivateDirectoryIfMissing(staging)
    try createPrivateDirectoryIfMissing(scratch)
    try createPrivateDirectoryIfMissing(state)
    try createPrivateDirectoryIfMissing(handoff)
    return (staging, scratch, state, handoff)
  }

  private func createPrivateDirectoryIfMissing(_ directory: URL) throws {
    guard !FileManager.default.fileExists(atPath: directory.path) else {
      return
    }
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
  }
}

/// Collects `ArtifactStagingProgress` events by role and republishes them as
/// preparing-screen rows.
private final class StagingProgressCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var latest = [String: ArtifactStagingProgress]()
  private let publish: @Sendable (AssetProgressUpdate) -> Void

  init(publish: @escaping @Sendable (AssetProgressUpdate) -> Void) {
    self.publish = publish
  }

  func record(_ event: ArtifactStagingProgress) {
    let snapshot = lock.withLock { () -> [AssetProgressRow] in
      latest[event.role] = event
      return rowsLocked()
    }
    publish(AssetProgressUpdate(stage: .downloading, rows: snapshot))
  }

  func rows() -> [AssetProgressRow] {
    lock.withLock { rowsLocked() }
  }

  private func rowsLocked() -> [AssetProgressRow] {
    latest.values
      .sorted { $0.role < $1.role }
      .map { progress in
        AssetProgressRow(
          role: progress.role,
          fileName: progress.fileName,
          bytesCompleted: progress.bytesCompleted,
          totalBytes: progress.totalBytes,
          phase: progress.phase,
          partIndex: progress.partIndex,
          partCount: progress.partCount
        )
      }
  }
}
