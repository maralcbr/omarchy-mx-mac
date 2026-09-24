#if os(macOS)
  import Foundation
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  final class EngineXPCErrorBridgeTests: XCTestCase {
    func testInvalidMachineOwnerCredentialsRoundTrip() {
      let bridged = EngineXPCErrorBridge.serviceError(
        for: ClosedEngineHelperError.invalidMachineOwnerCredentials
      )

      XCTAssertEqual(
        bridged.domain,
        EngineXPCErrorBridge.machineOwnerAuthorizationDomain
      )
      XCTAssertEqual(
        EngineXPCErrorBridge.submissionError(bridged),
        .machineOwnerCredentialsRejected
      )
    }

    func testRecoveryAuthorizationStillRoundTrips() {
      let bridged = EngineXPCErrorBridge.serviceError(
        for: PinnedAsahiEngineExecutionError.recoveryAuthorizationFailed
      )

      XCTAssertEqual(
        EngineXPCErrorBridge.submissionError(bridged),
        .recoveryAuthorizationFailed
      )
      XCTAssertTrue(
        RecoveryAuthorizationRetryPolicy.isEligible(
          after: EngineXPCSubmissionError.recoveryAuthorizationFailed
        )
      )
    }

    func testCredentialRejectionIsNotRecoveryRetryEligible() {
      XCTAssertFalse(
        RecoveryAuthorizationRetryPolicy.isEligible(
          after: EngineXPCSubmissionError.machineOwnerCredentialsRejected
        )
      )
    }

    func testEngineFailureCarriesOnlyTheNoticeAcrossXPC() throws {
      let report = EngineFailureReport(
        notice: EngineFailureNotice(
          reason: .approvedSpaceChanged, exitStatus: 1, diskUnchanged: true,
          summary: "omarchy_execution.ExecutionAdmissionError: approved extent changed"),
        redactedStandardErrorTail: "TAIL-THAT-MUST-STAY-IN-THE-HELPER"
      )
      let bridged = EngineXPCErrorBridge.serviceError(
        for: PinnedAsahiEngineExecutionError.engineFailed(report))

      XCTAssertEqual(bridged.domain, EngineXPCErrorBridge.engineFailureDomain)
      XCTAssertEqual(bridged.code, EngineFailureReason.approvedSpaceChanged.rawValue)
      XCTAssertEqual(
        Set(bridged.userInfo.keys),
        [
          EngineXPCErrorBridge.exitStatusKey, EngineXPCErrorBridge.diskUnchangedKey,
          EngineXPCErrorBridge.summaryKey,
        ])
      XCTAssertFalse("\(bridged.userInfo)".contains("TAIL-THAT-MUST-STAY"))

      // NSXPCConnection moves NSError through secure coding.
      let archived = try NSKeyedArchiver.archivedData(
        withRootObject: bridged, requiringSecureCoding: true)
      let decoded = try XCTUnwrap(
        NSKeyedUnarchiver.unarchivedObject(ofClass: NSError.self, from: archived))

      XCTAssertEqual(
        EngineXPCErrorBridge.submissionError(decoded),
        .engineFailed(report.notice))
      XCTAssertFalse(
        RecoveryAuthorizationRetryPolicy.isEligible(
          after: EngineXPCSubmissionError.engineFailed(report.notice)))
    }

    func testEngineFailureFromAnUntrustedShapeMakesNoClaims() {
      let malformed = NSError(
        domain: EngineXPCErrorBridge.engineFailureDomain,
        code: 99,
        userInfo: [
          EngineXPCErrorBridge.diskUnchangedKey: NSNumber(value: 1),
          EngineXPCErrorBridge.summaryKey: "line\u{1B}[2J\nsecond",
        ]
      )
      guard case .engineFailed(let notice) = EngineXPCErrorBridge.submissionError(malformed)
      else {
        return XCTFail("Expected engineFailed")
      }
      XCTAssertEqual(notice.reason, .unclassified)
      XCTAssertFalse(notice.diskUnchanged)
      XCTAssertEqual(notice.exitStatus, -1)
      XCTAssertEqual(notice.summary, "line[2J")
    }

    func testUnknownDomainsStillMapToHelperRejected() {
      let unknown = NSError(domain: "com.example.other", code: 7)

      XCTAssertEqual(
        EngineXPCErrorBridge.submissionError(unknown),
        .helperRejected(domain: "com.example.other", code: 7)
      )
    }

    func testBusyStillBridgesAsAGenericHelperRejection() {
      let bridged = EngineXPCErrorBridge.serviceError(
        for: ClosedEngineHelperError.busy
      )
      let busy = ClosedEngineHelperError.busy as NSError

      XCTAssertEqual(
        EngineXPCErrorBridge.submissionError(bridged),
        .helperRejected(domain: busy.domain, code: busy.code)
      )
    }
  }
#endif
