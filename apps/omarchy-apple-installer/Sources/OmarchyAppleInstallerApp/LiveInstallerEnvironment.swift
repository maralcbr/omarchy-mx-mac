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
  private var reusableAssets: PreparedInstallerAssets?
  private var releaseConfiguration: InstallerReleaseConfiguration?
  private var encryptLinuxDisk = true
  private var selectedLane = ReleaseChannel.stable.rawValue
  private let prefetch = PayloadPrefetchOrchestrator()

  var payloadPrefetchRequired: Bool { true }

  var payloadPrefetchState: PayloadPrefetchState {
    prefetch.currentState()
  }
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
    HelperDisplay(status: helperService.status)
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
        "The disk compatibility check failed. Installation is unavailable. Details: \(String(describing: error))"
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
    cancelPayloadPrefetch()

    return display(host: host, engine: engine, engineFailure: engineFailure)
  }

  // MARK: Plan preparation

  func preparePlan(
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
    let channel = ReleaseChannelPreference().resolve(configuration: configuration)
    let catalogStore = AcceptedCatalogIdentityStore(
      directory: workspace.state,
      channel: channel
    )
    let previouslyAcceptedCatalog = try catalogStore.load()
    let validationTime = Date()

    let collector = StagingProgressCollector(publish: progress)
    let release = try await InstallerReleaseAssetCoordinator()
      .prepareRelease(
        InstallerReleasePreparationRequest(
          host: host,
          configuration: configuration,
          channel: channel,
          validationTime: validationTime,
          previouslyAcceptedCatalog: previouslyAcceptedCatalog,
          installerVersion: InstallerVersion.current(),
          stagingDirectory: workspace.staging
        ),
        progress: { event in
          collector.record(event)
        },
        previouslyPrepared: lock.withLock { reusableAssets },
        includePayload: false
      )
    lock.withLock {
      reusableAssets = release.assets
      selectedLane = channel.rawValue
    }
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

    // Existing installs are never replaced or joined: report them and let
    // the session refuse.
    let existing = Self.existingInstalls(in: signedInspection.validated)
    if !existing.isEmpty {
      return .existingInstallChoice(existing)
    }
    let recommendation = try InstallerAllocationRecommendation(
      inventory: inventory,
      targetBytes: omarchyBytes ?? InstallerAllocationRecommendation.balancedTargetBytes,
      reservedBytes: release.assets.additionalHandoffBytes,
      snapshotConstraint: {
        APFSSnapshotInspector().constraint(in: host.storage)
      }
    )
    let candidate = recommendation.candidate
    let requestedLengthBytes = recommendation.requestedLengthBytes

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
    beginPayloadPrefetch(release.assets.payload)

    return .plan(
      Self.planDisplay(
        review: prepared.review, host: host, recommendation: recommendation,
        release:
          "\(channel.rawValue.capitalized) · \(release.assets.payload.fileURL.lastPathComponent)"
      ))
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

  func setEncryptLinuxDisk(_ encrypt: Bool) {
    lock.withLock { encryptLinuxDisk = encrypt }
  }

  func cancelPayloadPrefetch() {
    prefetch.cancel()
  }

  func prefetchPayload(
    progress: @escaping @Sendable (PayloadPrefetchState) -> Void
  ) async throws {
    try await prefetch.waitUntilVerified(progress: progress)
  }

  func waitUntilPayloadVerified() async throws {
    try await prefetch.waitUntilVerified(progress: { _ in })
  }

  private func beginPayloadPrefetch(_ payload: StagedInstallerArtifact) {
    prefetch.begin(payload: payload)
  }

  private func recordInstallConf(
    configuration: InstallerReleaseConfiguration,
    plan: ValidatedEnginePlan,
    authorization: MachineOwnerAuthorization,
    encrypt: Bool
  ) async -> InstallConfHandoff {
    let lane = lock.withLock { selectedLane }
    guard let conf = try? InstallConf(encrypt: encrypt, lane: lane) else {
      return .notRecorded
    }
    do {
      let submitter = try AuthenticatedEngineXPCSubmitter(
        machServiceName: configuration.helperMachServiceName,
        helperCodeSigningRequirement: configuration.helperCodeSigningRequirement
      )
      let helper = AuthorizedInstallConfESPHelper(
        submitter: submitter,
        authorization: authorization
      )
      return await InstallConfESPWriter(helper: helper).record(
        conf,
        storeIdentifier: plan.storeIdentifier,
        offsetBytes: plan.offsetBytes,
        lengthBytes: plan.lengthBytes
      )
    } catch {
      return .notRecorded
    }
  }

  // MARK: Execution

  func execute(
    operation: InstallOperationKind,
    authorization: MachineOwnerAuthorization,
    encryptLinuxDisk: Bool,
    journal: @escaping @Sendable (Data) -> Void
  ) async throws -> CompletionDisplay {
    let executionStarted = ProcessInfo.processInfo.systemUptime
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
    var installConf: InstallConfHandoff = .recorded
    let handoffOperation: EngineHandoffOperation =
      operation == .retryRecoveryAuthorization ? .retryRecoveryAuthorization : .install
    if InstallConfRecordPolicy.shouldRecord(
      operation: handoffOperation, nextAction: progress.nextAction)
    {
      installConf = await recordInstallConf(
        configuration: configuration,
        plan: prepared.review.plan,
        authorization: authorization,
        encrypt: encryptLinuxDisk
      )
      if operation == .install {
        InstallationTimingHistory.recordCompleted(
          seconds: ProcessInfo.processInfo.systemUptime - executionStarted)
      }
    }
    return Self.completionDisplay(progress, installConf: installConf)
  }

  // MARK: Display mapping

  private func display(
    host: AppleSiliconHostInspection,
    engine: ValidatedEngineTranscript?,
    engineFailure: String?
  ) -> HostDisplay {
    let blocked: Bool
    if case .blocked = host.eligibility {
      blocked = true
    } else {
      blocked = false
    }

    let existing = Self.existingInstalls(in: engine)
    let space = existing.isEmpty ? Self.spaceCheck(engine: engine, host: host) : nil
    var chipAndSpace =
      "\(host.identity.chip) · \(PlainLanguage.bytes(host.storage.containerFreeBytes)) free"
    if case .fits(let maximumBytes) = space {
      chipAndSpace += " · up to \(PlainLanguage.bytes(maximumBytes)) for Omarchy"
    }

    return HostDisplay(
      chipAndSpace: chipAndSpace,
      supported: !blocked && engine?.support == .supported,
      blockingReason: blockingReason(host: host, engineFailure: engineFailure),
      existingInstalls: existing,
      spaceShortfall: space?.shortfall
    )
  }

  private enum SpaceCheck {
    case fits(maximumBytes: UInt64)
    case shortfall(InstallerAllocationRecommendationError)

    var shortfall: InstallerAllocationRecommendationError? {
      if case .shortfall(let error) = self { error } else { nil }
    }
  }

  /// Runs the allocation recommendation on the bundled engine's inventory, so
  /// a disk that cannot hold Omarchy is reported before the catalog is fetched
  /// or the release downloaded. The handoff reserve is not known yet, so this
  /// can only be more generous than the check after the download.
  private static func spaceCheck(
    engine: ValidatedEngineTranscript?,
    host: AppleSiliconHostInspection
  ) -> SpaceCheck? {
    guard engine?.support == .supported, let inventory = engine?.inventory else {
      return nil
    }
    do {
      let recommendation = try InstallerAllocationRecommendation(
        inventory: inventory,
        snapshotConstraint: { APFSSnapshotInspector().constraint(in: host.storage) }
      )
      return .fits(maximumBytes: recommendation.maximumBytes)
    } catch let error as InstallerAllocationRecommendationError {
      return .shortfall(error)
    } catch {
      return nil
    }
  }

  /// Existing Omarchy installs the bundled engine's inventory reports as
  /// replace candidates. Read at the welcome stage, so the installer can
  /// refuse before it fetches the catalog or downloads anything.
  static func existingInstalls(
    in engine: ValidatedEngineTranscript?
  ) -> [ExistingInstallDisplay] {
    guard let inventory = engine?.inventory else {
      return []
    }
    return inventory.candidates
      .filter { $0.kind == "replace" }
      .map { existing in
        ExistingInstallDisplay(
          sourceIdentifier: existing.sourceIdentifier,
          sizeDescription: PlainLanguage.bytes(existing.lengthBytes)
        )
      }
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
    host: AppleSiliconHostInspection,
    recommendation: InstallerAllocationRecommendation,
    release: String
  ) -> PlanDisplay {
    let length = review.plan.lengthBytes
    let total =
      review.plan.candidateKind == "free"
      ? host.storage.containerSizeBytes + recommendation.candidate.lengthBytes
      : max(host.storage.containerSizeBytes, length)

    return PlanDisplay(
      diskTotalBytes: total,
      omarchyBytes: length,
      bindingDigest: review.identity.bindingDigest,
      isResizable: review.plan.candidateKind != "replace",
      minimumBytes: recommendation.minimumBytes,
      maximumBytes: recommendation.maximumBytes,
      releaseDescription: release,
      targetDescription:
        "Internal storage · \(review.plan.candidateKind == "free" ? "Use free space" : "Resize macOS")",
      fixedMacOSBytes: review.plan.candidateKind == "free" ? host.storage.containerSizeBytes : nil
    )
  }

  static func completionDisplay(
    _ progress: InstallerExecutionProgress,
    installConf: InstallConfHandoff = .recorded
  ) -> CompletionDisplay {
    let handoff: HandoffDisplay?
    let warning = PlainLanguage.installConfWarning(installConf)
    switch progress.nextAction {
    case .enterRecovery:
      handoff = HandoffDisplay(
        headline: PlainLanguage.recoveryHeadline,
        steps: PlainLanguage.recoverySteps(for: progress.requiredHumanSteps),
        warning: warning
      )
    case .attachInstallationMedia:
      handoff = HandoffDisplay(
        headline: PlainLanguage.mediaHeadline,
        steps: PlainLanguage.recoverySteps(for: progress.requiredHumanSteps),
        warning: warning
      )
    default:
      handoff = nil
    }

    return CompletionDisplay(
      nextAction: progress.nextAction,
      headline: progress.nextAction == .verifyInstalledSystem
        ? PlainLanguage.doneHeadline : PlainLanguage.recoveryHeadline,
      subheadline: PlainLanguage.nextActionMessage(
        progress.nextAction, installConf: installConf),
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
      return AssetProgressRow.rows(from: latest)
    }
    publish(AssetProgressUpdate(stage: .downloading, rows: snapshot))
  }

  func rows() -> [AssetProgressRow] {
    lock.withLock { AssetProgressRow.rows(from: latest) }
  }
}
