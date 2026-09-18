#if os(macOS)
  import Foundation

  /// Availability of the helper executable; authorization is checked at execution.
  public enum InstallerHelperServiceStatus: Equatable, Sendable {
    /// The selected helper executable is available.
    case enabled
    /// The selected helper executable is unavailable.
    case notInstalled
  }

  /// The injection seam. The shipping controller checks the filesystem; tests
  /// supply a fake that returns a fixed status.
  public protocol InstallerHelperServiceControlling: Sendable {
    var status: InstallerHelperServiceStatus { get }
  }

  public struct InstallerHelperServiceManager: Sendable {
    private let controller: any InstallerHelperServiceControlling

    public init(controller: any InstallerHelperServiceControlling) {
      self.controller = controller
    }

    /// Legacy compatibility controller: a synchronous check for the system daemon the
    /// package installed. No SMAppService registration or Login Items approval
    /// is ever involved.
    public static func preinstalledSystemDaemon() -> Self {
      Self(controller: SystemLaunchDaemonController())
    }

    public static func embeddedWorker() -> Self {
      Self(controller: EmbeddedWorkerController())
    }

    public var status: InstallerHelperServiceStatus {
      controller.status
    }
  }

  private struct EmbeddedWorkerController: InstallerHelperServiceControlling {
    var status: InstallerHelperServiceStatus {
      let worker = Bundle.main.bundleURL.appendingPathComponent(
        TemporaryInstallerWorker.embeddedWorkerPath)
      return FileManager.default.isExecutableFile(atPath: worker.path) ? .enabled : .notInstalled
    }
  }

  /// Reports the helper as reachable when its LaunchDaemon plist is present at
  /// the canonical system path. Existence is a synchronous `stat`, so it is
  /// safe to read from the main actor and never blocks on an XPC probe.
  private struct SystemLaunchDaemonController:
    InstallerHelperServiceControlling
  {
    var status: InstallerHelperServiceStatus {
      FileManager.default.fileExists(
        atPath: InstallerProductIdentity.systemLaunchDaemonPath
      ) ? .enabled : .notInstalled
    }
  }
#endif
