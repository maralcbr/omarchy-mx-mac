import XCTest

@testable import OmarchyInstallerPrivilegeCore

final class PrivilegeProofRetirementTests: XCTestCase {
  func testStartupFailureCannotPassAsIdleExpiryEvenIfObservedMuchLater() throws {
    var evidence = PrivilegeProofRetirement()
    XCTAssertFalse(
      try evidence.observe(
        jobPresent: true, processPresent: true, elapsed: .zero, mode: .idleExpiry))
    XCTAssertThrowsError(
      try evidence.observe(
        jobPresent: false, processPresent: false, elapsed: .seconds(14), mode: .idleExpiry)
    ) { error in
      XCTAssertEqual(error as? PrivilegeProofError, .workerExitedEarly)
    }
  }

  func testIdleExpiryRequiresPositiveLivenessAcrossTheExpectedLifetime() throws {
    var evidence = PrivilegeProofRetirement()
    for second in 0...11 {
      XCTAssertFalse(
        try evidence.observe(
          jobPresent: true, processPresent: true, elapsed: .seconds(second), mode: .idleExpiry))
    }
    XCTAssertTrue(
      try evidence.observe(
        jobPresent: false, processPresent: false, elapsed: .seconds(12), mode: .idleExpiry))
  }

  func testNormalReplyCanRetireEarlyButRequiresBothProcessAndJobAbsence() throws {
    var evidence = PrivilegeProofRetirement()
    _ = try evidence.observe(
      jobPresent: true, processPresent: true, elapsed: .zero, mode: .roundTrip)
    for (job, process) in [(true, false), (false, true)] {
      XCTAssertFalse(
        try evidence.observe(
          jobPresent: job, processPresent: process, elapsed: .milliseconds(250), mode: .roundTrip))
    }
    XCTAssertTrue(
      try evidence.observe(
        jobPresent: false, processPresent: false, elapsed: .milliseconds(500), mode: .roundTrip))
  }

  func testNeverObservedWorkerIsNotSuccessfulRetirement() {
    var evidence = PrivilegeProofRetirement()
    XCTAssertThrowsError(
      try evidence.observe(
        jobPresent: false, processPresent: false, elapsed: .seconds(12), mode: .roundTrip)
    ) { error in
      XCTAssertEqual(error as? PrivilegeProofError, .retirementUnverified)
    }
  }
}
