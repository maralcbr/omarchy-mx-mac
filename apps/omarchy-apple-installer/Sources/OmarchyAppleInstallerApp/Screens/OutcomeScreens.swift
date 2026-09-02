import OmarchyInstallerUXCore
import SwiftUI

/// Screen E — the Recovery handoff.
struct RecoveryHandoffScreen: View {
  let handoff: HandoffDisplay
  let onShutDown: () -> Void

  var body: some View {
    ScreenScaffold(
      headline: handoff.headline,
      subheadline: handoff.subheadline,
      hint: handoff.hint.isEmpty ? nil : handoff.hint
    ) {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(handoff.steps) { step in
          RecoveryStepRow(step: step)
        }
      }
      DetailsPanel(title: PlainLanguage.recoveryDetailsTitle) {
        Text(handoff.explainer)
          .font(OmarchyTheme.body)
          .foregroundStyle(OmarchyTheme.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
    } actions: {
      Button(PlainLanguage.recoveryShutDown, action: onShutDown)
        .omarchyPrimaryButton()
        .keyboardShortcut(.defaultAction)
    }
  }
}

/// Screen F — installed.
struct CompletionScreen: View {
  let completion: CompletionDisplay
  let onStartOver: () -> Void

  var body: some View {
    ScreenScaffold(
      headline: completion.headline,
      subheadline: completion.subheadline
    ) {
      Text("✓")
        .font(.system(size: 30, weight: .bold))
        .foregroundStyle(OmarchyTheme.accent)
      DetailsPanel(title: PlainLanguage.doneDetailsTitle) {
        FactGrid(rows: completion.verified, labelWidth: 118)
      }
    } actions: {
      Button(PlainLanguage.startOver, action: onStartOver)
        .omarchySecondaryButton()
    }
  }
}

/// The blocked model: locked, fail-closed, re-inspect only.
struct UnsupportedScreen: View {
  let failure: FailureDisplay
  let isBusy: Bool
  let onReinspect: () -> Void

  var body: some View {
    ScreenScaffold(
      headline: failure.headline,
      headlineIsError: false,
      subheadline: failure.plainDetail
    ) {
      if let device = failure.device {
        Panel {
          DeviceRow(
            name: device.modelName,
            meta: device.deviceIdentifier,
            badge: StatusBadge(text: PlainLanguage.blockedBadge, kind: .blocked)
          )
        }
      }
      DetailsPanel(title: PlainLanguage.blockedDetailsTitle) {
        Text(failure.remedy ?? PlainLanguage.blockedExplainer)
          .font(OmarchyTheme.body)
          .foregroundStyle(OmarchyTheme.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
        if let technical = failure.technicalDetail {
          TechnicalDetailText(text: technical)
        }
      }
    } actions: {
      Button(PlainLanguage.checkAgain, action: onReinspect)
        .omarchySecondaryButton()
        .disabled(isBusy)
    }
  }
}

/// Every recoverable stop, including the retry-eligible Recovery failure.
struct FailureScreen: View {
  let failure: FailureDisplay
  let canRetry: Bool
  let onStartOver: () -> Void
  let onRetry: () -> Void

  var body: some View {
    ScreenScaffold(
      headline: failure.headline,
      headlineIsError: true,
      subheadline: failure.plainDetail
    ) {
      if let remedy = failure.remedy {
        Panel {
          Text(remedy)
            .font(OmarchyTheme.body)
            .foregroundStyle(OmarchyTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      if let technical = failure.technicalDetail {
        DetailsPanel(title: PlainLanguage.technicalDetailsTitle) {
          TechnicalDetailText(text: technical)
        }
      }
    } actions: {
      Button(PlainLanguage.startOver, action: onStartOver)
        .omarchySecondaryButton()
      if failure.retryRecoveryAvailable {
        Button(PlainLanguage.retry, action: onRetry)
          .omarchyPrimaryButton()
          .disabled(!canRetry)
          .keyboardShortcut(.defaultAction)
      }
    }
  }
}

/// Raw error text, kept verbatim so nothing is lost behind plain language.
struct TechnicalDetailText: View {
  let text: String

  var body: some View {
    Text(text)
      .font(OmarchyTheme.monospaceSmall)
      .foregroundStyle(OmarchyTheme.secondaryText)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 8).fill(OmarchyTheme.window)
      )
  }
}
