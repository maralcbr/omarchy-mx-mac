#if os(macOS)
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  final class InstallerHelperServiceManagerTests: XCTestCase {
    func testReadingStatusDoesNotRegisterHelper() {
      let controller = FixtureHelperServiceController(status: .notRegistered)
      let manager = InstallerHelperServiceManager(controller: controller)

      XCTAssertEqual(manager.status, .notRegistered)
      XCTAssertEqual(controller.registrationCount, 0)
    }

    func testRegistrationRequiresExplicitMethodCall() throws {
      let controller = FixtureHelperServiceController(status: .requiresApproval)
      let manager = InstallerHelperServiceManager(controller: controller)

      try manager.registerAfterOwnerAuthorization()

      XCTAssertEqual(controller.registrationCount, 1)
    }
  }

  private final class FixtureHelperServiceController:
    InstallerHelperServiceControlling,
    @unchecked Sendable
  {
    let status: InstallerHelperServiceStatus
    private(set) var registrationCount = 0

    init(status: InstallerHelperServiceStatus) {
      self.status = status
    }

    func register() throws {
      registrationCount += 1
    }
  }
#endif
