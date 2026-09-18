import AppKit
import OmarchyInstallerPrivilegeCore
import SwiftUI

@main
struct PrivilegeProofApp: App {
  @NSApplicationDelegateAdaptor(ProofAppDelegate.self) private var delegate
  @State private var session = PrivilegeProofSession(
    backend: ServiceManagementProofBackend(
      bundleURL: Bundle.main.bundleURL,
      allowsAuthorization: Bundle.main.object(
        forInfoDictionaryKey: "OmarchyProofAllowsAuthorization") as? Bool == true
    ))

  private var allowsAuthorization: Bool {
    Bundle.main.object(forInfoDictionaryKey: "OmarchyProofAllowsAuthorization") as? Bool == true
  }

  var body: some Scene {
    Window("Omarchy · Privilege proof", id: "proof") {
      VStack(alignment: .leading, spacing: 22) {
        Label("Omarchy", systemImage: "externaldrive")
          .font(.title2.bold())
        Text("A temporary worker. One harmless check.")
          .font(.title.bold())
        Text(
          "This qualification app checks administrator authorization, an authenticated reply and worker retirement. It has no install or disk-removal commands."
        )
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        if !allowsAuthorization {
          Label("Review build · administrator access disabled", systemImage: "lock.shield")
            .foregroundStyle(.orange)
        }
        Divider()
        HStack(alignment: .top, spacing: 12) {
          if session.isRunning {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: session.passed ? "checkmark.circle.fill" : "info.circle")
          }
          Text(session.status).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        if !session.evidence.isEmpty {
          ScrollView {
            Text(session.evidence.joined(separator: "\n\n"))
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxHeight: 125)
        }
        Spacer(minLength: 0)
        HStack {
          Button("Check authorization and reply") { Task { await session.run(.roundTrip) } }
            .buttonStyle(.borderedProminent)
          Button("Check unused worker expiry") { Task { await session.run(.idleExpiry) } }
        }
        .disabled(session.isRunning)
        Text(
          "The native prompt can be cancelled. Any worker that starts has a 12-second lifetime limit, including if this app closes."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(30)
      .frame(width: 620, height: 430)
    }
    .windowResizability(.contentSize)
  }
}

private final class ProofAppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
