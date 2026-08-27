#if os(macOS)
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  final class InstallerWorkflowHostTests: XCTestCase {
    func testObservedM1KeepsCatalogAndOwnerGates() {
      let preview = InstallerWorkflow().preview(
        for: host(
          deviceIdentifier: "apple,j314s",
          eligibility: .requiresSignedCatalog
        )
      )

      XCTAssertEqual(preview.deviceIdentifier, "apple,j314s")
      XCTAssertNil(preview.blockedReason)
      XCTAssertEqual(preview.steps[0].status, .observed)
      XCTAssertEqual(preview.steps[1].status, .planned)
      XCTAssertEqual(preview.requiredOwnerSteps.map(\.id), ["recovery"])
      XCTAssertFalse(preview.canMutateSystem)
    }

    func testObservedM4BlocksEveryPreparationStep() {
      let reason = "The current Asahi installer does not support this Apple model."
      let preview = InstallerWorkflow().preview(
        for: host(
          deviceIdentifier: "apple,j614s",
          eligibility: .blocked(reason: reason)
        )
      )

      XCTAssertEqual(preview.blockedReason, reason)
      XCTAssertEqual(
        preview.steps.map(\.status),
        [.observed, .blocked, .blocked, .blocked, .blocked, .locked]
      )
      XCTAssertTrue(preview.requiredOwnerSteps.isEmpty)
      XCTAssertFalse(preview.canMutateSystem)
    }

    private func host(
      deviceIdentifier: String,
      eligibility: AppleSiliconInstallEligibility
    ) -> AppleSiliconHostInspection {
      AppleSiliconHostInspection(
        identity: AppleMacIdentity(
          model: "MacBookPro",
          chip: "Apple Silicon",
          deviceIdentifier: deviceIdentifier
        ),
        eligibility: eligibility,
        macOSVersion: "Version 15.6",
        powerSource: .ac,
        fileVaultEnabled: true,
        storage: APFSStorageInspection(
          containerIdentifier: "disk3",
          physicalStoreIdentifier: "disk0s2",
          isInternal: true,
          containerSizeBytes: 1_000,
          containerFreeBytes: 500,
          minimumPreferredSizeBytes: 600
        )
      )
    }
  }
#endif
