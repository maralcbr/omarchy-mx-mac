#if os(macOS)
  import Foundation
  import OmarchyAppleInstallerTrustCore

  /// Everything a screen renders, derived once by the environment from the
  /// retained trust objects. Display models are render-only: no approval,
  /// confirmation, or execution value is ever rebuilt from them.
  public struct PreflightCheck: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let value: String
    public let satisfied: Bool
    public let tooltip: String

    public init(
      id: String,
      label: String,
      value: String,
      satisfied: Bool,
      tooltip: String
    ) {
      self.id = id
      self.label = label
      self.value = value
      self.satisfied = satisfied
      self.tooltip = tooltip
    }
  }

  public struct HostDisplay: Equatable, Sendable {
    public let modelName: String
    public let chipAndSpace: String
    public let deviceIdentifier: String
    public let supported: Bool
    public let checks: [PreflightCheck]
    public let helper: HelperDisplay
    /// Why this Mac cannot install right now, when `supported` is false.
    public let blockingReason: String?

    public init(
      modelName: String,
      chipAndSpace: String,
      deviceIdentifier: String,
      supported: Bool,
      checks: [PreflightCheck],
      helper: HelperDisplay,
      blockingReason: String? = nil
    ) {
      self.modelName = modelName
      self.chipAndSpace = chipAndSpace
      self.deviceIdentifier = deviceIdentifier
      self.supported = supported
      self.checks = checks
      self.helper = helper
      self.blockingReason = blockingReason
    }
  }

  public struct PlanArtifactDisplay: Equatable, Sendable, Identifiable {
    public let role: String
    public let fileName: String
    public let expectedBytes: UInt64

    public var id: String { role }

    public init(role: String, fileName: String, expectedBytes: UInt64) {
      self.role = role
      self.fileName = fileName
      self.expectedBytes = expectedBytes
    }
  }

  public struct PlanFactRow: Equatable, Sendable, Identifiable {
    public let label: String
    public let value: String
    public let isMonospaced: Bool

    public var id: String { label }

    public init(label: String, value: String, isMonospaced: Bool = false) {
      self.label = label
      self.value = value
      self.isMonospaced = isMonospaced
    }
  }

  /// Where the plan should go when this Mac already has an Omarchy install.
  public enum InstallTargetSelection: Equatable, Sendable {
    /// First pass: surface a choice when an existing install is present.
    case automatic
    /// Keep the existing install and plan a second one automatically.
    case installAlongside
    /// Remove the named existing install and reuse its exact space.
    case replaceExisting(sourceIdentifier: String)
  }

  /// One existing Omarchy install the pinned engine found on this Mac.
  public struct ExistingInstallDisplay: Equatable, Sendable, Identifiable {
    public let sourceIdentifier: String
    public let sizeDescription: String

    public var id: String { sourceIdentifier }

    public init(sourceIdentifier: String, sizeDescription: String) {
      self.sourceIdentifier = sourceIdentifier
      self.sizeDescription = sizeDescription
    }
  }

  /// Plan preparation either yields a reviewable plan or pauses for the
  /// owner to decide what happens to an existing install. Nothing is
  /// approved or executed from either value.
  public enum PlanPreparationDisplay: Equatable, Sendable {
    case plan(PlanDisplay)
    case existingInstallChoice([ExistingInstallDisplay])
  }

  public struct PlanDisplay: Equatable, Sendable {
    public let headline: String
    public let subheadline: String
    public let diskTotalBytes: UInt64
    public let omarchyBytes: UInt64
    public let macOSBytes: UInt64
    public let bindingDigest: String
    public let planDigest: String
    public let artifacts: [PlanArtifactDisplay]
    public let facts: [PlanFactRow]

    public init(
      headline: String,
      subheadline: String,
      diskTotalBytes: UInt64,
      omarchyBytes: UInt64,
      macOSBytes: UInt64,
      bindingDigest: String,
      planDigest: String,
      artifacts: [PlanArtifactDisplay],
      facts: [PlanFactRow]
    ) {
      self.headline = headline
      self.subheadline = subheadline
      self.diskTotalBytes = diskTotalBytes
      self.omarchyBytes = omarchyBytes
      self.macOSBytes = macOSBytes
      self.bindingDigest = bindingDigest
      self.planDigest = planDigest
      self.artifacts = artifacts
      self.facts = facts
    }
  }

  public struct HelperDisplay: Equatable, Sendable {
    public let status: InstallerHelperServiceStatus
    public let summary: String

    /// The pre-installed system daemon is reachable, so installation may run.
    public var isEnabled: Bool { status == .enabled }

    public init(
      status: InstallerHelperServiceStatus,
      summary: String
    ) {
      self.status = status
      self.summary = summary
    }
  }

  /// One artifact row on the preparing screen, fed by
  /// `ArtifactStagingProgress` events keyed by role.
  public struct AssetProgressRow: Equatable, Sendable, Identifiable {
    public let role: String
    public let fileName: String
    public let bytesCompleted: UInt64
    public let totalBytes: UInt64
    public let phase: ArtifactStagingProgress.Phase
    public let partIndex: Int?
    public let partCount: Int?

    public var id: String { role }

    public var isVerified: Bool { phase == .verified }

    public var fraction: Double {
      guard totalBytes > 0 else { return 0 }
      return min(1, Double(bytesCompleted) / Double(totalBytes))
    }

    public init(
      role: String,
      fileName: String,
      bytesCompleted: UInt64,
      totalBytes: UInt64,
      phase: ArtifactStagingProgress.Phase,
      partIndex: Int? = nil,
      partCount: Int? = nil
    ) {
      self.role = role
      self.fileName = fileName
      self.bytesCompleted = bytesCompleted
      self.totalBytes = totalBytes
      self.phase = phase
      self.partIndex = partIndex
      self.partCount = partCount
    }
  }

  public struct AssetProgressUpdate: Equatable, Sendable {
    public enum Stage: String, Equatable, Sendable {
      case fetchingCatalog
      case downloading
      case inspectingEngine
      case planning
    }

    public let stage: Stage
    public let rows: [AssetProgressRow]

    public var bytesCompleted: UInt64 {
      rows.reduce(0) { $0 + $1.bytesCompleted }
    }

    public var totalBytes: UInt64 {
      rows.reduce(0) { $0 + $1.totalBytes }
    }

    public var isDeterminate: Bool { stage == .downloading && totalBytes > 0 }

    public init(stage: Stage, rows: [AssetProgressRow] = []) {
      self.stage = stage
      self.rows = rows
    }
  }

  public struct JournalFeedLine: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
      case event
      case checkpoint
      case completion
    }

    public let id: Int
    public let kind: Kind
    public let text: String

    public init(id: Int, kind: Kind, text: String) {
      self.id = id
      self.kind = kind
      self.text = text
    }
  }

  public struct InstallProgressDisplay: Equatable, Sendable {
    public let phaseTitle: String
    public let stageIndex: Int
    public let stageFractions: [Double]
    public let stageLabels: [String]
    public let completedCheckpoints: [String]
    public let feed: [JournalFeedLine]
    public let degraded: Bool
    public let startedAt: Date

    public var isIndeterminate: Bool { degraded || feed.isEmpty }

    public init(
      phaseTitle: String,
      stageIndex: Int,
      stageFractions: [Double],
      stageLabels: [String],
      completedCheckpoints: [String],
      feed: [JournalFeedLine],
      degraded: Bool,
      startedAt: Date
    ) {
      self.phaseTitle = phaseTitle
      self.stageIndex = stageIndex
      self.stageFractions = stageFractions
      self.stageLabels = stageLabels
      self.completedCheckpoints = completedCheckpoints
      self.feed = feed
      self.degraded = degraded
      self.startedAt = startedAt
    }
  }

  public struct RecoveryStep: Equatable, Sendable, Identifiable {
    public let number: Int
    public let title: String
    public let detail: String

    public var id: Int { number }

    public init(number: Int, title: String, detail: String) {
      self.number = number
      self.title = title
      self.detail = detail
    }
  }

  public struct HandoffDisplay: Equatable, Sendable {
    public let headline: String
    public let subheadline: String
    public let steps: [RecoveryStep]
    public let explainer: String
    public let hint: String

    public init(
      headline: String,
      subheadline: String,
      steps: [RecoveryStep],
      explainer: String,
      hint: String
    ) {
      self.headline = headline
      self.subheadline = subheadline
      self.steps = steps
      self.explainer = explainer
      self.hint = hint
    }
  }

  public struct CompletionDisplay: Equatable, Sendable {
    public let nextAction: InstallerNextAction
    public let headline: String
    public let subheadline: String
    public let verified: [PlanFactRow]
    public let handoff: HandoffDisplay?

    public init(
      nextAction: InstallerNextAction,
      headline: String,
      subheadline: String,
      verified: [PlanFactRow],
      handoff: HandoffDisplay?
    ) {
      self.nextAction = nextAction
      self.headline = headline
      self.subheadline = subheadline
      self.verified = verified
      self.handoff = handoff
    }
  }

  public struct FailureDisplay: Equatable, Sendable {
    public let headline: String
    public let plainDetail: String
    public let technicalDetail: String?
    public let remedy: String?
    public let retryRecoveryAvailable: Bool
    public let isBlockedModel: Bool
    public let device: HostDisplay?

    public init(
      headline: String,
      plainDetail: String,
      technicalDetail: String? = nil,
      remedy: String? = nil,
      retryRecoveryAvailable: Bool = false,
      isBlockedModel: Bool = false,
      device: HostDisplay? = nil
    ) {
      self.headline = headline
      self.plainDetail = plainDetail
      self.technicalDetail = technicalDetail
      self.remedy = remedy
      self.retryRecoveryAvailable = retryRecoveryAvailable
      self.isBlockedModel = isBlockedModel
      self.device = device
    }
  }

  public enum InstallOperationKind: String, Equatable, Sendable {
    case install
    case retryRecoveryAuthorization
  }

  public enum CredentialSheetError: String, Equatable, Sendable {
    case credentialsRejected
  }

  public struct CredentialSheetContext: Equatable, Sendable {
    public let kind: InstallOperationKind
    public let bindingDigest: String
    public let error: CredentialSheetError?
    /// True while the helper is checking the submitted credentials. The sheet
    /// stays up (fields locked) so a rejection appears in place instead of the
    /// sheet closing, the screen flipping, and the sheet coming back.
    public let isVerifying: Bool

    public init(
      kind: InstallOperationKind,
      bindingDigest: String,
      error: CredentialSheetError? = nil,
      isVerifying: Bool = false
    ) {
      self.kind = kind
      self.bindingDigest = bindingDigest
      self.error = error
      self.isVerifying = isVerifying
    }

    public func verifying() -> CredentialSheetContext {
      CredentialSheetContext(kind: kind, bindingDigest: bindingDigest, error: nil, isVerifying: true)
    }
  }

  public enum CredentialSheetState: Equatable, Sendable {
    case hidden
    case presented(CredentialSheetContext)

    public var context: CredentialSheetContext? {
      guard case .presented(let context) = self else {
        return nil
      }
      return context
    }
  }

  /// The single seam between the SwiftUI screens and the trust chain. The live
  /// implementation retains the trust objects (host inspection, prepared plan,
  /// review, approval, release configuration); the preview implementation
  /// replays a recorded journal. Neither ever hands a credential back.
  public protocol InstallerEnvironment: Sendable {
    func inspect() async throws -> HostDisplay
    /// `omarchyBytes` asks the planner for that much space for Omarchy; nil
    /// keeps the balanced default. The engine still clamps the request to the
    /// candidate's real minimum and maximum.
    func preparePlan(
      selection: InstallTargetSelection,
      omarchyBytes: UInt64?,
      progress: @escaping @Sendable (AssetProgressUpdate) -> Void
    ) async throws -> PlanPreparationDisplay
    func approve() throws
    func discardApproval()
    /// Re-reads whether the pre-installed system daemon is present. There is no
    /// registration or approval step — the package installs the helper.
    func refreshHelperStatus() -> HelperDisplay
    func execute(
      operation: InstallOperationKind,
      authorization: MachineOwnerAuthorization,
      journal: @escaping @Sendable (Data) -> Void
    ) async throws -> CompletionDisplay

    /// Fail-closed gates preserved verbatim from the previous view model.
    var installationBlocked: Bool { get }
    var engineSupported: Bool { get }
    var hasApprovedPlan: Bool { get }
    var helperStatus: HelperDisplay { get }

    /// Asks macOS for a graceful shutdown (the Apple menu's Shut Down).
    /// Returns true when the machine is actually going down; the preview
    /// environment and tests return false so nothing powers off.
    func requestShutdown() -> Bool
  }

  extension InstallerEnvironment {
    public func requestShutdown() -> Bool { false }
  }
#endif
