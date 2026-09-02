import OmarchyAppleInstallerTrustCore
import OmarchyInstallerUXCore
import SwiftUI

/// Screen B. Renders both the review phase (checkbox → approve) and the
/// approved phase (helper state → the destructive start confirmation).
struct PlanScreen: View {
  enum Mode: Equatable {
    case review(acknowledged: Bool)
    case approved(HelperDisplay)
  }

  let plan: PlanDisplay
  let mode: Mode
  let canStartInstallation: Bool
  var isBusy = false
  let onAcknowledge: (Bool) -> Void
  let onApprove: () -> Void
  let onBack: () -> Void
  /// The person let go of the divider on a different size; the session
  /// re-plans with it so every later step carries the chosen split.
  let onSizeChosen: (UInt64) -> Void
  let onRequestInstall: () -> Void

  /// Display-level exploration of the split. The approved plan still carries
  /// the engine's exact extent; re-planning with a chosen size hooks in at
  /// `preparePlan(selection:)`.
  @State private var exploredOmarchyGB: Double?

  private static let minimumOmarchyGB: Double = 120

  var body: some View {
    ScreenScaffold(
      headline: displayedHeadline,
      subheadline: plan.subheadline,
      hint: hint
    ) {
      Panel {
        PanelHeader(
          title: "Disk " + PlainLanguage.bytes(plan.diskTotalBytes)
        )
        DiskBar(
          macOSBytes: plan.diskTotalBytes - displayedOmarchyBytes,
          omarchyBytes: displayedOmarchyBytes,
          onAdjustOmarchyFraction: adjustHandler,
          onCommitOmarchyFraction: commitHandler,
          isFrozen: isBusy
        )
        .transaction { $0.animation = nil }
        if isReview {
          sizeCaption
        }
      }

      Panel {
        PanelHeader(
          title: PlainLanguage.downloadedTitle,
          accessory: PlainLanguage.downloadVerified
        )
        VStack(alignment: .leading, spacing: 3) {
          ForEach(shownArtifacts) { artifact in
            HStack(spacing: 8) {
              Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(OmarchyTheme.accent)
              Text(artifact.fileName)
                .font(OmarchyTheme.body)
                .lineLimit(1)
                .truncationMode(.middle)
              Spacer(minLength: 8)
              Text(PlainLanguage.bytes(artifact.expectedBytes))
                .font(OmarchyTheme.caption.monospacedDigit())
                .foregroundStyle(OmarchyTheme.secondaryText)
            }
          }
        }
      }

      if case .approved(let helper) = mode {
        helperPanel(helper)
      }

      DetailsPanel(title: PlainLanguage.planDetailsTitle) {
        FactGrid(rows: plan.facts, labelWidth: 104)
      }

      if case .review(let acknowledged) = mode {
        acknowledgement(acknowledged)
      }
    } actions: {
      Button(PlainLanguage.planBack, action: onBack)
        .omarchySecondaryButton()
        .disabled(isBusy)

      switch mode {
      case .review(let acknowledged):
        Button(PlainLanguage.planApprove, action: onApprove)
          .omarchyPrimaryButton()
          .disabled(!acknowledged || isBusy)
          .keyboardShortcut(.defaultAction)
      case .approved:
        Button(PlainLanguage.planInstall, action: onRequestInstall)
          .omarchyPrimaryButton()
          .disabled(!canStartInstallation)
          .keyboardShortcut(.defaultAction)
      }
    }
    .onChange(of: plan.omarchyBytes) { _, _ in
      exploredOmarchyGB = nil
    }
  }

  /// The list shows the OS package the person is installing; the pinned
  /// engine and its metadata are still downloaded and verified, but they are
  /// tooling, not something to review.
  private var shownArtifacts: [PlanArtifactDisplay] {
    let packages = plan.artifacts.filter { $0.role == "payload" }
    return packages.isEmpty ? plan.artifacts : packages
  }

  private var isReview: Bool {
    if case .review = mode {
      return true
    }
    return false
  }

  private var displayedOmarchyBytes: UInt64 {
    guard isReview, let exploredOmarchyGB else {
      return plan.omarchyBytes
    }
    return UInt64(exploredOmarchyGB * 1_000_000_000)
  }

  private var displayedHeadline: String {
    guard isReview, exploredOmarchyGB != nil else {
      return plan.headline
    }
    return "\(PlainLanguage.bytes(displayedOmarchyBytes)) for Omarchy"
  }

