import XCTest

@testable import OmarchyAppleInstallerTrustCore

final class InstallerAllocationRecommendationTests: XCTestCase {
  private let gib: UInt64 = 1_073_741_824

  func testResizeCeilingWithholdsADriftMargin() throws {
    let resize = candidate(
      kind: "resize",
      source: "disk0s2",
      length: 600 * gib,
      minimumInstall: 64 * gib,
      minimumContainer: 200 * gib
    )

    let recommendation = try InstallerAllocationRecommendation(
      inventory: inventory([resize])
    )

    // 400 GiB of headroom: 5% would be 20 GiB, capped at 8 GiB.
    XCTAssertEqual(recommendation.maximumBytes, 392 * gib)
  }

  func testDriftMarginIsFivePercentBelowTheCap() throws {
    let resize = candidate(
      kind: "resize",
      source: "disk0s2",
      length: 300 * gib,
      minimumInstall: 64 * gib,
      minimumContainer: 200 * gib
    )

    let recommendation = try InstallerAllocationRecommendation(
      inventory: inventory([resize])
    )

    XCTAssertEqual(recommendation.maximumBytes, 95 * gib)
  }

  func testDriftMarginAppliesAfterTheHandoffReserve() throws {
    let resize = candidate(
      kind: "resize",
      source: "disk0s2",
      length: 300 * gib,
      minimumInstall: 64 * gib,
      minimumContainer: 200 * gib
    )

    let recommendation = try InstallerAllocationRecommendation(
      inventory: inventory([resize]),
      reservedBytes: 10 * gib
    )

    // 90 GiB after the reserve, 4.5 GiB of it withheld.
    XCTAssertEqual(recommendation.maximumBytes, 85 * gib + gib / 2)
  }

  func testFreeExtentKeepsItsFullCeiling() throws {
    let free = candidate(
      kind: "free",
      source: "disk0s3",
      length: 300 * gib,
      minimumInstall: 64 * gib
    )

    let recommendation = try InstallerAllocationRecommendation(
      inventory: inventory([free])
    )

    // A free extent is fixed on the partition map, so nothing is withheld.
    XCTAssertEqual(recommendation.maximumBytes, 300 * gib)
  }

  func testTightDiskClampsToMinimumInstallInsteadOfDroppingTheMargin() throws {
    // 66 GiB of headroom: the full 3.3 GiB margin would fall below the 64 GiB
    // minimum, so the ceiling keeps the 2 GiB that still fits.
    let resize = candidate(
      kind: "resize",
      source: "disk0s2",
      length: 266 * gib,
      minimumInstall: 64 * gib,
      minimumContainer: 200 * gib
    )

    let recommendation = try InstallerAllocationRecommendation(
      inventory: inventory([resize])
    )

    XCTAssertEqual(recommendation.maximumBytes, 64 * gib)
    XCTAssertEqual(recommendation.requestedLengthBytes, 64 * gib)
  }

  func testTightDiskClampUsesTheAlignedMinimum() throws {
    let unit = PinnedAsahiPlanRequest.allocationUnitBytes
    let resize = candidate(
      kind: "resize",
      source: "disk0s2",
      length: 266 * gib,
      minimumInstall: 64 * gib + 1,
      minimumContainer: 200 * gib
    )

    let recommendation = try InstallerAllocationRecommendation(
      inventory: inventory([resize])
    )

    XCTAssertEqual(recommendation.minimumBytes, 64 * gib + unit)
    XCTAssertEqual(recommendation.maximumBytes, 64 * gib + unit)
  }

  func testDiskAtExactMinimumStaysInstallable() throws {
    let resize = candidate(
      kind: "resize",
      source: "disk0s2",
      length: 264 * gib,
      minimumInstall: 64 * gib,
      minimumContainer: 200 * gib
    )

    let recommendation = try InstallerAllocationRecommendation(
      inventory: inventory([resize])
    )

    XCTAssertEqual(recommendation.maximumBytes, 64 * gib)
  }

