import Foundation
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

  func testRepairCandidateRequiresItsExactExistingExtent() throws {
    let length: UInt64 = 137_438_953_472
    let candidate = ValidatedEngineCandidate(
      kind: "repair",
      sourceIdentifier: "disk0s2",
      offsetBytes: 857_747_943_424,
      lengthBytes: length,
      minimumInstallBytes: length,
      minimumContainerBytes: 0,
      identityDigest: "sha256:" + String(repeating: "b", count: 64)
    )

    let request = try PinnedAsahiPlanRequest(
      inventory: inventory(candidate),
      candidate: candidate,
      requestedLengthBytes: length
    )
    XCTAssertEqual(request.candidateKind, "repair")
    XCTAssertEqual(request.requestedLengthBytes, length)

    XCTAssertThrowsError(
      try PinnedAsahiPlanRequest(
        inventory: inventory(candidate),
        candidate: candidate,
        requestedLengthBytes: length - PinnedAsahiPlanRequest.allocationUnitBytes
      )
    ) {
      XCTAssertEqual(
        $0 as? PinnedAsahiPlanningError,
        .invalidRequestedLength
      )
    }
  }

  func testReplaceCandidateRequiresItsExactExistingExtent() throws {
    let length: UInt64 = 137_438_953_472
    let candidate = ValidatedEngineCandidate(
      kind: "replace",
      sourceIdentifier: "disk0s3",
      offsetBytes: 857_747_943_424,
      lengthBytes: length,
      minimumInstallBytes: 70_866_960_384,
      minimumContainerBytes: 0,
      identityDigest: "sha256:" + String(repeating: "9", count: 64)
    )

    let request = try PinnedAsahiPlanRequest(
      inventory: inventory(candidate),
      candidate: candidate,
      requestedLengthBytes: length
    )
    XCTAssertEqual(request.candidateKind, "replace")
    XCTAssertEqual(request.requestedLengthBytes, length)

    XCTAssertThrowsError(
      try PinnedAsahiPlanRequest(
        inventory: inventory(candidate),
        candidate: candidate,
        requestedLengthBytes: length - PinnedAsahiPlanRequest.allocationUnitBytes
      )
    ) {
      XCTAssertEqual(
        $0 as? PinnedAsahiPlanningError,
        .invalidRequestedLength
      )
    }
  }

  func testRepairIdentityCarriesManifestDigest() throws {
    let digest = "sha256:" + String(repeating: "7", count: 64)
    let engineDigest = "sha256:" + String(repeating: "d", count: 64)
    let metadataDigest = "sha256:" + String(repeating: "e", count: 64)
    let payloadDigest = "sha256:" + String(repeating: "f", count: 64)
    let identity = try PinnedAsahiPlanIdentity(
      engineVersion: "v0.9.0-omarchy.7",
      engineDigest: engineDigest,
      metadataDigest: metadataDigest,
      payloadDigest: payloadDigest,
      repairManifestDigest: digest
    )

    let encoded = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(identity))
        as? [String: Any]
    )
    XCTAssertEqual(encoded["repair_manifest_digest"] as? String, digest)
  }

  func testInstallIdentityOmitsManifestDigest() throws {
    let identity = try PinnedAsahiPlanIdentity(
      engineVersion: "v0.9.0-omarchy.7",
      engineDigest: "sha256:" + String(repeating: "d", count: 64),
      metadataDigest: "sha256:" + String(repeating: "e", count: 64),
      payloadDigest: "sha256:" + String(repeating: "f", count: 64)
    )

    let encoded = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(identity))
        as? [String: Any]
    )
    XCTAssertNil(encoded["repair_manifest_digest"])
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