  private var maximumOmarchyGB: Double {
    let totalGB = Double(plan.diskTotalBytes) / 1_000_000_000
    return max(Self.minimumOmarchyGB + 10, min(800, (totalGB - 120) / 10 * 10).rounded(.down))
  }

  private var adjustHandler: ((Double) -> Void)? {
    guard isReview else {
      return nil
    }
    return { fraction in adjustOmarchyShare(fraction) }
  }

  /// Letting go of the divider on a new size re-plans, so every later step
  /// carries the chosen split.
  private var commitHandler: ((Double) -> Void)? {
    guard isReview else {
      return nil
    }
    return { fraction in
      adjustOmarchyShare(fraction)
      let chosen = displayedOmarchyBytes
      if chosen != plan.omarchyBytes {
        // Keep showing the chosen split until the re-planned size arrives;
        // snapping back to the old plan in between is what looked glitchy.
        onSizeChosen(chosen)
      } else {
        exploredOmarchyGB = nil
      }
    }
  }

  private func adjustOmarchyShare(_ fraction: Double) {
    let totalGB = Double(plan.diskTotalBytes) / 1_000_000_000
    let steppedGB = ((totalGB * fraction) / 10).rounded() * 10
    exploredOmarchyGB = min(
      maximumOmarchyGB,
      max(Self.minimumOmarchyGB, steppedGB)
    )
  }

  private var sizeCaption: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("Drag the divider to choose how much space Omarchy gets (minimum \(Int(Self.minimumOmarchyGB)) GB)")
        .font(OmarchyTheme.caption)
        .foregroundStyle(OmarchyTheme.secondaryText)
      Spacer(minLength: 0)
      Text(PlainLanguage.bytes(displayedOmarchyBytes))
        .font(.system(size: 15, weight: .semibold).monospacedDigit())
        .foregroundStyle(OmarchyTheme.accent)
    }
    .padding(.top, 4)
  }

  private var hint: String? {
    switch mode {
    case .review:
      return nil
    case .approved(let helper):
      return helper.isEnabled ? nil : PlainLanguage.helperNotInstalled
    }
  }

  private func acknowledgement(_ acknowledged: Bool) -> some View {
    HStack(alignment: .center, spacing: 14) {
      Toggle(
        "",
        isOn: Binding(get: { acknowledged }, set: { onAcknowledge($0) })
      )
      .labelsHidden()
      .toggleStyle(.checkbox)
      .controlSize(.large)
      .scaleEffect(1.3)
      .tint(OmarchyTheme.accent)
      .accessibilityLabel(PlainLanguage.planAcknowledgement)
      Text(PlainLanguage.planAcknowledgement)
        .font(.system(size: 16.5, weight: .medium))
        .fixedSize(horizontal: false, vertical: true)
        .onTapGesture { onAcknowledge(!acknowledged) }
      Spacer(minLength: 0)
      InfoTip(text: PlainLanguage.planAcknowledgementTooltip)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 16)
    .background(
      RoundedRectangle(cornerRadius: OmarchyTheme.cardRadius)
        .fill(acknowledged ? OmarchyTheme.accentSoft : OmarchyTheme.card)
    )
    .overlay(
      RoundedRectangle(cornerRadius: OmarchyTheme.cardRadius)
        .strokeBorder(acknowledged ? OmarchyTheme.accent : OmarchyTheme.separator, lineWidth: 1.5)
    )
    .padding(.top, 24)
  }

  private func helperPanel(_ helper: HelperDisplay) -> some View {
    Panel {
      HStack(spacing: 10) {
        Image(
          systemName: helper.isEnabled
            ? "checkmark.shield.fill" : "lock.shield"
        )
        .foregroundStyle(
          helper.isEnabled ? OmarchyTheme.accent : OmarchyTheme.caution
        )
        VStack(alignment: .leading, spacing: 2) {
          Text("Privileged helper")
            .font(.system(size: 13, weight: .semibold))
          Text(helper.isEnabled ? helper.summary : PlainLanguage.helperNotInstalled)
            .font(OmarchyTheme.caption)
            .foregroundStyle(OmarchyTheme.secondaryText)
        }
        Spacer(minLength: 8)
        InfoTip(
          text:
            "The helper does the privileged work. The installer package installs it as a system service."
        )
      }
    }
  }
}