  /// The layout that refused four installs on an M2 Max (#120): a 494.4 GB
  /// container with 383.1 GB of headroom, which installed once approved at
  /// 370 GB. Execution sees the handoff copies plus 4 GiB of other writes.
  func testObservedM2MaxLayoutSurvivesHandoffAndChurn() throws {
    let handoffBytes: UInt64 = 8_492_104_840
    let resize = candidate(
      kind: "resize",
      source: "disk0s2",
      length: 494_384_795_648,
      minimumInstall: 76_562_825_216,
      minimumContainer: 111_240_282_112
    )

    let recommendation = try InstallerAllocationRecommendation(
      inventory: inventory([resize]),
      targetBytes: resize.lengthBytes,
      reservedBytes: handoffBytes
    )

    XCTAssertLessThan(recommendation.requestedLengthBytes, 370_000_000_000)
    let executionCandidate = candidate(
      kind: "resize",
      source: "disk0s2",
      length: resize.lengthBytes,
      minimumInstall: resize.minimumInstallBytes,
      minimumContainer: resize.minimumContainerBytes + handoffBytes + 4 * gib
    )
    XCTAssertNoThrow(
      try PinnedAsahiPlanRequest(
        inventory: inventory([executionCandidate]),
        candidate: executionCandidate,
        requestedLengthBytes: recommendation.requestedLengthBytes
      )
    )
  }

  func testRecommendationPrefersEligibleFreeExtentWithoutCheckingSnapshots() throws {
    let resize = candidate(
      kind: "resize",
      source: "disk0s2",
      length: 600 * gib,
      minimumInstall: 64 * gib,
      minimumContainer: 200 * gib
    )
    let free = candidate(
      kind: "free",
      source: "disk0s3",
      length: 300 * gib,
      minimumInstall: 64 * gib
    )

    let recommendation = try InstallerAllocationRecommendation(
      inventory: inventory([resize, free]),
      snapshotConstraint: {
        XCTFail("Eligible free space must not trigger snapshot diagnostics.")
        return .timeMachine
      }
    )

    XCTAssertEqual(recommendation.candidate, free)
    XCTAssertEqual(recommendation.requestedLengthBytes, 128 * gib)
  }

  func testClampsToAlignedMaximumWithoutViolatingMinimum() throws {
    let unit = PinnedAsahiPlanRequest.allocationUnitBytes
    let free = candidate(
      kind: "free",
      source: "disk0s3",
      length: 90 * gib + 333,
      minimumInstall: 64 * gib + 1
    )

    let recommendation = try InstallerAllocationRecommendation(
      inventory: inventory([free])
    )

    XCTAssertEqual(recommendation.requestedLengthBytes % unit, 0)
    XCTAssertLessThanOrEqual(
      recommendation.requestedLengthBytes,
      free.lengthBytes
    )
    XCTAssertGreaterThanOrEqual(
      recommendation.requestedLengthBytes,
      free.minimumInstallBytes
    )
  }

  func testInsufficientFreeExtentStillFailsClosedWhenSnapshotDiagnosisIsNil() {
    let free = candidate(
      kind: "free",
      source: "disk0s3",
      length: 32 * gib,
      minimumInstall: 64 * gib
    )
    var checkedSnapshots = false

    XCTAssertThrowsError(
      try InstallerAllocationRecommendation(
        inventory: inventory([free]),
        snapshotConstraint: {
          checkedSnapshots = true
          return nil
        }
      )
    ) {
      XCTAssertEqual(
        $0 as? InstallerAllocationRecommendationError,
        .insufficientSpace(requiredBytes: 64 * gib, availableBytes: 32 * gib)
      )
    }
    XCTAssertTrue(checkedSnapshots)
  }

  func testEmptyInventoryStillChecksForSnapshotConstraint() {
    // The engine omits resize candidates that cannot meet its minimum.
    var checkedSnapshots = false

    XCTAssertThrowsError(
      try InstallerAllocationRecommendation(
        inventory: inventory([]),
        snapshotConstraint: {
          checkedSnapshots = true
          return .timeMachine
        }
      )
    ) {
      XCTAssertEqual(
        $0 as? InstallerAllocationRecommendationError,
        .snapshotConstrained(.timeMachine)
      )
    }
    XCTAssertTrue(checkedSnapshots)
  }

  func testZeroShrinkResizeReportsTimeMachineConstraint() {
    let resize = candidate(
      kind: "resize",
      source: "disk0s2",
      length: 200 * gib,
      minimumInstall: 64 * gib,
      minimumContainer: 200 * gib
    )

    XCTAssertThrowsError(
      try InstallerAllocationRecommendation(
        inventory: inventory([resize]),
        snapshotConstraint: { .timeMachine }
      )
    ) {
      XCTAssertEqual(
        $0 as? InstallerAllocationRecommendationError,
        .snapshotConstrained(.timeMachine)
      )
    }
  }

