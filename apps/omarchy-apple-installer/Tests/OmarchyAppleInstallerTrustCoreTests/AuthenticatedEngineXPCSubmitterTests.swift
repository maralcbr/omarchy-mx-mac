#if os(macOS)
  import Foundation
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  final class AuthenticatedEngineXPCSubmitterTests: XCTestCase {
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
