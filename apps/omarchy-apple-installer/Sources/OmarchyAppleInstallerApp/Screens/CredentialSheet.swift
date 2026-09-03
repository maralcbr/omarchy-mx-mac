import AppKit
import OmarchyAppleInstallerTrustCore
import OmarchyInstallerUXCore
import SwiftUI

/// Screen C — the machine-owner authorization sheet.
///
/// Password lifecycle (unchanged from the previous view): the password exists
/// only as sheet-local state, is converted straight into a
/// `MachineOwnerAuthorization` on submit, and is cleared at the same three
/// points — on submit, on cancel, and unconditionally on disappear. Nothing
/// above the XPC boundary can retain the string: the session and environment
/// APIs accept only `MachineOwnerAuthorization`.
struct CredentialSheet: View {
  let context: CredentialSheetContext
  let onCancel: () -> Void
  let onSubmit: (MachineOwnerAuthorization) -> Void

  @State private var input = CredentialInput(username: NSUserName())
  @FocusState private var focus: Field?

  private enum Field: Hashable {
    case username
    case password
  }

  var body: some View {
    VStack(spacing: 0) {
      Text(isRetry ? PlainLanguage.authorizeRetryTitle : PlainLanguage.authorizeTitle)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(OmarchyTheme.accent)
        .multilineTextAlignment(.center)
        .padding(.bottom, 14)

      if context.error == .credentialsRejected {
        Text(PlainLanguage.authorizeRejected)
          .font(OmarchyTheme.caption)
          .foregroundStyle(OmarchyTheme.danger)
          .padding(.bottom, 10)
      }

      field(
        label: PlainLanguage.authorizeUsernameLabel,
        reason: input.usernameReason
      ) {
        TextField("", text: $input.username)
          .textFieldStyle(.roundedBorder)
          .textContentType(.username)
          .autocorrectionDisabled()
          .focused($focus, equals: .username)
          .onSubmit { focus = .password }
      }

      field(
        label: PlainLanguage.authorizePasswordLabel,
        reason: input.passwordReason
      ) {
        SecureField("", text: $input.password)
          .textFieldStyle(.roundedBorder)
          .textContentType(.password)
          .privacySensitive()
          .focused($focus, equals: .password)
          .onSubmit(submit)
      }

      HStack(spacing: 8) {
        if context.isVerifying {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel(PlainLanguage.authorizeChecking)
        }
        Spacer(minLength: 0)
        // fixedSize keeps both buttons at their natural width: the row is
        // narrow, and a squeezed button truncates its label.
        Button(PlainLanguage.authorizeCancel, action: cancel)
          .omarchySecondaryButton()
          .fixedSize()
          .keyboardShortcut(.cancelAction)
          .disabled(context.isVerifying)
        Button(
          isRetry ? PlainLanguage.authorizeRetryAction : PlainLanguage.authorizeInstall,
          action: submit
        )
        .omarchyPrimaryButton()
        .fixedSize()
        .keyboardShortcut(.defaultAction)
        .disabled(!input.isValid || context.isVerifying)
      }
      .padding(.top, 14)
    }
    .padding(24)
    .frame(width: 304)
    .foregroundStyle(OmarchyTheme.text)
    .background(OmarchyTheme.window)
    .disabled(context.isVerifying)
    .animation(.easeInOut(duration: 0.2), value: context.isVerifying)
    .animation(.easeInOut(duration: 0.2), value: context.error)
    .onAppear {
      focus = input.username.isEmpty ? .username : .password
    }
    .onChange(of: context.error) { _, error in
      if error == .credentialsRejected {
        focus = .password
      }
    }
    .onDisappear {
      input.clearPassword()
    }
  }

  private var isRetry: Bool {
    context.kind == .retryRecoveryAuthorization
  }

  private func field<Content: View>(
    label: String,
    reason: String?,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(OmarchyTheme.secondaryText)
      content()
      if let reason {
        Text(reason)
          .font(.system(size: 10))
          .foregroundStyle(OmarchyTheme.secondaryText)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, 10)
  }

  private func submit() {
    guard let authorization = input.validated() else {
      return
    }
    input.clearPassword()
    onSubmit(authorization)
  }

  private func cancel() {
    input.clearPassword()
    onCancel()
  }
}
