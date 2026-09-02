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
      subheadline: PlainLanguage.checkSubheadline
    ) {
      Panel {
        DeviceRow(
          name: host.modelName,
          meta: host.chipAndSpace,
          badge: StatusBadge(text: PlainLanguage.supportedBadge, kind: .ok)
        )
        .padding(.vertical, 6)
      }
      .padding(.top, 8)
      DetailsPanel(title: PlainLanguage.checkDetailsTitle) {
        PreflightGrid(checks: host.checks)
      }
      .padding(.top, 10)
    } actions: {
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
