import OmarchyInstallerUXCore
import SwiftUI

struct WelcomeScreen: View {
  let host: HostDisplay
  let isBusy: Bool
  let onContinue: () -> Void
  let onReinspect: () -> Void

  var body: some View {
    ScreenScaffold(
      headline: PlainLanguage.checkHeadline,
      subheadline: PlainLanguage.checkSubheadline,
      hint: PlainLanguage.checkHint
    ) {
      Panel {
        DeviceRow(
          name: host.modelName,
          meta: host.chipAndSpace,
          badge: StatusBadge(text: PlainLanguage.supportedBadge, kind: .ok)
        )
      }
      DetailsPanel(title: PlainLanguage.checkDetailsTitle) {
        PreflightGrid(checks: host.checks)
      }
    } actions: {
      Button(PlainLanguage.checkAgain, action: onReinspect)
        .omarchySecondaryButton()
        .disabled(isBusy)
      Button(PlainLanguage.checkContinue, action: onContinue)
        .omarchyPrimaryButton()
        .disabled(isBusy)
        .keyboardShortcut(.defaultAction)
    }
  }
}

struct InspectingScreen: View {
  var body: some View {
    ScreenScaffold(
      headline: PlainLanguage.inspectingHeadline,
      subheadline: PlainLanguage.inspectingSubheadline
    ) {
      Panel {
        ProgressTrack(fraction: nil)
      }
    } actions: {
      EmptyView()
    }
  }
}
