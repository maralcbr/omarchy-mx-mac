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
  let onAcknowledge: (Bool) -> Void
  let onApprove: () -> Void
  let onBack: () -> Void
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
          title: "Disk · " + PlainLanguage.bytes(plan.diskTotalBytes)
        )
        DiskBar(
          macOSBytes: plan.diskTotalBytes - displayedOmarchyBytes,
          omarchyBytes: displayedOmarchyBytes,
          onAdjustOmarchyFraction: adjustHandler
        )
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
          ForEach(plan.artifacts) { artifact in
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
      Button(
        isReview ? PlainLanguage.planReapprove : PlainLanguage.planBack,
        action: onBack
      )
      .omarchySecondaryButton()

      switch mode {
      case .review(let acknowledged):
        Button(PlainLanguage.planApprove, action: onApprove)
          .omarchyPrimaryButton()
          .disabled(!acknowledged)
          .keyboardShortcut(.defaultAction)
      case .approved:
        Button(PlainLanguage.planInstall, action: onRequestInstall)
          .omarchyPrimaryButton()
          .disabled(!canStartInstallation)
          .keyboardShortcut(.defaultAction)
      }
    }
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

  private var adjustHandler: ((Double) -> Void)? {
    guard isReview else {
      return nil
    }
    return { fraction in adjustOmarchyShare(fraction) }
  }

  private var maximumOmarchyGB: Double {
    let totalGB = Double(plan.diskTotalBytes) / 1_000_000_000
    return max(Self.minimumOmarchyGB + 10, min(800, totalGB - 120))
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
      Text(
        "Drag the divider to choose how much space Omarchy gets · minimum "
          + PlainLanguage.bytes(UInt64(Self.minimumOmarchyGB * 1_000_000_000))
      )
      .font(OmarchyTheme.caption)
      .foregroundStyle(OmarchyTheme.secondaryText)
      Spacer(minLength: 0)
      Text(PlainLanguage.bytes(displayedOmarchyBytes))
        .font(OmarchyTheme.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(OmarchyTheme.accent)
    }
  }

  private var hint: String? {
    switch mode {
    case .review(let acknowledged):
      return acknowledged ? nil : PlainLanguage.planConfirmHint
    case .approved(let helper):
      return helper.isEnabled ? nil : PlainLanguage.helperNotInstalled
    }
  }

  private func acknowledgement(_ acknowledged: Bool) -> some View {
    HStack(alignment: .top, spacing: 11) {
      Toggle(
        isOn: Binding(get: { acknowledged }, set: { onAcknowledge($0) })
      ) {
        Text(PlainLanguage.planAcknowledgement)
          .font(.system(size: 14.5))
      }
      .toggleStyle(.checkbox)
      .controlSize(.large)
      .tint(OmarchyTheme.accent)
      InfoTip(text: PlainLanguage.planAcknowledgementTooltip)
      Spacer(minLength: 0)
    }
    .padding(.top, 14)
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
