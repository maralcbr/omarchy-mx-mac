import Foundation
import XCTest

@testable import OmarchyInstallerPrivilegeCore

final class PrivilegeProofArtifactPinsTests: XCTestCase {
  private let emptySHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  private let cdhash = "1c1d0d1c7ee1f1608cb61c15956f40f21fe06684"

  func testRevalidationRejectsAnyCandidateFileChangedAfterInitialValidation() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = [
      "Contents/MacOS/OmarchyPrivilegeProofApp",
      "Contents/Helpers/OmarchyPrivilegeProofWorker",
      "Contents/Info.plist",
    ]
    let pins = try PrivilegeProofArtifactPins(
      appSHA256: emptySHA256, workerSHA256: emptySHA256, infoSHA256: emptySHA256,
      workerCDHash: cdhash)
    for relative in files {
      let file = root.appendingPathComponent(relative)
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data().write(to: file)
    }
    try pins.validate(root)
    for relative in files {
      let file = root.appendingPathComponent(relative)
      try Data("changed while authorization was pending".utf8).write(to: file)
      XCTAssertThrowsError(try pins.validate(root), relative)
      try Data().write(to: file)
      try pins.validate(root)
    }
  }

  func testMalformedCodeHashCannotBecomeALaunchConstraint() throws {
    for invalid in ["", "00", String(repeating: "g", count: 40), cdhash.uppercased()] {
      XCTAssertThrowsError(
        try PrivilegeProofArtifactPins(
          appSHA256: emptySHA256, workerSHA256: emptySHA256, infoSHA256: emptySHA256,
          workerCDHash: invalid))
    }
  }
}
