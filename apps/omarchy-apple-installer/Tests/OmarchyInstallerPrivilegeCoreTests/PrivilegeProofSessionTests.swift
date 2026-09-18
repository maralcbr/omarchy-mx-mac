import Foundation
import XCTest

@testable import OmarchyInstallerPrivilegeCore

@MainActor
final class PrivilegeProofSessionTests: XCTestCase {
  func testPassRequiresAuthenticatedRootReplyAndRetirement() async {
    let backend = ProofBackendFixture()
    let session = PrivilegeProofSession(backend: backend)
    await session.run(.roundTrip)
    XCTAssertTrue(session.passed)
    XCTAssertFalse(session.isRunning)
    XCTAssertTrue(session.evidence.contains { $0.contains("effective UID 0") })
    let effects = await backend.effects
    XCTAssertEqual(effects, [.submitted, .probed, .finished, .retired])
  }

  func testAuthorizationCancellationDoesNotSubmitOrContactWorker() async {
    let backend = ProofBackendFixture(failure: .authorization)
    let session = PrivilegeProofSession(backend: backend)
    await session.run(.roundTrip)
    XCTAssertFalse(session.passed)
    XCTAssertTrue(session.status.contains("cancelled"))
    let effects = await backend.effects
    XCTAssertTrue(effects.isEmpty)
  }

  func testUnusedWorkerCheckSendsNoXPCRequest() async {
    let backend = ProofBackendFixture()
    let session = PrivilegeProofSession(backend: backend)
    await session.run(.idleExpiry)
    XCTAssertTrue(session.passed)
    let effects = await backend.effects
    XCTAssertEqual(effects, [.submitted, .retired])
    let mode = await backend.retirementMode
    XCTAssertEqual(mode, .idleExpiry)
  }

  func testForeignSessionOrNonRootReplyFailsAndCleansOnlyThisRun() async {
    for failure in [ProofBackendFixture.Failure.foreignReply, .nonRootReply] {
      let backend = ProofBackendFixture(failure: failure)
      let session = PrivilegeProofSession(backend: backend)
      await session.run(.roundTrip)
      XCTAssertFalse(session.passed)
      let effects = await backend.effects
      XCTAssertEqual(effects, [.submitted, .probed, .removed])
      XCTAssertTrue(session.status.contains("did not match"))
    }
  }

  func testConnectionFailureReportsFailureEvenWhenCleanupSucceeds() async {
    let backend = ProofBackendFixture(failure: .connection)
    let session = PrivilegeProofSession(backend: backend)
    await session.run(.roundTrip)
    XCTAssertFalse(session.passed)
    XCTAssertTrue(session.status.contains("authenticated reply"))
    let effects = await backend.effects
    XCTAssertEqual(effects, [.submitted, .removed])
  }

  func testReplyWithoutVerifiedExitIsNeverAPass() async {
    let backend = ProofBackendFixture(failure: .retirement)
    let session = PrivilegeProofSession(backend: backend)
    await session.run(.roundTrip)
    XCTAssertFalse(session.passed)
    XCTAssertTrue(session.status.contains("retirement could not be verified"))
  }

  func testCleanupFailurePreservesOriginalFailureAndDoesNotClaimRetirement() async {
    let backend = ProofBackendFixture(failure: .cleanup)
    let session = PrivilegeProofSession(backend: backend)
    await session.run(.roundTrip)
    XCTAssertFalse(session.passed)
    XCTAssertTrue(session.status.contains("authenticated reply"))
    XCTAssertTrue(session.status.contains("Cleanup also failed"))
    XCTAssertFalse(session.evidence.contains { $0.contains("no longer active") })
  }

  func testAdHocReviewBuildCannotRequestAuthorization() async {
    let backend = ServiceManagementProofBackend(
      bundleURL: URL(fileURLWithPath: "/untrusted.app"), allowsAuthorization: false)
    let session = PrivilegeProofSession(backend: backend)
    await session.run(.roundTrip)
    XCTAssertFalse(session.passed)
    XCTAssertTrue(session.status.contains("review build"))
    XCTAssertTrue(session.evidence.isEmpty)
  }

  func testRequirementsRejectInjectedIdentityAndMalformedTeam() throws {
    XCTAssertThrowsError(
      try PrivilegeProofIdentity.requirement(identifier: "arbitrary", team: "ABCDEFGHIJ"))
    XCTAssertThrowsError(
      try PrivilegeProofIdentity.requirement(
        identifier: PrivilegeProofIdentity.app, team: "x\" or true"))
    let requirement = try PrivilegeProofIdentity.requirement(
      identifier: PrivilegeProofIdentity.worker, team: "ABCDEFGHIJ")
    XCTAssertTrue(InstallerCodeSigningRequirement.isValid(requirement))
    XCTAssertFalse(InstallerCodeSigningRequirement.isValid("identifier \"unterminated"))
  }
}

private actor ProofBackendFixture: PrivilegeProofBackend {
  enum Failure { case authorization, foreignReply, nonRootReply, connection, retirement, cleanup }
  enum Effect { case submitted, probed, finished, retired, removed }
  let failure: Failure?
  var active: UUID?
  var effects: [Effect] = []
  var retirementMode: PrivilegeProofMode?
  init(failure: Failure? = nil) { self.failure = failure }

  func start(_ launch: PrivilegeProofLaunch) throws {
    if failure == .authorization { throw PrivilegeProofError.authorizationCancelled }
    active = launch.id
    effects.append(.submitted)
  }

  func probe(_ launch: PrivilegeProofLaunch) throws -> PrivilegeProofReply {
    XCTAssertEqual(active, launch.id)
    if failure == .connection || failure == .cleanup { throw PrivilegeProofError.connectionFailed }
    effects.append(.probed)
    return PrivilegeProofReply(
      launch: failure == .foreignReply ? PrivilegeProofLaunch() : launch,
      effectiveUserID: failure == .nonRootReply ? 501 : 0, processID: 123)
  }

  func finish(_ launch: PrivilegeProofLaunch) {
    XCTAssertEqual(active, launch.id)
    effects.append(.finished)
  }

  func waitForExit(_ launch: PrivilegeProofLaunch, mode: PrivilegeProofMode) throws {
    XCTAssertEqual(active, launch.id)
    retirementMode = mode
    if failure == .retirement { throw PrivilegeProofError.retirementUnverified }
    effects.append(.retired)
  }

  func remove(_ launch: PrivilegeProofLaunch) throws {
    XCTAssertEqual(active, launch.id)
    if failure == .cleanup { throw PrivilegeProofError.retirementUnverified }
    effects.append(.removed)
  }
}
