import AppKit
import OmarchyAppleInstallerTrustCore
import OmarchyInstallerUXCore
import SwiftUI

/// The window: a step rail and exactly one screen, plus the three
/// confirmation dialogs that gate every privileged or destructive action and
/// the machine-owner sheet.
struct InstallerRootView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var session: InstallerSession
  @State private var showsExecutionConfirmation = false
  @State private var showsRecoveryRetryConfirmation = false
  @State private var showsShutdownConfirmation = false

  init(environment: any InstallerEnvironment) {
    _session = State(initialValue: InstallerSession(environment: environment))
  }

  var body: some View {
    HStack(spacing: 0) {
      InstallerRail(
        current: session.railStep,
        completed: session.completedRailSteps,
        blocked: session.installationBlocked,
        onSelect: { step in session.navigate(to: step) }
      )
      Divider().overlay(OmarchyTheme.separator)
      screen
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OmarchyTheme.content)
    }
    .background(OmarchyTheme.window)
    .task {
      await session.inspect()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        session.refreshHelperStatus()
      }
    }
    .sheet(isPresented: $showsRecoveryRetryConfirmation) {
      ConfirmationSheet(
        title: PlainLanguage.recoveryRetryConfirmationTitle,
        body_: PlainLanguage.recoveryRetryConfirmationBody,
        action: PlainLanguage.recoveryRetryConfirmationAction,
        onConfirm: {
          showsRecoveryRetryConfirmation = false
          session.presentRecoveryRetryCredentials()
        },
        onCancel: { showsRecoveryRetryConfirmation = false }
      )
    }
    .sheet(isPresented: $showsExecutionConfirmation) {
      ExecutionConfirmationSheet(
        onConfirm: {
          showsExecutionConfirmation = false
          session.presentInstallCredentials()
        },
        onCancel: { showsExecutionConfirmation = false }
      )
    }
    .sheet(isPresented: $showsShutdownConfirmation) {
      ConfirmationSheet(
        title: PlainLanguage.shutdownConfirmationTitle,
        body_: PlainLanguage.shutdownConfirmationBody,
        action: PlainLanguage.shutdownConfirmationAction,
        onConfirm: {
          showsShutdownConfirmation = false
          session.shutDown()
          NSApplication.shared.terminate(nil)
        },
        onCancel: { showsShutdownConfirmation = false }
      )
    }
    .sheet(isPresented: sheetBinding) {
      if let context = session.credentialSheet.context {
        CredentialSheet(
          context: context,
          onCancel: { session.dismissCredentials() },
          onSubmit: { authorization in
            Task { await session.submit(authorization) }
          }
        )
      }
    }
  }

  private var sheetBinding: Binding<Bool> {
    Binding(
      get: { session.credentialSheet.context != nil },
      set: { presented in
        if !presented {
          session.dismissCredentials()
        }
      }
    )
  }

  @ViewBuilder
  private var screen: some View {
    switch session.phase {
    case .inspecting:
      InspectingScreen()

    case .unsupported(let failure):
      UnsupportedScreen(
        failure: failure,
        isBusy: session.isBusy,
        onReinspect: { Task { await session.inspect() } }
      )

    case .welcome(let host):
      WelcomeScreen(
        host: host,
        isBusy: session.isBusy,
        onContinue: { Task { await session.continueToPlan() } },
        onReinspect: { Task { await session.inspect() } }
      )

    case .existingInstallChoice(let installs, _):
      ExistingInstallScreen(
        installs: installs,
        isBusy: session.isBusy,
        onReplace: { install in
          Task { await session.chooseReplaceExistingInstall(install) }
        },
        onKeep: { Task { await session.chooseInstallAlongsideExistingInstall() } },
        onBack: { session.cancelExistingInstallChoice() }
      )

    case .preparingPlan(let update):
      PreparingScreen(update: update)

    case .planPrepared(_, let update):
      PreparingScreen(
        update: update,
        isReady: true,
        onContinue: { session.continueToPlanReview() },
        onBack: { session.goBack() }
      )

    case .planReview(let plan, let acknowledged):
      PlanScreen(
        plan: plan,
        mode: .review(acknowledged: acknowledged),
        canStartInstallation: false,
        isBusy: session.isBusy,
        onAcknowledge: { session.setAcknowledged($0) },
        onApprove: { session.approve() },
        onBack: { session.goBack() },
        onSizeChosen: { bytes in Task { await session.replan(omarchyBytes: bytes) } },
        onRequestInstall: {}
      )

    case .awaitingInstall(let plan, let helper, _):
      PlanScreen(
        plan: plan,
        mode: .approved(helper),
        canStartInstallation: session.canStartInstallation,
        isBusy: session.isBusy,
        onAcknowledge: { _ in },
        onApprove: {},
        onBack: { session.goBack() },
        onSizeChosen: { _ in },
        onRequestInstall: { showsExecutionConfirmation = true }
      )

    case .installing(let progress):
      InstallingScreen(progress: progress)

    case .awaitingRecovery(let handoff):
      RecoveryHandoffScreen(
        handoff: handoff,
        onShutDown: { showsShutdownConfirmation = true }
      )

    case .done(let completion):
      CompletionScreen(
        completion: completion,
        onStartOver: { Task { await session.inspect() } }
      )

    case .failed(let failure):
      FailureScreen(
        failure: failure,
        canRetry: session.canRetryRecoveryAuthorization,
        onStartOver: { Task { await session.inspect() } },
        onRetry: { showsRecoveryRetryConfirmation = true }
      )
    }
  }
}
