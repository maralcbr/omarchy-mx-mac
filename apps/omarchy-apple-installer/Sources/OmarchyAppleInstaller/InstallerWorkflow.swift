import Foundation

public struct InstallerWorkflow: Sendable {
  public init() {}

  public func referenceM1ProPreview() -> InstallerWorkflowSnapshot {
    makePreview(
      deviceName: "14-inch MacBook Pro with M1 Pro",
      deviceIdentifier: "apple,j314s",
      inspectionStatus: .planned,
      blockedReason: nil
    )
  }

  #if os(macOS)
    public func preview(
      for host: AppleSiliconHostInspection
    ) -> InstallerWorkflowSnapshot {
      let blockedReason: String?
      if case .blocked(let reason) = host.eligibility {
        blockedReason = reason
      } else {
        blockedReason = nil
      }

      return makePreview(
        deviceName: "\(host.identity.model) • \(host.identity.chip)",
        deviceIdentifier: host.identity.deviceIdentifier,
        inspectionStatus: .observed,
        blockedReason: blockedReason
      )
    }
  #endif

  private func makePreview(
    deviceName: String,
    deviceIdentifier: String,
    inspectionStatus: InstallerWorkflowStepStatus,
    blockedReason: String?
  ) -> InstallerWorkflowSnapshot {
    let preparationStatus: InstallerWorkflowStepStatus =
      blockedReason == nil
      ? .planned
      : .blocked
    let recoveryStatus: InstallerWorkflowStepStatus =
      blockedReason == nil
      ? .ownerRequired
      : .blocked

    return InstallerWorkflowSnapshot(
      mode: .safePreview,
      deviceName: deviceName,
      deviceIdentifier: deviceIdentifier,
      distributionName: "Omarchy MX Mac",
      releaseCandidate: "Signed full-OS Asahi package • private qualification",
      executionGate: .locked,
      blockedReason: blockedReason,
      steps: [
        InstallerWorkflowStep(
          id: "inspect",
          title: "Inspect this Mac",
          detail:
            "Confirm the exact Apple model, macOS version, power source, FileVault state, and current APFS limits without changing the disk.",
          status: inspectionStatus,
          systemImage: "laptopcomputer.and.arrow.down"
        ),
        InstallerWorkflowStep(
          id: "verify",
          title: "Verify trusted sources",
          detail:
            "Fetch the signed support catalog and accept only pinned Asahi installer, metadata, engine, and Omarchy payload digests.",
          status: preparationStatus,
          systemImage: "checkmark.shield"
        ),
        InstallerWorkflowStep(
          id: "download",
          title: "Download installation assets",
          detail:
            "Download the model-specific engine, metadata, and complete Omarchy ESP, boot, and root images into private staging, verify size and SHA-256, then accept each file atomically.",
          status: preparationStatus,
          systemImage: "arrow.down.circle"
        ),
        InstallerWorkflowStep(
          id: "plan",
          title: "Review the disk plan",
          detail:
            "Present the exact APFS container, byte extent, required free space, rollback evidence, and candidate-bound approval before authorization.",
          status: preparationStatus,
          systemImage: "externaldrive.badge.questionmark"
        ),
        InstallerWorkflowStep(
          id: "recovery",
          title: "Complete Recovery handoff",
          detail:
            "After the full OS is written, a machine owner must hold the power button, enter One True Recovery, authenticate, and let Finish Installation establish the machine-specific boot policy.",
          status: recoveryStatus,
          systemImage: "person.badge.key"
        ),
        InstallerWorkflowStep(
          id: "boot",
          title: "Boot and finish Omarchy",
          detail:
            "Boot the installed linux-asahi system through m1n1 stage 2, U-Boot, and AArch64 GRUB; complete first-owner setup; then verify Omarchy and macOS both remain bootable.",
          status: .locked,
          systemImage: "power"
        ),
      ]
    )
  }
}

public struct InstallerWorkflowSnapshot: Equatable, Sendable {
  public let mode: InstallerWorkflowMode
  public let deviceName: String
  public let deviceIdentifier: String
  public let distributionName: String
  public let releaseCandidate: String
  public let executionGate: InstallerExecutionGate
  public let blockedReason: String?
  public let steps: [InstallerWorkflowStep]

  public var canMutateSystem: Bool {
    executionGate == .enabled && mode == .live && blockedReason == nil
  }

  public var requiredOwnerSteps: [InstallerWorkflowStep] {
    steps.filter { $0.status == .ownerRequired }
  }
}

public enum InstallerWorkflowMode: String, Equatable, Sendable {
  case safePreview
  case live
}

public enum InstallerExecutionGate: String, Equatable, Sendable {
  case locked
  case enabled
}

public struct InstallerWorkflowStep: Equatable, Identifiable, Sendable {
  public let id: String
  public let title: String
  public let detail: String
  public let status: InstallerWorkflowStepStatus
  public let systemImage: String

  public init(
    id: String,
    title: String,
    detail: String,
    status: InstallerWorkflowStepStatus,
    systemImage: String
  ) {
    self.id = id
    self.title = title
    self.detail = detail
    self.status = status
    self.systemImage = systemImage
  }
}

public enum InstallerWorkflowStepStatus: String, Equatable, Sendable {
  case planned
  case observed
  case ownerRequired
  case blocked
  case locked

  public var label: String {
    switch self {
    case .planned:
      "Planned"
    case .observed:
      "Observed"
    case .ownerRequired:
      "Owner required"
    case .blocked:
      "Blocked"
    case .locked:
      "Locked"
    }
  }
}
