import OmarchyInstallerUXCore
import SwiftUI

/// Screen A2: this Mac already has at least one Omarchy install. The owner
/// decides whether the new install replaces one of them or goes alongside.
/// Nothing is erased here — a replace choice only shapes the exact plan that
/// still needs review, approval, and the machine-owner password.
struct ExistingInstallScreen: View {
  let installs: [ExistingInstallDisplay]
  let isBusy: Bool
  let onReplace: (ExistingInstallDisplay) -> Void
  let onKeep: () -> Void
  let onBack: () -> Void

  var body: some View {
    ScreenScaffold(
      headline: PlainLanguage.existingInstallHeadline,
      subheadline: PlainLanguage.existingInstallSubheadline,
      hint: PlainLanguage.existingInstallHint
    ) {
      DetailsPanel(title: PlainLanguage.existingInstallDetailsTitle) {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(installs) { install in
            HStack {
              Text(PlainLanguage.existingInstallRow(install))
              Spacer()
              Button(PlainLanguage.existingInstallReplace) {
                onReplace(install)
              }
              .omarchySecondaryButton()
              .disabled(isBusy)
            }
          }
          Text(PlainLanguage.existingInstallReplaceDetail)
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(PlainLanguage.existingInstallKeepDetail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    } actions: {
      Button(PlainLanguage.existingInstallBack, action: onBack)
        .omarchySecondaryButton()
        .disabled(isBusy)
      Button(PlainLanguage.existingInstallKeep, action: onKeep)
        .omarchyPrimaryButton()
        .disabled(isBusy)
        .keyboardShortcut(.defaultAction)
    }
  }
}
