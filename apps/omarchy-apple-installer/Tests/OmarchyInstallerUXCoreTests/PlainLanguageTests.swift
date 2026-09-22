#if os(macOS)
  import Foundation
  import OmarchyAppleInstallerTrustCore
  import XCTest

  @testable import OmarchyInstallerUXCore

  final class PlainLanguageTests: XCTestCase {
    func testChannelBadgesDistinguishStableAndRC() {
      XCTAssertEqual(PlainLanguage.badge(for: .stable), "Stable")
      XCTAssertEqual(PlainLanguage.badge(for: .rc), "Release candidate")
    }

    func testAllocationNoticeIgnoresByteAlignmentAtDisplayedPrecision() {
      XCTAssertNil(
        PlainLanguage.allocationNotice(
          requestedBytes: 180_000_000_000, actualBytes: 179_999_604_736))
      XCTAssertNil(
        PlainLanguage.allocationNotice(
          requestedBytes: 180_000_000_000, actualBytes: 180_000_000_000))
    }

    func testAllocationNoticeDescribesActualChangeWithoutClaimingDiskIsFull() {
      XCTAssertEqual(
        PlainLanguage.allocationNotice(
          requestedBytes: 650_000_000_000, actualBytes: 137_438_953_472),
        "Space for Omarchy changed from 650 GB to 137 GB. Review the updated size before installing."
      )
      XCTAssertEqual(
        PlainLanguage.allocationNotice(requestedBytes: 70_000_000_000, actualBytes: 80_000_000_000),
        "Space for Omarchy changed from 70 GB to 80 GB. Review the updated size before installing.")
    }

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
      XCTAssertEqual(
        PlainLanguage.eventSummary("odd_name"), "Additional installation activity (odd_name)")
    }

    func testEveryCheckpointHasAPlainSummary() {
      let identifiers = [
        "existing-install-removed", "apfs-target-prepared",
        "stub-and-esp-installed", "recovery-handoff-prepared",
      ]
      let summaries = identifiers.map(PlainLanguage.checkpointSummary)

      XCTAssertEqual(Set(summaries).count, identifiers.count)
      XCTAssertTrue(summaries.allSatisfy { !$0.isEmpty })
      XCTAssertEqual(
        PlainLanguage.checkpointSummary("unknown"), "Additional installation activity (unknown)")
    }

    func testEveryNextActionHasAMessage() {
      let actions: [InstallerNextAction] = [
        .continueInstallation, .enterRecovery, .attachInstallationMedia,
        .verifyInstalledSystem, .manualRecovery,
      ]
      let messages = actions.map { PlainLanguage.nextActionMessage($0) }

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
      XCTAssertEqual(
        unknown.first?.title,
        "Unsupported Recovery instruction: somethingNew. Save the installation record and get support before continuing."
      )

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
        InstallerAssetPreparationError.hostBlocked("not enabled"),
        InstallerAssetPreparationError.unsupportedDevice("apple,j614s"),
        InstallerAssetPreparationError.deliveryMetadataUnavailable,
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

    func testAnOutdatedInstallerOffersTheDownloadItNeeds() {
      let url = URL(
        string: "https://downloads.example.com/installer/stable/Installer.pkg"
      )!
      let failure = PlainLanguage.failure(
        for: InstallerAssetPreparationError.installerOutdated(
          current: InstallerVersion("1.9.9")!,
          minimum: InstallerVersion("2.0.0")!,
          downloadURL: url
        )
      )

      XCTAssertEqual(failure.headline, "This installer is out of date")
      XCTAssertTrue(failure.plainDetail.contains("2.0.0"))
      XCTAssertTrue(failure.plainDetail.contains("1.9.9"))
      XCTAssertTrue(failure.plainDetail.contains("requires installer"))
      XCTAssertEqual(failure.actionURL, url)
      XCTAssertEqual(failure.actionTitle, PlainLanguage.downloadInstaller)
      XCTAssertFalse(failure.retryRecoveryAvailable)
    }

    func testFailuresWithoutAnActionCarryNoLink() {
      let failure = PlainLanguage.failure(for: SupportCatalogError.expired)

      XCTAssertNil(failure.actionURL)
      XCTAssertNil(failure.actionTitle)
    }

    func testConfirmedSnapshotConstraintsOfferAppleGuidanceWithoutRecoveryAuthorization() {
      for constraint: APFSSnapshotConstraint in [.timeMachine, .other] {
        let failure = PlainLanguage.failure(
          for: InstallerAllocationRecommendationError.snapshotConstrained(constraint)
        )

        XCTAssertEqual(
          failure.actionURL,
          URL(string: "https://support.apple.com/en-us/102154")
        )
        XCTAssertFalse(failure.retryRecoveryAvailable)
        XCTAssertFalse(failure.isBlockedModel)
      }
    }

    func testUnconfirmedAllocationFailureDoesNotOfferSnapshotCleanupAsTheFix() {
      let failure = PlainLanguage.failure(
        for: InstallerAllocationRecommendationError.noEligibleCandidate
      )

      XCTAssertNil(failure.actionURL)
      XCTAssertFalse(failure.retryRecoveryAvailable)
    }

    func testAnEmptyChannelSaysSoInsteadOfShowingAStatusCode() {
      let failure = PlainLanguage.failure(
        for: InstallerReleaseConfigurationError.unexpectedHTTPStatus(404)
      )

      XCTAssertEqual(failure.headline, "No release is available on this channel")
      XCTAssertTrue(failure.plainDetail.contains("No downloadable release"))
      XCTAssertFalse(failure.plainDetail.contains("404"))
      XCTAssertFalse(failure.headline.contains("404"))
      XCTAssertEqual(
        failure.technicalDetail,
        String(describing: InstallerReleaseConfigurationError.unexpectedHTTPStatus(404))
      )
      XCTAssertTrue(try XCTUnwrap(failure.remedy).contains("release channel"))
    }

    func testOtherServerFailuresAreDistinctFromAnEmptyChannel() {
      let failure = PlainLanguage.failure(
        for: InstallerReleaseConfigurationError.unexpectedHTTPStatus(503)
      )

      XCTAssertEqual(failure.headline, "The release server returned an error")
      XCTAssertFalse(failure.plainDetail.contains("503"))
    }

    func testAnUnreadableReleaseIsExplainedPlainly() {
      let failure = PlainLanguage.failure(
        for: InstallerReleaseConfigurationError.invalidCatalogEnvelope
      )

      XCTAssertEqual(failure.headline, "The release couldn’t be verified")
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

    func testDigestShorteningKeepsBothEnds() {
      let digest = "sha256:" + String(repeating: "a", count: 56) + "beefcafe"

      let short = PlainLanguage.shortDigest(digest)

      XCTAssertTrue(short.hasPrefix("aaaaaaaa"))
      XCTAssertTrue(short.hasSuffix("beefcafe"))
      XCTAssertTrue(short.contains("…"))
      XCTAssertEqual(PlainLanguage.shortDigest("short"), "short")
    }

    func testByteFormattingIsWholeNumbers() {
      XCTAssertEqual(PlainLanguage.bytes(137_438_953_472), "137 GB")
      XCTAssertEqual(PlainLanguage.bytes(18_400_000), "18 MB")
      XCTAssertEqual(PlainLanguage.bytes(512), "512 bytes")
    }

    func testEncryptionCopyNamesTheCheckboxAndDefaultOnFailure() {
      XCTAssertEqual(
        PlainLanguage.encryptLinuxDiskTitle, "Encrypt this Mac's Linux disk")
      XCTAssertEqual(
        PlainLanguage.encryptLinuxDiskPassword,
        "The Linux login password you set at first boot unlocks the disk after setup.")
      XCTAssertFalse(PlainLanguage.encryptLinuxDiskPassword.lowercased().contains("macos"))
      XCTAssertEqual(
        PlainLanguage.encryptionChoiceNotRecorded,
        "Encryption choice not recorded: first boot will encrypt")
      XCTAssertTrue(
        PlainLanguage.nextActionMessage(.enterRecovery, installConf: .notRecorded)
          .contains(PlainLanguage.encryptionChoiceNotRecorded))
      XCTAssertEqual(
        PlainLanguage.installConfWarning(.unconfirmed(encrypt: false)),
        PlainLanguage.encryptionOptOutRecorded)
      XCTAssertFalse(
        PlainLanguage.nextActionMessage(.enterRecovery, installConf: .unconfirmed(encrypt: false))
          .contains(PlainLanguage.encryptionChoiceNotRecorded))
      XCTAssertTrue(
        PlainLanguage.nextActionMessage(.enterRecovery, installConf: .unconfirmed(encrypt: false))
          .contains(PlainLanguage.encryptionOptOutRecorded))
    }

    func testCopyAuditOmitsAsahiExceptTheInstallerEngine() throws {
      let tests = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
      let roots = [
        tests.appendingPathComponent("Sources/OmarchyInstallerUXCore"),
        tests.appendingPathComponent("Sources/OmarchyAppleInstallerApp"),
      ]
      var offenders = [String]()
      for root in roots {
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
          guard file.pathExtension == "swift" else { continue }
          let text = try String(contentsOf: file, encoding: .utf8)
          for snippet in swiftStringLiterals(in: text) {
            guard snippet.localizedCaseInsensitiveContains("asahi") else { continue }
            if snippet.localizedCaseInsensitiveContains("Asahi installer") {
              continue
            }
            offenders.append("\(file.lastPathComponent): \(snippet)")
          }
        }
      }
      XCTAssertTrue(offenders.isEmpty, offenders.joined(separator: "\n"))
    }

    private func swiftStringLiterals(in text: String) -> [String] {
      var literals = [String]()
      var index = text.startIndex
      while index < text.endIndex {
        if text[index] == "\"" {
          let start = index
          index = text.index(after: index)
          var escaped = false
          while index < text.endIndex {
            let character = text[index]
            if escaped {
              escaped = false
            } else if character == "\\" {
              escaped = true
            } else if character == "\"" {
              literals.append(String(text[start...index]))
              index = text.index(after: index)
              break
            }
            index = text.index(after: index)
          }
          continue
        }
        index = text.index(after: index)
      }
      return literals
    }
  }

  private enum InstallerAppErrorStub: Error {
    case unknown
  }
#endif
