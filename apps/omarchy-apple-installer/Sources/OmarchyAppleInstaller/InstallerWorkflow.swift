import Foundation

public struct InstallerWorkflow: Sendable {
  public init() {}

  public func referenceM1ProPreview() -> InstallerWorkflowSnapshot {
    InstallerWorkflowSnapshot(
      mode: .safePreview,
      deviceName: "14-inch MacBook Pro with M1 Pro",
      deviceIdentifier: "apple,j314s",
      distributionName: "Omarchy MX Mac",
      releaseCandidate: "Read-only Apple media candidate e732b2bc",
      executionGate: .locked,
      steps: [
        InstallerWorkflowStep(
          id: "inspect",
          title: "Inspect this Mac",
          detail: "Confirm the exact Apple model, macOS version, ownership, and current APFS layout without changing the disk.",
          status: .planned,
          systemImage: "laptopcomputer.and.arrow.down"
        ),
        InstallerWorkflowStep(
          id: "verify",
          title: "Verify trusted sources",
          detail: "Fetch the signed support catalog and accept only pinned Asahi installer, metadata, engine, and Omarchy payload digests.",
          status: .planned,
          systemImage: "checkmark.shield"
        ),
        InstallerWorkflowStep(
          id: "download",
          title: "Download installation assets",
          detail: "Download the model-specific boot preparation payload and Omarchy image into an isolated staging directory, then verify every digest.",
          status: .planned,
          systemImage: "arrow.down.circle"
        ),
        InstallerWorkflowStep(
          id: "plan",
          title: "Review the disk plan",
          detail: "Present the exact APFS container, byte extent, required free space, rollback evidence, and candidate-bound approval before authorization.",
          status: .planned,
          systemImage: "externaldrive.badge.questionmark"
        ),
        InstallerWorkflowStep(
          id: "recovery",
          title: "Complete Recovery handoff",
          detail: "A machine owner must hold the power button, enter One True Recovery, authenticate, and approve the machine-specific m1n1 stage 1 setup.",
          status: .ownerRequired,
          systemImage: "person.badge.key"
        ),
        InstallerWorkflowStep(
          id: "boot",
          title: "Boot and finish Omarchy",
          detail: "The prepared chain continues through m1n1 stage 2 and U-Boot to the AArch64 EFI loader, then verifies the installed system before offering normal boot.",
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
  public let steps: [InstallerWorkflowStep]

  public var canMutateSystem: Bool {
    executionGate == .enabled && mode == .live
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
  case ownerRequired
  case locked

  public var label: String {
    switch self {
    case .planned:
      "Planned"
    case .ownerRequired:
      "Owner required"
    case .locked:
      "Locked"
    }
  }
}
