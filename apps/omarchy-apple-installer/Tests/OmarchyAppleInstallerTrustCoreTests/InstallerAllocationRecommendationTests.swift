import XCTest

@testable import OmarchyAppleInstallerTrustCore

final class InstallerAllocationRecommendationTests: XCTestCase {
  private let gib: UInt64 = 1_073_741_824

  func testPrefersFreeExtentAndBalancedTarget() throws {
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
      inventory: inventory([resize, free])
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

  func testFailsClosedWhenNoCandidateCanMeetMinimum() {
    let free = candidate(
      kind: "free",
      source: "disk0s3",
      length: 32 * gib,
      minimumInstall: 64 * gib
    )

    XCTAssertThrowsError(
      try InstallerAllocationRecommendation(inventory: inventory([free]))
    ) {
      XCTAssertEqual(
        $0 as? InstallerAllocationRecommendationError,
        .noEligibleCandidate
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
      try InstallerAllocationRecommendation(inventory: inventory([replace]))
    ) {
      XCTAssertEqual(
        $0 as? InstallerAllocationRecommendationError,
        .noEligibleCandidate
      )
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
