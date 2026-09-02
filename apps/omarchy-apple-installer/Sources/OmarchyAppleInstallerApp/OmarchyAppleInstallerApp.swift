import AppKit
import OmarchyAppleInstallerTrustCore
import OmarchyInstallerUXCore
import SwiftUI

@MainActor
private final class InstallerApplicationDelegate: NSObject, NSApplicationDelegate {
  private var instanceLease: InstallerAppInstanceLease?

  func applicationWillFinishLaunching(_ notification: Notification) {
    do {
      let lockFile = try InstallerAppInstanceLease.defaultLockFileURL()
      instanceLease = try InstallerAppInstanceLease.acquire(at: lockFile)
    } catch {
      fputs("Omarchy MX Mac Installer refused a duplicate or unsafe launch: \(error)\n", stderr)
      NSApplication.shared.terminate(nil)
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  #if DEBUG
    func applicationDidFinishLaunching(_ notification: Notification) {
      // A bare SwiftPM executable has no Info.plist, so Launch Services
      // registers it background-only and the window never appears. Promote
      // unbundled debug runs to a regular, frontmost app; the packaged app
      // is already regular and never enters this branch.
      if Bundle.main.bundleURL.pathExtension != "app" {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
      }
    }
  #endif
}

@main
struct OmarchyAppleInstallerApp: App {
  @NSApplicationDelegateAdaptor(InstallerApplicationDelegate.self)
  private var applicationDelegate

  var body: some Scene {
    WindowGroup(PlainLanguage.windowTitle) {
      InstallerRootView(environment: InstallerEnvironmentFactory.make())
        .frame(minWidth: 720, minHeight: 496)
        .tint(OmarchyTheme.accent)
    }
    .defaultSize(width: 800, height: 560)
    .windowResizability(.contentMinSize)
  }
}
