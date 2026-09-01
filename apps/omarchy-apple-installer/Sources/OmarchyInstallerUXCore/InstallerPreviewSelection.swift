#if os(macOS)
  import Foundation

  public enum InstallerPreviewScenario: String, CaseIterable, Sendable {
    case freshInstall = "fresh-install"
    case existingInstall = "existing-install"
    case unsupported = "unsupported"
    case credentialReject = "credential-reject"
    case recoveryRetry = "recovery-retry"
    case degradedJournal = "degraded-journal"
  }

  /// Chooses between the live installer environment and the debug-only preview
  /// environment.
  ///
  /// The environment lookup itself is inside `#if DEBUG`, so a release build
  /// cannot be talked into preview mode by any environment variable: the code
  /// that reads it does not exist in the binary.
  public enum InstallerPreviewSelection {
    public static let environmentKey = "OMARCHY_INSTALLER_UI_PREVIEW"
    public static let journalEnvironmentKey =
      "OMARCHY_INSTALLER_UI_PREVIEW_JOURNAL"

    public static func scenario(
      from environment: [String: String]
    ) -> InstallerPreviewScenario? {
      #if DEBUG
        guard let raw = environment[environmentKey],
          !raw.isEmpty
        else {
          return nil
        }
        return InstallerPreviewScenario(rawValue: raw)
      #else
        return nil
      #endif
    }

    public static func journalURL(
      from environment: [String: String]
    ) -> URL? {
      #if DEBUG
        guard let path = environment[journalEnvironmentKey],
          !path.isEmpty
        else {
          return nil
        }
        return URL(fileURLWithPath: path)
      #else
        return nil
      #endif
    }
  }
#endif
