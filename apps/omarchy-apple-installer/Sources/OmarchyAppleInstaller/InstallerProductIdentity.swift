import Foundation

public enum InstallerProductIdentity {
  public static let appBundleIdentifier = "com.omarchy.mx.installer"
  public static let appExecutableName = "OmarchyAppleInstallerApp"
  public static let helperIdentifier = "com.omarchy.mx.installer.helper"
  public static let helperExecutableName =
    "omarchy-apple-installer-helper"
  public static let helperMachServiceName = helperIdentifier
  public static let helperDaemonPlistName = helperIdentifier + ".plist"
  /// Where the installer package installs the helper's system LaunchDaemon.
  public static let systemLaunchDaemonDirectory = "/Library/LaunchDaemons"
  /// The absolute path of the pre-installed system LaunchDaemon plist. Its
  /// presence is the app's synchronous reachability signal for the helper.
  public static let systemLaunchDaemonPath =
    systemLaunchDaemonDirectory + "/" + helperDaemonPlistName
  public static let helperWorkingDirectory =
    "/var/db/com.omarchy.mx.installer"
  public static let clientRequirementEnvironmentVariable =
    "OMARCHY_CLIENT_CODE_SIGNING_REQUIREMENT"
}
