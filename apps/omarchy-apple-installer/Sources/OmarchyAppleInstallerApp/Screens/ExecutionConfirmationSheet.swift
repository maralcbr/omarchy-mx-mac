import OmarchyInstallerUXCore
import SwiftUI

/// The app's own confirmation: roomier than the system dialog, with the
/// wording, the buttons, and the space between them under the app's control.
/// Every confirmation in the installer uses this so they all look alike.
struct ConfirmationSheet: View {
  let title: String
  let body_: String
  let action: String
  let onConfirm: () -> Void
  let onCancel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.system(size: 19, weight: .semibold))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 14)
      Text(body_)
        .font(.system(size: 14))
        .foregroundStyle(OmarchyTheme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 34)
      HStack(spacing: 16) {
        Spacer(minLength: 0)
        Button(PlainLanguage.cancel, action: onCancel)
          .omarchySecondaryButton()
          .keyboardShortcut(.cancelAction)
        Button(action, action: onConfirm)
          .omarchyPrimaryButton()
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(32)
    .frame(width: 520)
    .background(OmarchyTheme.window)
    // No keyboard-focus ring on the buttons; the sheet's own styling is enough.
    .focusEffectDisabled()
  }
}

/// The last stop before anything is written.
struct ExecutionConfirmationSheet: View {
  let onConfirm: () -> Void
  let onCancel: () -> Void

  var body: some View {
    ConfirmationSheet(
      title: PlainLanguage.executionConfirmationTitle,
      body_: PlainLanguage.executionConfirmationBody,
      action: PlainLanguage.executionConfirmationAction,
      onConfirm: onConfirm,
      onCancel: onCancel
    )
  }
}
