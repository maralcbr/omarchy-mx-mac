#if os(macOS)
  import Foundation

  /// Whether the pre-installed privileged helper is available.
  ///
  /// The helper is a plain system `LaunchDaemon` that the installer package
  /// installs into `/Library/LaunchDaemons` and loads at package-install time,
  /// under the package's single administrator prompt. The app never registers,
  /// approves, or gates on Login Items: it only reports whether the daemon is
  /// present so the flow stays locked when the package has not been run.
  public enum InstallerHelperServiceStatus: Equatable, Sendable {
    /// The system daemon is installed; its mach service is reachable.
    case enabled
    /// The system daemon is not installed. The installer package must be run.
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

    /// The shipping controller: a synchronous check for the system daemon the
    /// package installed. No SMAppService registration or Login Items approval
    /// is ever involved.
    public static func preinstalledSystemDaemon() -> Self {
      Self(controller: SystemLaunchDaemonController())
    }

    public var status: InstallerHelperServiceStatus {
      controller.status
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
