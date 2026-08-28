import OmarchyAppleInstallerTrustCore
import SwiftUI

@main
struct OmarchyAppleInstallerApp: App {
  var body: some Scene {
    WindowGroup("Omarchy MX Mac Installer") {
      InstallerRootView()
        .frame(minWidth: 960, minHeight: 640)
    }
    .defaultSize(width: 1080, height: 720)
  }
}

private struct InstallerRootView: View {
  @Environment(\.scenePhase) private var scenePhase
  private let workflow = InstallerWorkflow()
  private let helperService = InstallerHelperServiceManager.bundledDaemon()
  @State private var selectedStepID = "inspect"
  @State private var hostInspection: AppleSiliconHostInspection?
  @State private var engineInspection: ValidatedEngineTranscript?
  @State private var engineInspectionTranscript: Data?
  @State private var planReview: InstallerPlanReview?
  @State private var preparedPlan: PreparedInstallerPlanExecution?
  @State private var planApproval: CandidateBoundPlanApproval?
  @State private var releaseConfiguration: InstallerReleaseConfiguration?
  @State private var executionProgress: InstallerExecutionProgress?
  @State private var ownerAcknowledged = false
  @State private var inspectionError: String?
  @State private var engineInspectionError: String?
  @State private var planPreparationError: String?
  @State private var helperServiceStatus = InstallerHelperServiceStatus.unknown
  @State private var helperRegistrationError: String?
  @State private var executionError: String?
  @State private var isInspecting = true
  @State private var isPreparingPlan = false
  @State private var isExecuting = false
  @State private var hasExecutionStarted = false
  @State private var showsHelperConfirmation = false
  @State private var showsExecutionConfirmation = false

  private var snapshot: InstallerWorkflowSnapshot {
    if let hostInspection {
      workflow.preview(for: hostInspection)
    } else {
      workflow.referenceM1ProPreview()
    }
  }

  private var selectedStep: InstallerWorkflowStep {
    snapshot.steps.first { $0.id == selectedStepID } ?? snapshot.steps[0]
  }

  private var installationBlocked: Bool {
    snapshot.blockedReason != nil
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      HStack(spacing: 0) {
        stepList
        Divider()
        detail
      }
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .task {
      helperServiceStatus = helperService.status
      await inspectThisMac()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        helperServiceStatus = helperService.status
      }
    }
    .confirmationDialog(
      "Register the privileged installer helper?",
      isPresented: $showsHelperConfirmation,
      titleVisibility: .visible
    ) {
      Button("Register helper") {
        registerHelperAfterConfirmation()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "macOS will request administrator approval. This does not start the installation or change a disk."
      )
    }
    .confirmationDialog(
      "Start the exact approved installation?",
      isPresented: $showsExecutionConfirmation,
      titleVisibility: .visible
    ) {
      Button("Start installation", role: .destructive) {
        Task { await executeApprovedPlan() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "This authorizes the privileged helper to apply the reviewed disk extent. Do not continue without a current backup."
      )
    }
  }

