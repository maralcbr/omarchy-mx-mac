import Foundation
import OmarchyInstallerPrivilegeCore
import XCTest

@testable import OmarchyAppleInstallerTrustCore

final class TemporaryInstallerWorkerTests: XCTestCase {
  func testProductionSigningRequirementsAreValidWithoutBroadeningProofIdentities() throws {
    for identifier in [
      TemporaryInstallerWorker.appIdentifier, InstallerProductIdentity.helperIdentifier,
    ] {
      let requirement = try InstallerCodeSigningRequirement.requirement(
        identifier: identifier, team: "T2C384FJBD")
      XCTAssertTrue(InstallerCodeSigningRequirement.isValid(requirement))
      XCTAssertThrowsError(
        try PrivilegeProofIdentity.requirement(identifier: identifier, team: "T2C384FJBD"))
    }
    XCTAssertThrowsError(
      try InstallerCodeSigningRequirement.requirement(
        identifier: "injected\" or true", team: "T2C384FJBD"))
  }

  func testHandshakePinsVersionSessionRootAndObservedWorkerPID() throws {
    let session = UUID()
    let valid: [String: Any] = [
      "version": 1, "session": session.uuidString, "processID": 42, "effectiveUserID": 0,
    ]
    func decode(_ fields: [String: Any]) throws -> InstallerWorkerHandshake {
      try JSONDecoder().decode(
        InstallerWorkerHandshake.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    XCTAssertNoThrow(try decode(valid).validate(session: session, processID: 42))
    for (key, value) in [
      ("version", 2 as Any), ("session", UUID().uuidString), ("processID", 43),
      ("effectiveUserID", 501),
    ] {
      var changed = valid
      changed[key] = value
      XCTAssertThrowsError(try decode(changed).validate(session: session, processID: 42)) {
        XCTAssertEqual($0 as? TemporaryInstallerWorkerError, .incompatibleWorker)
      }
    }
  }

  func testTemporaryServiceCannotCollideWithLegacyService() {
    let first = TemporaryInstallerWorker.serviceName(UUID())
    let second = TemporaryInstallerWorker.serviceName(UUID())
    XCTAssertNotEqual(first, second)
    XCTAssertNotEqual(first, InstallerProductIdentity.helperMachServiceName)
    XCTAssertTrue(AuthenticatedEngineXPCSubmitter.isMachServiceName(first))
  }
}
