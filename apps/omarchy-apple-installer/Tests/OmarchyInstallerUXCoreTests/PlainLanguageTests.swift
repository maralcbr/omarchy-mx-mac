#if os(macOS)
  import Foundation
  import OmarchyAppleInstallerTrustCore
  import XCTest

  @testable import OmarchyInstallerUXCore

  final class PlainLanguageTests: XCTestCase {
    func testEveryPhaseHasADistinctTitle() {
      let phases = [
        "preflight", "existing_removal", "apfs_preparation", "stub_and_esp",
        "awaiting_recovery", "boot_policy", "media_handoff", "omarchy_install",
      ]
      let titles = phases.map { PlainLanguage.installPhaseTitle(forPhase: $0) }

      XCTAssertEqual(Set(titles).count, phases.count)
      XCTAssertTrue(titles.allSatisfy { !$0.isEmpty })
      XCTAssertEqual(
        PlainLanguage.installPhaseTitle(forPhase: nil),
        PlainLanguage.installVerifyingOwner
      )
    }

    func testEveryStartedEventHasATitle() {
      for event in [
        "existing_removal_started", "apfs_preparation_started",
        "stub_and_esp_started", "recovery_handoff_started",
      ] {
        XCTAssertNotNil(PlainLanguage.installPhaseTitle(forEvent: event))
        XCTAssertFalse(PlainLanguage.eventSummary(event).isEmpty)
      }
      XCTAssertNil(PlainLanguage.installPhaseTitle(forEvent: "unknown_event"))
      XCTAssertEqual(PlainLanguage.eventSummary("odd_name"), "odd name")
    }

    func testEveryCheckpointHasAPlainSummary() {
      let identifiers = [
        "existing-install-removed", "apfs-target-prepared",
        "stub-and-esp-installed", "recovery-handoff-prepared",
      ]
      let summaries = identifiers.map(PlainLanguage.checkpointSummary)

      XCTAssertEqual(Set(summaries).count, identifiers.count)
      XCTAssertTrue(summaries.allSatisfy { !$0.isEmpty })
      XCTAssertEqual(PlainLanguage.checkpointSummary("unknown"), "unknown")
    }

    func testEveryNextActionHasAMessage() {
      let actions: [InstallerNextAction] = [
        .continueInstallation, .enterRecovery, .attachInstallationMedia,
        .verifyInstalledSystem, .manualRecovery,
      ]
      let messages = actions.map(PlainLanguage.nextActionMessage)

      XCTAssertEqual(Set(messages).count, actions.count)
      XCTAssertTrue(messages.allSatisfy { !$0.isEmpty })
    }

    func testRecoveryStepsCoverSignedTokensAndUnknowns() {
      let steps = PlainLanguage.recoverySteps(for: [
        "enterOneTrueRecovery", "authenticateMachineOwner",
      ])
      XCTAssertEqual(steps.count, 3)
      XCTAssertEqual(steps.map(\.number), [1, 2, 3])

      let unknown = PlainLanguage.recoverySteps(for: ["somethingNew"])
      XCTAssertEqual(unknown.count, 1)
      XCTAssertEqual(unknown.first?.title, "somethingNew")

      XCTAssertEqual(PlainLanguage.recoverySteps(for: []).count, 3)
    }

    func testKnownErrorsMapToDistinctHeadlinesAndKeepTechnicalDetail() {
      let errors: [any Error] = [
        EngineXPCSubmissionError.machineOwnerCredentialsRejected,
        EngineXPCSubmissionError.connectionFailed,
        EngineXPCSubmissionError.recoveryAuthorizationFailed,
        ClosedEngineHelperError.busy,
        ClosedEngineHelperError.unsupportedDevice("apple,j614s"),
        InstallerPlanPreparationError.inventoryUnavailable,
        ArtifactStageError.digestMismatch(expected: "a", actual: "b"),
        InstallerReleaseConfigurationError.releaseResourcesUnavailable,
        SupportCatalogError.expired,
        InstallerAppErrorStub.unknown,
      ]

      var headlines = Set<String>()
      for error in errors {
        let failure = PlainLanguage.failure(for: error)
        XCTAssertFalse(failure.headline.isEmpty)
        XCTAssertFalse(failure.plainDetail.isEmpty)
        XCTAssertEqual(failure.technicalDetail, String(describing: error))
        headlines.insert(failure.headline)
      }
      XCTAssertGreaterThanOrEqual(headlines.count, 8)
    }

    func testRetryEligibleFailureIsFlaggedAndExplained() {
      let failure = PlainLanguage.failure(
        for: EngineXPCSubmissionError.recoveryAuthorizationFailed,
        retryRecoveryAvailable: true
      )

      XCTAssertTrue(failure.retryRecoveryAvailable)
      XCTAssertEqual(failure.headline, "Recovery authorization didn’t complete")
      XCTAssertNotNil(failure.remedy)
      XCTAssertNotNil(failure.technicalDetail)
    }

    func testBlockedDeviceIsFlaggedAsBlockedModel() {
      let failure = PlainLanguage.failure(
        for: ClosedEngineHelperError.unsupportedDevice("apple,j614s")
      )

      XCTAssertTrue(failure.isBlockedModel)
      XCTAssertEqual(failure.headline, PlainLanguage.blockedHeadline)
    }

    func testHelperSummariesAreDistinct() {
      let statuses: [InstallerHelperServiceStatus] = [.enabled, .notInstalled]
      let summaries = statuses.map(PlainLanguage.helperSummary)

      XCTAssertEqual(Set(summaries).count, statuses.count)
    }

    func testDigestShorteningKeepsBothEnds() {
      let digest = "sha256:" + String(repeating: "a", count: 56) + "beefcafe"

      let short = PlainLanguage.shortDigest(digest)

      XCTAssertTrue(short.hasPrefix("aaaaaaaa"))
      XCTAssertTrue(short.hasSuffix("beefcafe"))
      XCTAssertTrue(short.contains("…"))
      XCTAssertEqual(PlainLanguage.shortDigest("short"), "short")
    }

    func testByteFormattingIsHumanAndExact() {
      XCTAssertFalse(PlainLanguage.bytes(137_438_953_472).isEmpty)
      XCTAssertTrue(
        PlainLanguage.exactBytes(857_747_943_424).hasSuffix("bytes")
      )
      XCTAssertTrue(
        PlainLanguage.exactBytes(1_000).contains("1,000")
          || PlainLanguage.exactBytes(1_000).contains("1 000")
      )
    }
  }

  private enum InstallerAppErrorStub: Error {
    case unknown
  }
#endif