  private var header: some View {
    HStack(spacing: 18) {
      ZStack {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .fill(Color.accentColor.gradient)
          .frame(width: 58, height: 58)
        Image(systemName: "laptopcomputer.and.arrow.down")
          .font(.system(size: 26, weight: .semibold))
          .foregroundStyle(.white)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text("Omarchy MX Mac Installer")
          .font(.system(size: 25, weight: .semibold))
        Text("Prepare Apple Silicon for a verified Omarchy installation")
          .foregroundStyle(.secondary)
      }

      Spacer()

      Label(
        installationBlocked ? "INSTALLATION LOCKED" : "SAFE PREVIEW",
        systemImage: installationBlocked ? "xmark.shield" : "lock.shield"
      )
      .font(.caption.weight(.bold))
      .foregroundStyle(installationBlocked ? .red : .orange)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        (installationBlocked ? Color.red : Color.orange).opacity(0.12),
        in: Capsule()
      )
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 20)
  }

  private var stepList: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        Text("THIS MAC")
          .font(.caption.weight(.bold))
          .foregroundStyle(.secondary)
        Text(isInspecting ? "Inspecting…" : snapshot.deviceName)
          .font(.headline)
        Text(isInspecting ? "read-only preflight" : snapshot.deviceIdentifier)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }
      .padding(22)

      ScrollView {
        VStack(spacing: 6) {
          ForEach(Array(snapshot.steps.enumerated()), id: \.element.id) { index, step in
            Button {
              selectedStepID = step.id
            } label: {
              stepRow(number: index + 1, step: step)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 12)
      }

      Spacer(minLength: 12)

      HStack(spacing: 8) {
        Image(systemName: "externaldrive.badge.xmark")
        Text("Disk mutation disabled")
      }
      .font(.caption.weight(.medium))
      .foregroundStyle(.secondary)
      .padding(20)
    }
    .frame(width: 350)
    .background(Color.secondary.opacity(0.045))
  }

  private func stepRow(
    number: Int,
    step: InstallerWorkflowStep
  ) -> some View {
    HStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(selectedStepID == step.id ? Color.accentColor : Color.secondary.opacity(0.13))
          .frame(width: 30, height: 30)
        Text(String(number))
          .font(.caption.weight(.bold))
          .foregroundStyle(selectedStepID == step.id ? .white : .secondary)
      }

      VStack(alignment: .leading, spacing: 3) {
        Text(step.title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
        Text(step.status.label)
          .font(.caption)
          .foregroundStyle(statusColor(step.status))
      }

      Spacer()
      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
      selectedStepID == step.id ? Color.accentColor.opacity(0.1) : .clear,
      in: RoundedRectangle(cornerRadius: 10, style: .continuous)
    )
    .contentShape(Rectangle())
  }

  private var detail: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack(alignment: .top, spacing: 18) {
        Image(systemName: selectedStep.systemImage)
          .font(.system(size: 32, weight: .medium))
          .foregroundStyle(Color.accentColor)
          .frame(width: 58, height: 58)
          .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))

        VStack(alignment: .leading, spacing: 7) {
          Text(selectedStep.title)
            .font(.system(size: 28, weight: .semibold))
          Text(selectedStep.detail)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          summaryRow("Model", hostInspection?.identity.model ?? "Pending")
          summaryRow("macOS", hostInspection?.macOSVersion ?? "Pending")
          summaryRow("Power", hostInspection?.powerSource.rawValue ?? "Pending")
          summaryRow("FileVault", fileVaultStatus)
          summaryRow("APFS free", freeSpaceStatus)
          summaryRow("Engine", engineStatus)
          summaryRow("Helper", helperStatus)
          summaryRow("Downloads", downloadStatus)
        }
        .padding(8)
      } label: {
        Label("Read-only preflight", systemImage: "checkmark.seal")
          .font(.headline)
      }

      if let reason = snapshot.blockedReason {
        statusMessage(
          reason,
          systemImage: "xmark.octagon.fill",
          color: .red
        )
      } else if let inspectionError {
        statusMessage(
          inspectionError,
          systemImage: "exclamationmark.triangle.fill",
          color: .red
        )
      } else if let executionProgress {
        statusMessage(
          executionMessage(executionProgress),
          systemImage: "checkmark.shield.fill",
          color: .green
        )
      } else if let executionError {
        statusMessage(
          executionError,
          systemImage: "exclamationmark.octagon.fill",
          color: .red
        )
      } else if let helperRegistrationError {
        statusMessage(
          helperRegistrationError,
          systemImage: "exclamationmark.shield.fill",
          color: .orange
        )
      } else if planApproval != nil {
        statusMessage(
          helperServiceStatus == .enabled
            ? "The exact candidate-bound plan is approved and the signed helper is enabled. Starting still requires a separate confirmation."
            : "The exact candidate-bound plan is approved in memory. Privileged execution remains locked until the signed helper is enabled.",
          systemImage: "checkmark.circle.fill",
          color: .green
        )
      } else if planReview != nil {
        statusMessage(
          "The signed plan is ready for exact owner review. No authorization was requested and no disk or boot policy changed.",
          systemImage: "checkmark.shield.fill",
          color: .green
        )
      } else if let planPreparationError {
        statusMessage(
          planPreparationError,
          systemImage: "exclamationmark.triangle.fill",
          color: .red
        )
      } else {
        Label(
          "Host inspection is live. Verified downloads remain locked until a production-signed model catalog is available.",
          systemImage: "info.circle"
        )
        .foregroundStyle(.secondary)
      }

      if let engineInspection {
        statusMessage(
          engineInspection.support == .supported
            ? "The pinned Asahi engine independently confirmed this model and completed read-only disk inventory."
            : "The pinned Asahi engine independently rejected this model before disk inventory or mutation.",
          systemImage: engineInspection.support == .supported
            ? "checkmark.shield.fill"
            : "lock.shield.fill",
          color: engineInspection.support == .supported ? .green : .orange
        )
      } else if let engineInspectionError {
        statusMessage(
          engineInspectionError,
          systemImage: "exclamationmark.shield.fill",
          color: .red
        )
      }

      if selectedStepID == "plan", let planReview {
        planReviewBox(planReview)
      }

      Spacer()

      if planReview != nil, planApproval == nil {
        Toggle(
          "I reviewed the exact disk extent and required Recovery steps",
          isOn: $ownerAcknowledged
        )
        .toggleStyle(.checkbox)
      }

      HStack {
        Button(isInspecting ? "Inspecting…" : "Inspect this Mac") {
          Task { await inspectThisMac() }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isInspecting)

        Button(isPreparingPlan ? "Preparing…" : "Prepare signed plan") {
          Task { await prepareSignedPlan() }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(
          isInspecting
            || isPreparingPlan
            || hostInspection == nil
            || engineInspection?.support != .supported
            || installationBlocked
        )

        if let planReview, planApproval == nil {
          Button("Approve exact plan") {
            approve(planReview)
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
          .disabled(!ownerAcknowledged)
        }

        if planApproval != nil, helperServiceStatus == .requiresApproval {
          Button("Open System Settings") {
            InstallerHelperServiceManager.openSystemSettings()
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
        } else if planApproval != nil, helperServiceStatus != .enabled {
          Button("Register helper") {
            showsHelperConfirmation = true
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
          .disabled(installationBlocked)
        }

        Button(isExecuting ? "Installing…" : "Start installation") {
          showsExecutionConfirmation = true
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!canStartInstallation)

        Spacer()

        Text(engineConnectionLabel)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }
    }
    .padding(34)
  }

  private var fileVaultStatus: String {
    guard let hostInspection else {
      return "Pending"
    }
    return hostInspection.fileVaultEnabled ? "On" : "Off"
  }

  private var freeSpaceStatus: String {
    guard let storage = hostInspection?.storage else {
      return "Pending"
    }
    return ByteCountFormatter.string(
      fromByteCount: Int64(storage.containerFreeBytes),
      countStyle: .file
    )
  }

  private var downloadStatus: String {
    if installationBlocked {
      return "Blocked for this model"
    }
    if let planReview {
      return "Verified • catalog \(planReview.assets.catalogIdentity.sequence)"
    }
    if isPreparingPlan {
      return "Fetching and verifying"
    }
    return "Awaiting signed catalog"
  }

  private var engineStatus: String {
    if isInspecting {
      return "Inspecting pinned artifact"
    }
    if let engineInspection {
      return engineInspection.support == .supported
        ? "Verified • supported"
        : "Verified • unsupported"
    }
    return engineInspectionError == nil ? "Pending" : "Unavailable • locked"
  }

  private var helperStatus: String {
    switch helperServiceStatus {
    case .notRegistered:
      "Not registered • locked"
    case .enabled:
      "Enabled"
    case .requiresApproval:
      "Awaiting System Settings"
    case .notFound:
      "Bundled service unavailable"
    case .unknown:
      "Unknown • locked"
    }
  }

  private var canStartInstallation: Bool {
    !installationBlocked
      && !isExecuting
      && !hasExecutionStarted
      && engineInspection?.support == .supported
      && preparedPlan != nil
      && planApproval != nil
      && releaseConfiguration != nil
      && helperServiceStatus == .enabled
  }

  private func executionMessage(
    _ progress: InstallerExecutionProgress
  ) -> String {
    switch progress.nextAction {
    case .continueInstallation:
      "The helper accepted the exact plan and installation is continuing."
    case .enterRecovery:
      "Preparation completed. Shut down and enter 1TR Recovery to continue the signed handoff."
    case .attachInstallationMedia:
      "Preparation completed. Attach the verified installation media to continue."
    case .verifyInstalledSystem:
      "Installation completed. Boot and verify the installed Omarchy system."
    case .manualRecovery:
      "The engine stopped safely and requires manual recovery before continuing."
    }
  }

  private var engineConnectionLabel: String {
    if isPreparingPlan {
      return "Signed engine planning"
    }
    if isInspecting {
      return "Pinned engine inspecting"
    }
    if engineInspection != nil {
      return "Pinned engine read-only"
    }
    return "Pinned engine unavailable"
  }

  private func planReviewBox(
    _ review: InstallerPlanReview
  ) -> some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 9) {
        summaryRow("Device", review.plan.deviceIdentifier)
        summaryRow("Store", review.plan.storeIdentifier)
        summaryRow("Source", review.plan.sourceIdentifier)
        summaryRow("Offset", formatBytes(review.plan.offsetBytes))
        summaryRow("Install", formatBytes(review.plan.lengthBytes))
        summaryRow("Engine", review.plan.engineVersion)
        summaryRow("Plan", shortDigest(review.plan.planDigest))
        summaryRow("Binding", shortDigest(review.identity.bindingDigest))
      }
      .padding(8)
    } label: {
      Label("Exact candidate-bound plan", systemImage: "lock.shield")
        .font(.headline)
    }
  }

  private func formatBytes(_ value: UInt64) -> String {
    ByteCountFormatter.string(
      fromByteCount: Int64(clamping: value),
      countStyle: .file
    )
  }

  private func shortDigest(_ value: String) -> String {
    guard value.count > 22 else {
      return value
    }
    return String(value.prefix(18)) + "…" + String(value.suffix(8))
  }

  private func summaryRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
        .foregroundStyle(.secondary)
        .frame(width: 92, alignment: .leading)
      Text(value)
        .fontWeight(.medium)
      Spacer()
    }
  }

  private func statusMessage(
    _ message: String,
    systemImage: String,
    color: Color
  ) -> some View {
    Label(message, systemImage: systemImage)
      .foregroundStyle(color)
      .padding(14)
      .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
  }

  private func statusColor(_ status: InstallerWorkflowStepStatus) -> Color {
    switch status {
    case .planned:
      .blue
    case .observed:
      .green
    case .ownerRequired:
      .orange
    case .blocked:
      .red
    case .locked:
      .secondary
    }
  }

  @MainActor
  private func prepareSignedPlan() async {
    guard let hostInspection,
      engineInspectionTranscript != nil
    else {
      planPreparationError =
        "Read-only host and engine inspection must complete first."
      return
    }

    isPreparingPlan = true
    planPreparationError = nil
    planReview = nil
    preparedPlan = nil
    planApproval = nil
    releaseConfiguration = nil
    executionProgress = nil
    executionError = nil
    helperRegistrationError = nil
    hasExecutionStarted = false
    ownerAcknowledged = false
    defer { isPreparingPlan = false }

    do {
      let configuration = try InstallerReleaseConfigurationLocator()
        .loadFromMainBundle()
      let workspace = try installerWorkspace()
      let catalogStore = AcceptedCatalogIdentityStore(
        directory: workspace.state
      )
      let previouslyAcceptedCatalog = try catalogStore.load()
      let validationTime = Date()
      let release = try await InstallerReleaseAssetCoordinator()
        .prepareRelease(
          InstallerReleasePreparationRequest(
            host: hostInspection,
            configuration: configuration,
            validationTime: validationTime,
            previouslyAcceptedCatalog: previouslyAcceptedCatalog,
            stagingDirectory: workspace.staging
          )
        )
      try catalogStore.store(release.assets.catalogIdentity)
      let stagedEngine = release.assets.engine
      let archive = try PinnedAsahiEngineArchive(
        fileURL: stagedEngine.fileURL,
        expectedDigest: stagedEngine.artifact.expectedDigest,
        expectedSizeBytes: stagedEngine.artifact.expectedSizeBytes
      )
      let signedInspection = try await EngineInspectionRunner().inspect(
        archive
      )
      guard
        signedInspection.validated.deviceIdentifier
          == hostInspection.identity.deviceIdentifier,
        signedInspection.validated.support == .supported,
        let inventory = signedInspection.validated.inventory
      else {
        throw InstallerPlanPreparationError.unsupportedDevice(
          hostInspection.identity.deviceIdentifier
        )
      }
      let recommendation = try InstallerAllocationRecommendation(
        inventory: inventory
      )
      let prepared = try await InstallerPlanPreparationCoordinator()
        .prepareExecution(
          InstallerPlanPreparationRequest(
            host: hostInspection,
            release: release,
            configuration: configuration,
            inspectionTranscript: signedInspection.transcript,
            candidate: recommendation.candidate,
            requestedLengthBytes: recommendation.requestedLengthBytes,
            validationTime: validationTime,
            previouslyAcceptedCatalog: previouslyAcceptedCatalog,
            scratchDirectory: workspace.scratch
          )
        )
      preparedPlan = prepared
      planReview = prepared.review
      releaseConfiguration = configuration
      selectedStepID = "plan"
    } catch InstallerReleaseConfigurationError.releaseResourcesUnavailable {
      planPreparationError =
        "This build has no sealed production release identity. Installation remains locked."
    } catch {
      planPreparationError =
        "Signed plan preparation failed (\(String(describing: error))). No authorization was requested."
    }
  }

  @MainActor
  private func approve(_ review: InstallerPlanReview) {
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
      planApproval = try review.approve(confirming: confirmation)
      ownerAcknowledged = false
    } catch {
      planApproval = nil
      planPreparationError =
        "The plan changed before approval. Prepare and review it again."
    }
  }

  @MainActor
  private func registerHelperAfterConfirmation() {
    guard planApproval != nil,
      preparedPlan != nil,
      releaseConfiguration != nil,
      !installationBlocked
    else {
      helperRegistrationError =
        "A supported Mac and exact approved plan are required before helper registration."
      return
    }
    helperRegistrationError = nil
    do {
      try helperService.registerAfterOwnerAuthorization()
      helperServiceStatus = helperService.status
      if helperServiceStatus == .requiresApproval {
        helperRegistrationError =
          "macOS requires approval in System Settings before the helper can run."
      } else if helperServiceStatus != .enabled {
        helperRegistrationError =
          "The helper is not enabled. Keep installation locked and review macOS service status."
      }
    } catch {
      helperServiceStatus = helperService.status
      helperRegistrationError =
        "Helper registration failed (\(String(describing: error))). Installation remains locked."
    }
  }

  @MainActor
  private func executeApprovedPlan() async {
    helperServiceStatus = helperService.status
    guard canStartInstallation,
      let preparedPlan,
      let planApproval,
      let releaseConfiguration,
      let hostInspection
    else {
      executionError =
        "The approved plan or enabled helper is no longer available. Prepare and review the plan again."
      return
    }

    isExecuting = true
    hasExecutionStarted = true
    executionProgress = nil
    executionError = nil
    defer { isExecuting = false }

    do {
      let currentHost = try AppleSiliconHostInspector().inspect()
      guard
        currentHost.identity.deviceIdentifier
          == hostInspection.identity.deviceIdentifier
      else {
        throw InstallerAppError.hostChanged
      }
      let workspace = try installerWorkspace()
      let progress = try await InstallerExecutionCoordinator().execute(
        preparedPlan,
        approval: planApproval,
        configuration: releaseConfiguration,
        handoffDirectory: workspace.handoff
      )
      executionProgress = progress
      selectedStepID =
        progress.nextAction == .verifyInstalledSystem
        ? "boot"
        : "recovery"
    } catch {
      executionError =
        "Installation stopped or was rejected (\(String(describing: error))). Review the last trusted checkpoint, then prepare and approve a fresh plan before retrying."
    }
  }

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

  @MainActor
  private func inspectThisMac() async {
    isInspecting = true
    planReview = nil
    preparedPlan = nil
    planApproval = nil
    releaseConfiguration = nil
    executionProgress = nil
    executionError = nil
    helperRegistrationError = nil
    hasExecutionStarted = false
    planPreparationError = nil
    ownerAcknowledged = false
    engineInspection = nil
    engineInspectionTranscript = nil
    engineInspectionError = nil
    do {
      let result = try await Task.detached(priority: .userInitiated) {
        try AppleSiliconHostInspector().inspect()
      }.value
      hostInspection = result
      inspectionError = nil

      do {
        let inspection = try await EngineInspectionRunner().inspect()
        guard
          inspection.validated.deviceIdentifier
            == result.identity.deviceIdentifier
        else {
          engineInspectionError =
            "Pinned engine identity did not match this Mac. Installation remains locked."
          isInspecting = false
          return
        }
        engineInspection = inspection.validated
        engineInspectionTranscript = inspection.transcript
      } catch ValidationEngineArtifactError.unavailable {
        engineInspectionError =
          "Pinned validation engine is not available in this build. Installation remains locked."
      } catch {
        engineInspectionError =
          "Pinned engine inspection failed validation. Installation remains locked."
      }
    } catch {
      hostInspection = nil
      inspectionError = "Read-only inspection failed. Installation remains locked."
    }
    isInspecting = false
  }
}

private struct EngineInspectionRunner: Sendable {
  func inspect() async throws -> EngineInspectionResult {
    let scratch = try scratchDirectory()
    let archive = try ValidationEngineArtifactLocator().locate()
    return try await inspect(archive, in: scratch)
  }

  func inspect(
    _ archive: PinnedAsahiEngineArchive
  ) async throws -> EngineInspectionResult {
    try await inspect(archive, in: scratchDirectory())
  }

  private func inspect(
    _ archive: PinnedAsahiEngineArchive,
    in scratch: URL
  ) async throws -> EngineInspectionResult {
    let transcript = try await PinnedAsahiEngineExecutor().inspect(
      archive,
      in: scratch
    )
    return EngineInspectionResult(
      transcript: transcript,
      validated: try AppleInstallerTrustCore()
        .validateEngineTranscript(transcript)
    )
  }

  private func scratchDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "com.omarchy.mx.installer-engine",
      isDirectory: true
    )
    if !FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
    }
    return directory
  }
}

private struct EngineInspectionResult: Sendable {
  let transcript: Data
  let validated: ValidatedEngineTranscript
}

private enum InstallerAppError: Error {
  case hostChanged
  case workspaceUnavailable
}
