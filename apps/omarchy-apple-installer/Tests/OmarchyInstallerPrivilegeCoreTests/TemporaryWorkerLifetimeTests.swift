import XCTest

@testable import OmarchyInstallerPrivilegeCore

final class TemporaryWorkerLifetimeTests: XCTestCase {
  func testLongInstallationCannotBeKilledByIdleTimer() throws {
    let start = ContinuousClock.now
    var lifetime = TemporaryWorkerLifetime(now: start)
    let installation = try lifetime.begin(now: start)
    let muchLater = start.advanced(by: .seconds(7_200))
    XCTAssertFalse(lifetime.shouldRetire(now: muchLater))
    XCTAssertThrowsError(try lifetime.begin(now: muchLater)) {
      XCTAssertEqual($0 as? TemporaryWorkerLifetime.AdmissionError, .busy)
    }
    try lifetime.complete(installation, now: muchLater)
    XCTAssertFalse(lifetime.shouldRetire(now: muchLater.advanced(by: .seconds(299))))
    XCTAssertTrue(lifetime.shouldRetire(now: muchLater.advanced(by: .seconds(300))))
  }

  func testCredentialCorrectionAndRecoveryRetryStayInTheSameBoundedSession() throws {
    let start = ContinuousClock.now
    var lifetime = TemporaryWorkerLifetime(now: start)
    let rejectedCredentials = try lifetime.begin(now: start)
    try lifetime.complete(rejectedCredentials, now: start.advanced(by: .seconds(20)))
    let correctedInstall = try lifetime.begin(now: start.advanced(by: .seconds(40)))
    try lifetime.complete(correctedInstall, now: start.advanced(by: .seconds(1_000)))
    let recoveryRetry = try lifetime.begin(now: start.advanced(by: .seconds(1_100)))
    try lifetime.complete(recoveryRetry, now: start.advanced(by: .seconds(1_200)))
    lifetime.requestRetirement()
    XCTAssertTrue(lifetime.shouldRetire(now: start.advanced(by: .seconds(1_200))))
  }

  func testRemovalPreviewAllowsFiveMinutesForConfirmation() throws {
    let start = ContinuousClock.now
    var lifetime = TemporaryWorkerLifetime(now: start)
    let preview = try lifetime.begin(now: start)
    let previewFinished = start.advanced(by: .seconds(60))
    try lifetime.complete(preview, now: previewFinished)
    XCTAssertFalse(lifetime.shouldRetire(now: previewFinished.advanced(by: .seconds(299))))
    let removal = try lifetime.begin(now: previewFinished.advanced(by: .seconds(299)))
    XCTAssertFalse(lifetime.shouldRetire(now: previewFinished.advanced(by: .seconds(600))))
    try lifetime.complete(removal, now: previewFinished.advanced(by: .seconds(601)))
  }

  func testClosingDuringWorkWaitsForCompletionAndNeverReopensAdmission() throws {
    let start = ContinuousClock.now
    var lifetime = TemporaryWorkerLifetime(now: start)
    let operation = try lifetime.begin(now: start)
    lifetime.requestRetirement()
    lifetime.requestRetirement()
    XCTAssertFalse(lifetime.shouldRetire(now: start.advanced(by: .seconds(1_000))))
    XCTAssertThrowsError(try lifetime.begin(now: start))
    try lifetime.complete(operation, now: start.advanced(by: .seconds(1_001)))
    XCTAssertTrue(lifetime.shouldRetire(now: start))
    XCTAssertThrowsError(try lifetime.begin(now: start)) {
      XCTAssertEqual($0 as? TemporaryWorkerLifetime.AdmissionError, .retiring)
    }
  }

  func testExpiredWorkerRefusesWorkEvenBeforeItsTimerFires() {
    let start = ContinuousClock.now
    var lifetime = TemporaryWorkerLifetime(now: start)
    XCTAssertThrowsError(try lifetime.begin(now: start.advanced(by: .seconds(300)))) {
      XCTAssertEqual($0 as? TemporaryWorkerLifetime.AdmissionError, .retiring)
    }
    XCTAssertTrue(lifetime.shouldRetire(now: start.advanced(by: .seconds(300))))
  }

  func testStaleOrForeignCompletionCannotReleaseCurrentWork() throws {
    let start = ContinuousClock.now
    var lifetime = TemporaryWorkerLifetime(now: start)
    var otherWorker = TemporaryWorkerLifetime(now: start)
    let old = try lifetime.begin(now: start)
    try lifetime.complete(old, now: start)
    let current = try lifetime.begin(now: start)
    let foreign = try otherWorker.begin(now: start)
    for token in [old, foreign] {
      XCTAssertThrowsError(try lifetime.complete(token, now: start)) {
        XCTAssertEqual($0 as? TemporaryWorkerLifetime.AdmissionError, .invalidOperation)
      }
    }
    lifetime.requestRetirement()
    XCTAssertFalse(lifetime.shouldRetire(now: start))
    try lifetime.complete(current, now: start)
    XCTAssertTrue(lifetime.shouldRetire(now: start))
  }

  func testIdleCloseIsImmediateAndIrreversible() {
    let start = ContinuousClock.now
    var lifetime = TemporaryWorkerLifetime(now: start)
    lifetime.requestRetirement()
    XCTAssertTrue(lifetime.shouldRetire(now: start))
    XCTAssertThrowsError(try lifetime.begin(now: start))
  }
}
