import OmarchyAppleInstallerTrustCore
import XCTest

final class InstallerWorkflowTests: XCTestCase {
  private let preview = InstallerWorkflow().referenceM1ProPreview()

  func testPreviewCannotMutateSystem() {
    XCTAssertEqual(preview.mode, .safePreview)
    XCTAssertEqual(preview.executionGate, .locked)
    XCTAssertFalse(preview.canMutateSystem)
  }

  func testPreviewNamesTheSupportedReferenceCanary() {
    XCTAssertEqual(preview.deviceIdentifier, "apple,j314s")
    XCTAssertEqual(preview.deviceName, "14-inch MacBook Pro with M1 Pro")
    XCTAssertEqual(preview.distributionName, "Omarchy MX Mac")
  }

  func testWorkflowKeepsRecoveryHumanGated() {
    XCTAssertEqual(preview.requiredOwnerSteps.map(\.id), ["recovery"])
    XCTAssertEqual(
      preview.steps.map(\.id),
      ["inspect", "verify", "download", "plan", "recovery", "boot"]
    )
    XCTAssertEqual(preview.steps.last?.status, .locked)
  }
}
