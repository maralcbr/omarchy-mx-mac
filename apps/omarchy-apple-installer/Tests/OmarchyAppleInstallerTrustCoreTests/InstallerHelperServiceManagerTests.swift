#if os(macOS)
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  final class InstallerHelperServiceManagerTests: XCTestCase {
    func testReportsEnabledWhenControllerSeesInstalledDaemon() {
      let manager = InstallerHelperServiceManager(
        controller: FixtureHelperServiceController(status: .enabled)
      )

      XCTAssertEqual(manager.status, .enabled)
    }

    func testReportsNotInstalledWhenControllerSeesMissingDaemon() {
      let manager = InstallerHelperServiceManager(
        controller: FixtureHelperServiceController(status: .notInstalled)
      )

      XCTAssertEqual(manager.status, .notInstalled)
    }

    func testReachabilityChecksTheCanonicalSystemLaunchDaemonPath() {
      XCTAssertEqual(
        InstallerProductIdentity.systemLaunchDaemonPath,
        "/Library/LaunchDaemons/com.omarchy.mx.installer.helper.plist"
      )
    }
  }

  private struct FixtureHelperServiceController:
    InstallerHelperServiceControlling
  {
    let status: InstallerHelperServiceStatus
  }
#endif
