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