  func testResizeBelowMinimumInstallSizeReportsOtherSnapshotConstraint() {
    let resize = candidate(
      kind: "resize",
      source: "disk0s2",
      length: 240 * gib,
      minimumInstall: 64 * gib,
      minimumContainer: 200 * gib
    )

    XCTAssertThrowsError(
      try InstallerAllocationRecommendation(
        inventory: inventory([resize]),
        snapshotConstraint: { .other }
      )
    ) {
      XCTAssertEqual(
        $0 as? InstallerAllocationRecommendationError,
        .snapshotConstrained(.other)
      )
    }
  }

  func testRecommendationSelectsEligibleResizeWithoutCheckingSnapshots() throws {
    let free = candidate(
      kind: "free",
      source: "disk0s3",
      length: 32 * gib,
      minimumInstall: 64 * gib
    )
    let resize = candidate(
      kind: "resize",
      source: "disk0s2",
      length: 600 * gib,
      minimumInstall: 64 * gib,
      minimumContainer: 200 * gib
    )

    let recommendation = try InstallerAllocationRecommendation(
      inventory: inventory([free, resize]),
      snapshotConstraint: {
        XCTFail("An eligible resize must not trigger snapshot diagnostics.")
        return .other
      }
    )

    XCTAssertEqual(recommendation.candidate, resize)
    XCTAssertEqual(recommendation.requestedLengthBytes, 128 * gib)
  }

  func testResizeMaximumLeavesRoomForHandoffCopiesBeforeApproval() throws {
    let resize = candidate(
      kind: "resize",
      source: "disk0s2",
      length: 494_384_795_648,
      minimumInstall: 76_562_825_216,
      minimumContainer: 118_385_364_992
    )
    let oldMaximum: UInt64 = 375_999_430_656
    let handoffBytes: UInt64 = 8_492_104_840
    let recommendation = try InstallerAllocationRecommendation(
      inventory: inventory([resize]),
      targetBytes: oldMaximum,
      reservedBytes: handoffBytes
    )

    XCTAssertEqual(recommendation.candidate, resize)
    XCTAssertEqual(recommendation.requestedLengthBytes, recommendation.maximumBytes)
    XCTAssertEqual(recommendation.maximumBytes % PinnedAsahiPlanRequest.allocationUnitBytes, 0)
    XCTAssertGreaterThanOrEqual(
      resize.lengthBytes - resize.minimumContainerBytes - recommendation.maximumBytes,
      handoffBytes
    )

    // The reported failure: helper import raised the minimum after review.
    let executionCandidate = candidate(
      kind: "resize",
      source: "disk0s2",
      length: resize.lengthBytes,
      minimumInstall: resize.minimumInstallBytes,
      minimumContainer: 122_248_232_960
    )
    XCTAssertThrowsError(
      try PinnedAsahiPlanRequest(
        inventory: inventory([executionCandidate]), candidate: executionCandidate,
        requestedLengthBytes: oldMaximum
      )
    )
    XCTAssertNoThrow(
      try PinnedAsahiPlanRequest(
        inventory: inventory([executionCandidate]), candidate: executionCandidate,
        requestedLengthBytes: recommendation.requestedLengthBytes
      )
    )
  }

  func testHandoffReserveDoesNotReduceAlreadyFreeExtent() throws {
    let free = candidate(
      kind: "free", source: "disk0s3", length: 100 * gib,
      minimumInstall: 64 * gib
    )
    let recommendation = try InstallerAllocationRecommendation(
      inventory: inventory([free]), targetBytes: 100 * gib,
      reservedBytes: UInt64.max
    )

    XCTAssertEqual(recommendation.maximumBytes, 100 * gib)
    XCTAssertEqual(recommendation.requestedLengthBytes, 100 * gib)
  }

  func testResizeReserveCannotUnderflowOrViolateInstallMinimum() {
    let resize = candidate(
      kind: "resize", source: "disk0s2", length: 200 * gib,
      minimumInstall: 64 * gib, minimumContainer: 100 * gib
    )
    for (reserve, available) in [(37 * gib, 63 * gib), (100 * gib, 0), (UInt64.max, 0)] {
      XCTAssertThrowsError(
        try InstallerAllocationRecommendation(
          inventory: inventory([resize]), reservedBytes: reserve
        )
      ) {
        XCTAssertEqual(
          $0 as? InstallerAllocationRecommendationError,
          .insufficientSpace(requiredBytes: 64 * gib, availableBytes: available)
        )
      }
    }
  }

