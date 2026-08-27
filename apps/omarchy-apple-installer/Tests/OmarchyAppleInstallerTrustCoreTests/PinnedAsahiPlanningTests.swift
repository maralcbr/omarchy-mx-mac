import XCTest

@testable import OmarchyAppleInstallerTrustCore

final class PinnedAsahiPlanningTests: XCTestCase {
  func testFreeCandidateProducesExactAlignedRequest() throws {
    let candidate = freeCandidate()
    let request = try PinnedAsahiPlanRequest(
      inventory: inventory(candidate),
      candidate: candidate,
      requestedLengthBytes: 96 * 1_048_576
    )

    XCTAssertEqual(
      request.layoutDigest,
      "sha256:" + String(repeating: "a", count: 64)
    )
    XCTAssertEqual(request.candidateKind, "free")
    XCTAssertEqual(request.sourceIdentifier, "disk0s3")
    XCTAssertEqual(request.requestedLengthBytes, 96 * 1_048_576)
  }

  func testRequestRejectsCandidateFromDifferentInventory() throws {
    let candidate = freeCandidate()
    let other = ValidatedEngineCandidate(
      kind: "free",
      sourceIdentifier: "disk0s4",
      offsetBytes: 300 * 1_048_576,
      lengthBytes: 128 * 1_048_576,
      minimumInstallBytes: 64 * 1_048_576,
      minimumContainerBytes: 0
    )

    XCTAssertThrowsError(
      try PinnedAsahiPlanRequest(
        inventory: inventory(other),
        candidate: candidate,
        requestedLengthBytes: 96 * 1_048_576
      )
    ) {
      XCTAssertEqual(
        $0 as? PinnedAsahiPlanningError,
        .candidateNotInInventory
      )
    }
  }

  func testRequestRejectsUnalignedOrOversizedLength() throws {
    let candidate = freeCandidate()
    for length in [64 * 1_048_576 + 1, 129 * 1_048_576] {
      XCTAssertThrowsError(
        try PinnedAsahiPlanRequest(
          inventory: inventory(candidate),
          candidate: candidate,
          requestedLengthBytes: UInt64(length)
        )
      ) {
        XCTAssertEqual(
          $0 as? PinnedAsahiPlanningError,
          .invalidRequestedLength
        )
      }
    }
  }

  private func inventory(
    _ candidate: ValidatedEngineCandidate
  ) -> ValidatedEngineInventory {
    ValidatedEngineInventory(
      layoutDigest: "sha256:" + String(repeating: "a", count: 64),
      systemStoreIdentifier: "disk0",
      candidates: [candidate]
    )
  }

  private func freeCandidate() -> ValidatedEngineCandidate {
    ValidatedEngineCandidate(
      kind: "free",
      sourceIdentifier: "disk0s3",
      offsetBytes: 128 * 1_048_576,
      lengthBytes: 128 * 1_048_576,
      minimumInstallBytes: 64 * 1_048_576,
      minimumContainerBytes: 0
    )
  }
}
