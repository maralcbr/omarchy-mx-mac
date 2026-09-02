#if DEBUG
  import Foundation
  import OmarchyAppleInstallerTrustCore
  import OmarchyInstallerUXCore

  /// Debug-only environment that replays a recorded execution journal through
  /// the real trust-core decoder so every screen can be reviewed on a machine
  /// that is not installable — including this blocked M4.
  ///
  /// Nothing here is compiled into a release build, no fixture is bundled into
  /// app resources, and no trust type with a non-public initializer is
  /// fabricated: the display-model seam makes that unnecessary.
  final class PreviewInstallerEnvironment: InstallerEnvironment, @unchecked Sendable {
    private let scenario: InstallerPreviewScenario
    private let journalURL: URL?
    private let lock = NSLock()
    private var approved = false
    private var credentialAttempts = 0

    init(scenario: InstallerPreviewScenario, journalURL: URL?) {
      self.scenario = scenario
      self.journalURL = journalURL
    }

    var installationBlocked: Bool { scenario == .unsupported }
    var engineSupported: Bool { scenario != .unsupported }

    var hasApprovedPlan: Bool {
      lock.withLock { approved }
    }

    var helperStatus: HelperDisplay {
      HelperDisplay(
        status: .enabled,
        summary: PlainLanguage.helperSummary(.enabled)
      )
    }

    func refreshHelperStatus() -> HelperDisplay { helperStatus }

    func inspect() async throws -> HostDisplay {
      try? await Task.sleep(for: .milliseconds(700))
      let transcript = try loadValidatedTranscript()
      let blocked = scenario == .unsupported
      let device = blocked ? "apple,j614s" : transcript.deviceIdentifier
      let free: UInt64 = 464_000_000_000
      let required = InstallerAllocationRecommendation.balancedTargetBytes

      return HostDisplay(
        modelName: blocked ? "MacBookPro16,1 (preview)" : "MacBookPro18,3 (preview)",
        chipAndSpace: blocked
          ? "Apple M4 · \(device)"
          : "Apple M1 Pro · \(PlainLanguage.bytes(free)) free",
        deviceIdentifier: device,
        supported: !blocked,
        checks: blocked ? [] : previewChecks(free: free, required: required),
        helper: helperStatus
      )
    }

    func preparePlan(
      selection: InstallTargetSelection,
      omarchyBytes: UInt64?,
      progress: @escaping @Sendable (AssetProgressUpdate) -> Void
    ) async throws -> PlanPreparationDisplay {
      if scenario == .existingInstall, selection == .automatic {
        try? await Task.sleep(for: .milliseconds(400))
        return .existingInstallChoice([
          ExistingInstallDisplay(
            sourceIdentifier: "disk0s3",
            sizeDescription: PlainLanguage.bytes(137_438_953_472)
          )
        ])
      }

      let transcript = try loadValidatedTranscript()
      guard let plan = transcript.plan else {
        throw InstallerAppError.inspectionRequired
      }

      let artifacts = Self.previewArtifacts
      if omarchyBytes != nil {
        // A size change re-plans against already verified files.
        try? await Task.sleep(for: .milliseconds(250))
        let total: UInt64 = 994_662_584_320
        let unit: UInt64 = 1_000_000_000
        let length = min(total - 120 * unit, max(120 * unit, omarchyBytes ?? plan.lengthBytes))
        return .plan(planDisplay(plan: plan, length: length, total: total, artifacts: artifacts))
      }

      progress(AssetProgressUpdate(stage: .fetchingCatalog))
      try? await Task.sleep(for: .milliseconds(500))

      for step in 1...12 {
        let fraction = Double(step) / 12
        let rows = artifacts.map { artifact in
          AssetProgressRow(
            role: artifact.role,
            fileName: artifact.fileName,
            bytesCompleted: UInt64(Double(artifact.expectedBytes) * fraction),
            totalBytes: artifact.expectedBytes,
            phase: step == 12 ? .verified : .downloading
          )
        }
        progress(AssetProgressUpdate(stage: .downloading, rows: rows))
        try? await Task.sleep(for: .milliseconds(140))
      }

      progress(AssetProgressUpdate(stage: .inspectingEngine))
      try? await Task.sleep(for: .milliseconds(500))
      progress(AssetProgressUpdate(stage: .planning))
      try? await Task.sleep(for: .milliseconds(400))

      let total: UInt64 = 994_662_584_320
      let unit: UInt64 = 1_000_000_000
      let length = min(total - 120 * unit, max(120 * unit, omarchyBytes ?? plan.lengthBytes))
      return .plan(planDisplay(plan: plan, length: length, total: total, artifacts: artifacts))
    }

    private func planDisplay(
      plan: ValidatedEnginePlan,
      length: UInt64,
      total: UInt64,
      artifacts: [PlanArtifactDisplay]
    ) -> PlanDisplay {
      PlanDisplay(
        headline: "\(PlainLanguage.bytes(length)) for Omarchy",
        subheadline: PlainLanguage.planSubheadline,
        diskTotalBytes: total,
        omarchyBytes: length,
        macOSBytes: total - length,
        bindingDigest: "sha256:" + String(repeating: "b", count: 64),
        planDigest: plan.planDigest,
        artifacts: artifacts,
        facts: [
          PlanFactRow(label: "Device", value: plan.deviceIdentifier),
          PlanFactRow(
            label: "Store",
            value:
              "\(plan.storeIdentifier) · \(plan.candidateKind) \(plan.sourceIdentifier)"
          ),
          PlanFactRow(
            label: "Offset",
            value: PlainLanguage.exactBytes(plan.offsetBytes)
          ),
          PlanFactRow(
            label: "Length",
            value:
              "\(PlainLanguage.exactBytes(length)) (\(PlainLanguage.bytes(length)))"
          ),
          PlanFactRow(label: "Engine", value: plan.engineVersion),
          PlanFactRow(
            label: "Plan digest",
            value: plan.planDigest,
            isMonospaced: true
          ),
          PlanFactRow(
            label: "Rollback",
            value:
              "MacOS untouched until approval; every write is checkpointed and journaled"
          ),
        ]
      )
    }

    func approve() throws {
      lock.withLock { approved = true }
    }

    func discardApproval() {
      lock.withLock { approved = false }
    }

    func execute(
      operation: InstallOperationKind,
      authorization: MachineOwnerAuthorization,
      journal: @escaping @Sendable (Data) -> Void
    ) async throws -> CompletionDisplay {
      if scenario == .credentialReject {
        let first = lock.withLock { () -> Bool in
          credentialAttempts += 1
          return credentialAttempts == 1
        }
        if first, operation == .install {
          try? await Task.sleep(for: .milliseconds(1400))
          throw EngineXPCSubmissionError.machineOwnerCredentialsRejected
        }
      }

      let lines = try loadJournalLines()
      var forwarded = Data()
      for (index, line) in lines.enumerated() {
        try? await Task.sleep(for: .milliseconds(800))
        if scenario == .degradedJournal, index == 5 {
          journal(Data("{\"broken\":true}\n".utf8))
          continue
        }
        forwarded.append(line)
        journal(line)

        if scenario == .recoveryRetry,
          operation == .install,
          index == 6
        {
          throw EngineXPCSubmissionError.recoveryAuthorizationFailed
        }
      }

      let transcript = try AppleInstallerTrustCore()
        .validateEngineTranscript(
          lines.reduce(into: Data()) { $0.append($1) }
        )
      let steps = transcript.plan?.requiredHumanSteps ?? []
      return CompletionDisplay(
        nextAction: .enterRecovery,
        headline: PlainLanguage.recoveryHeadline,
        subheadline: PlainLanguage.nextActionMessage(.enterRecovery),
        verified: PlainLanguage.doneVerifiedRows,
        handoff: HandoffDisplay(
          headline: PlainLanguage.recoveryHeadline,
          subheadline: PlainLanguage.recoverySubheadline,
          steps: PlainLanguage.recoverySteps(for: steps),
          explainer: PlainLanguage.recoveryExplainer,
          hint: ""
        )
      )
    }

    // MARK: Fixture

    private static let previewArtifacts = [
      PlanArtifactDisplay(
        role: "payload",
        fileName: "omarchy-2026.09.02-aarch64-apple-silicon-asahi-os-package.zip",
        expectedBytes: 3_638_729_568
      ),
      PlanArtifactDisplay(
        role: "metadata",
        fileName: "installer_data.json",
        expectedBytes: 34_000_000
      ),
      PlanArtifactDisplay(
        role: "engine",
        fileName: "installer-v0.9.0-omarchy.7.tar.gz",
        expectedBytes: 22_000_000
      ),
    ]

    private func previewChecks(
      free: UInt64,
      required: UInt64
    ) -> [PreflightCheck] {
      [
        PreflightCheck(
          id: "model",
          label: "Model",
          value: "MacBook Pro (M1 Pro) — preview fixture",
          satisfied: true,
          tooltip:
            "Support is per exact model. The list is signed and fails closed."
        ),
        PreflightCheck(
          id: "macos",
          label: "MacOS",
          value: "Preview replay",
          satisfied: true,
          tooltip: "A current MacOS is required for the Recovery handoff."
        ),
        PreflightCheck(
          id: "power",
          label: "Power",
          value: "Connected",
          satisfied: true,
          tooltip:
            "The install writes many gigabytes. Wall power avoids surprises."
        ),
        PreflightCheck(
          id: "filevault",
          label: "FileVault",
          value: "On, stays on",
          satisfied: true,
          tooltip: "Read only. Your MacOS data stays encrypted."
        ),
        PreflightCheck(
          id: "space",
          label: "Free space",
          value:
            "\(PlainLanguage.bytes(free)) · \(PlainLanguage.bytes(required)) needed",
          satisfied: true,
          tooltip: "Omarchy takes a fixed \(PlainLanguage.bytes(required))."
        ),
        PreflightCheck(
          id: "engine",
          label: "Engine",
          value: "Verified • supported",
          satisfied: true,
          tooltip:
            "A pinned, checksum-verified build of the Asahi installer does the disk work."
        ),
        PreflightCheck(
          id: "helper",
          label: "Helper",
          value: PlainLanguage.helperSummary(.enabled),
          satisfied: true,
          tooltip:
            "Does the privileged work. Installed as a system service by the installer package."
        ),
        PreflightCheck(
          id: "downloads",
          label: "Downloads",
          value: "Verified, catalog 7",
          satisfied: true,
          tooltip: "Every file is checked against a signed catalog before use."
        ),
      ]
    }

    private func loadJournalLines() throws -> [Data] {
      guard let journalURL else {
        throw InstallerAppError.previewFixtureUnavailable
      }
      let data = try Data(contentsOf: journalURL)
      var lines = [Data]()
      var start = data.startIndex
      while let newline = data[start...].firstIndex(of: 0x0A) {
        lines.append(Data(data[start...newline]))
        start = data.index(after: newline)
      }
      guard !lines.isEmpty else {
        throw InstallerAppError.previewFixtureUnavailable
      }
      return lines
    }

    private func loadValidatedTranscript() throws -> ValidatedEngineTranscript {
      let lines = try loadJournalLines()
      return try AppleInstallerTrustCore()
        .validateEngineTranscript(
          lines.reduce(into: Data()) { $0.append($1) }
        )
    }
  }
#endif