  func testTightResizeReportsWhatIsMissing() {
    // MacBook Air M1: diskutil keeps 420.9 GB for macOS, leaving 73.5 GB of a
    // 494.4 GB container for a release that needs 76.6 GB.
    let resize = candidate(
      kind: "resize",
      source: "disk0s2",
      length: 494_384_795_648,
      minimumInstall: 76_562_825_216,
      minimumContainer: 420_856_463_360
    )

    XCTAssertThrowsError(
      try InstallerAllocationRecommendation(inventory: inventory([resize]))
    ) {
      XCTAssertEqual(
        $0 as? InstallerAllocationRecommendationError,
        .insufficientSpace(
          requiredBytes: 76_562_825_216,
          availableBytes: 73_528_246_272
        )
      )
    }
  }

  func testTheLargestShortfallIsReported() {
    let free = candidate(
      kind: "free", source: "disk0s3", length: 10 * gib, minimumInstall: 64 * gib
    )
    let resize = candidate(
      kind: "resize", source: "disk0s2", length: 200 * gib,
      minimumInstall: 64 * gib, minimumContainer: 150 * gib
    )

    XCTAssertThrowsError(
      try InstallerAllocationRecommendation(inventory: inventory([free, resize]))
    ) {
      XCTAssertEqual(
        $0 as? InstallerAllocationRecommendationError,
        .insufficientSpace(requiredBytes: 64 * gib, availableBytes: 50 * gib)
      )
    }
  }

  func testReplaceOnlyInventoryFailsClosed() {
    let replace = candidate(
      kind: "replace",
      source: "disk0s3",
      length: 300 * gib,
      minimumInstall: 64 * gib,
      identityDigest: "sha256:" + String(repeating: "9", count: 64)
    )

    XCTAssertThrowsError(
      try InstallerAllocationRecommendation(
        inventory: inventory([replace]),
        snapshotConstraint: {
          XCTFail("A replace-only inventory must not trigger snapshot diagnostics.")
          return .timeMachine
        }
      )
    ) {
      XCTAssertEqual(
        $0 as? InstallerAllocationRecommendationError,
        .noEligibleCandidate
      )
    }
  }

  func testRepairAndMixedExistingInventoriesFailWithoutCheckingSnapshots() {
    let free = candidate(
      kind: "free",
      source: "disk0s3",
      length: 32 * gib,
      minimumInstall: 64 * gib
    )
    let repair = candidate(
      kind: "repair",
      source: "disk0s2",
      length: 300 * gib,
      minimumInstall: 64 * gib,
      identityDigest: "sha256:" + String(repeating: "9", count: 64)
    )
    let replace = candidate(
      kind: "replace",
      source: "disk0s2",
      length: 300 * gib,
      minimumInstall: 64 * gib,
      identityDigest: "sha256:" + String(repeating: "9", count: 64)
    )

    for candidates in [[repair], [free, repair], [free, replace]] {
      XCTAssertThrowsError(
        try InstallerAllocationRecommendation(
          inventory: inventory(candidates),
          snapshotConstraint: {
            XCTFail("An existing installation must not trigger snapshot diagnostics.")
            return .timeMachine
          }
        )
      ) {
        XCTAssertEqual(
          $0 as? InstallerAllocationRecommendationError,
          .noEligibleCandidate
        )
      }
    }
  }

  func testReplaceCandidateIsNeverAutoSelected() throws {
    let replace = candidate(
      kind: "replace",
      source: "disk0s2",
      length: 600 * gib,
      minimumInstall: 64 * gib,
      identityDigest: "sha256:" + String(repeating: "9", count: 64)
    )
    let free = candidate(
      kind: "free",
      source: "disk0s3",
      length: 300 * gib,
      minimumInstall: 64 * gib
    )

    let recommendation = try InstallerAllocationRecommendation(
      inventory: inventory([replace, free])
    )

    XCTAssertEqual(recommendation.candidate, free)
  }

  private func inventory(
    _ candidates: [ValidatedEngineCandidate]
  ) -> ValidatedEngineInventory {
    ValidatedEngineInventory(
      layoutDigest: "sha256:" + String(repeating: "a", count: 64),
      systemStoreIdentifier: "disk0",
      candidates: candidates
    )
  }

  private func candidate(
    kind: String,
    source: String,
    length: UInt64,
    minimumInstall: UInt64,
    minimumContainer: UInt64 = 0,
    identityDigest: String? = nil
  ) -> ValidatedEngineCandidate {
    ValidatedEngineCandidate(
      kind: kind,
      sourceIdentifier: source,
      offsetBytes: 0,
      lengthBytes: length,
      minimumInstallBytes: minimumInstall,
      minimumContainerBytes: minimumContainer,
      identityDigest: identityDigest
    )
  }
}
