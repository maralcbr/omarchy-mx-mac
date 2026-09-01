import Foundation
import OmarchyInstallerUXCore

/// Chooses the environment the window runs against.
///
/// In a release build the preview branch does not exist: `scenario(from:)`
/// compiles to `nil` and the preview type is not in the binary at all.
enum InstallerEnvironmentFactory {
  static func make(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> any InstallerEnvironment {
    #if DEBUG
      if let scenario = InstallerPreviewSelection.scenario(from: environment) {
        return PreviewInstallerEnvironment(
          scenario: scenario,
          journalURL: InstallerPreviewSelection.journalURL(from: environment)
        )
      }
    #endif
    return LiveInstallerEnvironment()
  }
}
