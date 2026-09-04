#if os(macOS)
  import Foundation
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  final class AuthenticatedEngineXPCSubmitterTests: XCTestCase {
    /// A service nobody registered must fail the ping within the timeout,
    /// never hang: that is the whole point of pinging before submitting.
    func testPingFailsFastForAMissingService() async throws {
      let submitter = try AuthenticatedEngineXPCSubmitter(
        machServiceName: "com.omarchy.apple-installer.test.absent",
        helperCodeSigningRequirement:
          #"identifier "com.omarchy.apple-installer.helper""#
      )
      let started = Date()
      do {
        try await submitter.ping(timeout: .seconds(3))
        XCTFail("ping to an absent service must throw")
      } catch let error as EngineXPCSubmissionError {
        XCTAssertTrue(
          [.connectionFailed, .helperUnresponsive].contains(error),
          "unexpected \(error)"
        )
      }
      XCTAssertLessThan(Date().timeIntervalSince(started), 6)
    }

    func testValidServiceAndRequirementAreAcceptedWithoutRegistration() throws {
      XCTAssertNoThrow(
        try AuthenticatedEngineXPCSubmitter(
          machServiceName: "com.omarchy.apple-installer.helper",
          helperCodeSigningRequirement:
            #"identifier "com.omarchy.apple-installer.helper""#
        )
      )
    }

    func testMalformedServiceNameIsRejected() {
      XCTAssertThrowsError(
        try AuthenticatedEngineXPCSubmitter(
          machServiceName: "../helper",
          helperCodeSigningRequirement:
            #"identifier "com.omarchy.apple-installer.helper""#
        )
      ) {
        XCTAssertEqual(
          $0 as? EngineXPCSubmissionError,
          .invalidMachServiceName
        )
      }
    }

    func testMalformedRequirementIsRejectedBeforeXPCUse() {
      XCTAssertThrowsError(
        try AuthenticatedEngineXPCSubmitter(
          machServiceName: "com.omarchy.apple-installer.helper",
          helperCodeSigningRequirement: "("
        )
      ) {
        XCTAssertEqual(
          $0 as? EngineXPCSubmissionError,
          .invalidCodeSigningRequirement
        )
      }
    }

    func testRecoveryAuthorizationFailureCrossesXPCAsTypedSafeError() {
      let serviceError = EngineXPCErrorBridge.serviceError(
        for: PinnedAsahiEngineExecutionError.recoveryAuthorizationFailed
      )

      XCTAssertEqual(
        EngineXPCErrorBridge.submissionError(serviceError),
        .recoveryAuthorizationFailed
      )
      XCTAssertTrue(serviceError.userInfo.isEmpty)
      XCTAssertTrue(
        RecoveryAuthorizationRetryPolicy.isEligible(
          after: EngineXPCSubmissionError.recoveryAuthorizationFailed
        )
      )
      XCTAssertFalse(
        RecoveryAuthorizationRetryPolicy.isEligible(
          after: EngineXPCSubmissionError.helperRejected(
            domain: "example",
            code: 1
          )
        )
      )
    }
  }
#endif
