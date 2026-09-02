#if os(macOS)
  import Foundation
  import OmarchyAppleInstallerTrustCore
  import XCTest

  @testable import OmarchyInstallerUXCore

  @MainActor
  final class InstallerSessionTests: XCTestCase {
    func testHappyPathFollowsTheTransitionTable() async throws {
      let environment = MockInstallerEnvironment()
      let session = InstallerSession(environment: environment)

      await session.inspect()
      XCTAssertEqual(session.railStep, .check)
      guard case .welcome = session.phase else {
        return XCTFail("Expected welcome, got \(session.phase)")
      }

      await session.continueToPlan()
      session.continueToPlanReview()
      guard case .planReview(_, let acknowledged) = session.phase else {
        return XCTFail("Expected planReview, got \(session.phase)")
      }
      XCTAssertFalse(acknowledged)
      XCTAssertEqual(session.railStep, .plan)

      session.setAcknowledged(true)
      session.approve()
      guard case .awaitingInstall = session.phase else {
        return XCTFail("Expected awaitingInstall, got \(session.phase)")
      }
      XCTAssertEqual(environment.approveCount, 1)
      XCTAssertEqual(session.railStep, .authorize)
      XCTAssertTrue(session.canStartInstallation)

      session.presentInstallCredentials()
      XCTAssertNotNil(session.credentialSheet.context)

      await session.submit(try authorization())
      guard case .awaitingRecovery = session.phase else {
        return XCTFail("Expected awaitingRecovery, got \(session.phase)")
      }
      XCTAssertEqual(session.railStep, .finish)
      XCTAssertTrue(session.hasExecutionStarted)
      XCTAssertEqual(environment.executeCount, 1)
      XCTAssertEqual(environment.lastOperation, .install)
      XCTAssertNil(session.credentialSheet.context)

      session.shutDown()
      XCTAssertEqual(environment.requestShutdownCount, 1)
      guard case .awaitingRecovery = session.phase else {
        return XCTFail("Expected awaitingRecovery, got \(session.phase)")
      }
      XCTAssertEqual(session.railStep, .finish)
    }

    func testBlockedHostLocksToUnsupported() async {
      let environment = MockInstallerEnvironment()
      environment.installationBlocked = true
      environment.host = MockInstallerEnvironment.blockedHost
      let session = InstallerSession(environment: environment)

      await session.inspect()

      guard case .unsupported(let failure) = session.phase else {
        return XCTFail("Expected unsupported, got \(session.phase)")
      }
      XCTAssertTrue(failure.isBlockedModel)
      XCTAssertTrue(session.installationBlocked)
      XCTAssertFalse(session.canStartInstallation)

      // Locked: nothing but re-inspection moves the phase.
      await session.continueToPlan()
      session.continueToPlanReview()
      guard case .unsupported = session.phase else {
        return XCTFail("Blocked host must stay locked")
      }
    }

    func testUnsupportedEngineExplainsItselfWithoutClaimingABlockedModel() async {
      let environment = MockInstallerEnvironment()
      environment.host = HostDisplay(
        modelName: "MacBookPro18,3",
        chipAndSpace: "Apple M1 Pro · 464 GB free",
        deviceIdentifier: "apple,j314s",
        supported: false,
        checks: [],
        helper: environment.helper,
        blockingReason: PlainLanguage.engineUnavailable
      )
      let session = InstallerSession(environment: environment)

      await session.inspect()

      guard case .unsupported(let failure) = session.phase else {
        return XCTFail("Expected unsupported, got \(session.phase)")
      }
      XCTAssertFalse(failure.isBlockedModel)
      XCTAssertEqual(failure.headline, PlainLanguage.notReadyHeadline)
      XCTAssertEqual(failure.plainDetail, PlainLanguage.engineUnavailable)
    }

    func testPreparationHoldsUntilContinue() async {
      let environment = MockInstallerEnvironment()
      let session = InstallerSession(environment: environment)
      await session.inspect()
      await session.continueToPlan()

      guard case .planPrepared(_, let update) = session.phase else {
        return XCTFail("Expected planPrepared, got \(session.phase)")
      }
      XCTAssertTrue(update.rows.allSatisfy(\.isVerified))
      XCTAssertEqual(session.railStep, .plan)
      session.approve()
      XCTAssertEqual(environment.approveCount, 0)

      session.continueToPlanReview()
      guard case .planReview(_, let acknowledged) = session.phase else {
        return XCTFail("Expected planReview, got \(session.phase)")
      }
      XCTAssertFalse(acknowledged)
    }

    func testReplanCarriesTheChosenSizeAndSkipsTheHold() async {
      let environment = MockInstallerEnvironment()
      let session = InstallerSession(environment: environment)
      await session.inspect()
      await session.continueToPlan()
      session.continueToPlanReview()

      await session.replan(omarchyBytes: 200_000_000_000)

      XCTAssertEqual(environment.lastOmarchyBytes, 200_000_000_000)
      XCTAssertEqual(environment.prepareCount, 2)
      guard case .planReview(_, let acknowledged) = session.phase else {
        return XCTFail("Expected planReview after replan, got \(session.phase)")
      }
      XCTAssertFalse(acknowledged)
    }

    func testGoBackAndRailNavigationWalkEarlierSteps() async {
      let environment = MockInstallerEnvironment()
      let session = InstallerSession(environment: environment)
      await session.inspect()
      await session.continueToPlan()
      session.continueToPlanReview()
      session.setAcknowledged(true)
      session.approve()
      guard case .awaitingInstall = session.phase else {
        return XCTFail("Expected awaitingInstall, got \(session.phase)")
      }

      session.navigate(to: .finish)
      guard case .awaitingInstall = session.phase else {
        return XCTFail("Forward navigation must be ignored")
      }

      session.goBack()
      guard case .planReview(_, let acknowledged) = session.phase, !acknowledged else {
        return XCTFail("Expected planReview after goBack, got \(session.phase)")
      }
      session.goBack()
      guard case .planPrepared = session.phase else {
        return XCTFail("Expected planPrepared after goBack, got \(session.phase)")
      }
      session.navigate(to: .check)
      guard case .welcome = session.phase else {
        return XCTFail("Expected welcome after rail navigation, got \(session.phase)")
      }
    }

    func testWholeFlowWalksForwardBackAndForwardAgain() async {
      let environment = MockInstallerEnvironment()
      let session = InstallerSession(environment: environment)
      await session.inspect()
      guard case .welcome = session.phase else { return XCTFail("welcome") }

      await session.continueToPlan()
      guard case .planPrepared = session.phase else { return XCTFail("planPrepared") }
      XCTAssertEqual(session.railStep, .plan)

      session.continueToPlanReview()
      guard case .planReview = session.phase else { return XCTFail("planReview") }

      // Choosing a size re-plans in place: the phase never leaves review and
      // the new plan carries the chosen size.
      await session.replan(omarchyBytes: 250_000_000_000)
      XCTAssertFalse(session.isReplanning)
      guard case .planReview(_, let acknowledged) = session.phase else { return XCTFail("planReview after replan") }
      XCTAssertFalse(acknowledged)
      XCTAssertEqual(environment.lastOmarchyBytes, 250_000_000_000)

      session.setAcknowledged(true)
      session.approve()
      guard case .awaitingInstall = session.phase else { return XCTFail("awaitingInstall") }
      XCTAssertEqual(session.railStep, .authorize)

      session.goBack()
      guard case .planReview(_, false) = session.phase else { return XCTFail("planReview after back") }
      session.navigate(to: .check)
      guard case .welcome = session.phase else { return XCTFail("welcome via rail") }
      XCTAssertEqual(session.railStep, .check)

      await session.continueToPlan()
      guard case .planPrepared = session.phase else { return XCTFail("planPrepared again") }
      XCTAssertEqual(environment.prepareCount, 3)
    }

    func testApproveRequiresAcknowledgement() async {
      let environment = MockInstallerEnvironment()
      let session = InstallerSession(environment: environment)
      await session.inspect()
      await session.continueToPlan()
      session.continueToPlanReview()

      session.approve()

      XCTAssertEqual(environment.approveCount, 0)
      guard case .planReview = session.phase else {
        return XCTFail("Expected to stay in planReview")
      }
    }

    func testBackDiscardsApprovalAndReturnsToReview() async {
      let environment = MockInstallerEnvironment()
      let session = InstallerSession(environment: environment)
      await session.inspect()
      await session.continueToPlan()
      session.continueToPlanReview()
      session.setAcknowledged(true)
      session.approve()

      session.back()

      XCTAssertGreaterThanOrEqual(environment.discardCount, 1)
      guard case .planReview(_, let acknowledged) = session.phase else {
        return XCTFail("Expected planReview, got \(session.phase)")
      }
      XCTAssertFalse(acknowledged)
      XCTAssertFalse(session.canStartInstallation)
    }

    func testIllegalTransitionsAreNoOps() async {
      let environment = MockInstallerEnvironment()
      let session = InstallerSession(environment: environment)

      // Before inspection completes nothing may advance.
      session.approve()
      session.setAcknowledged(true)
      session.presentInstallCredentials()
      session.refreshHelperStatus()
      await session.continueToPlan()
      session.continueToPlanReview()

      XCTAssertEqual(environment.approveCount, 0)
      XCTAssertEqual(environment.prepareCount, 0)
      guard case .inspecting = session.phase else {
        return XCTFail("Expected inspecting, got \(session.phase)")
      }
    }

    func testCredentialRejectionReopensTheSheet() async throws {
      let environment = MockInstallerEnvironment()
      environment.executeResults = [
        .failure(EngineXPCSubmissionError.machineOwnerCredentialsRejected),
        .success(MockInstallerEnvironment.recoveryCompletion),
      ]
      let session = InstallerSession(environment: environment)
      await session.inspect()
      await session.continueToPlan()
      session.continueToPlanReview()
      session.setAcknowledged(true)
      session.approve()
      session.presentInstallCredentials()

      await session.submit(try authorization())

      guard case .awaitingInstall(_, _, let sheet) = session.phase else {
        return XCTFail("Expected awaitingInstall, got \(session.phase)")
      }
      XCTAssertEqual(sheet.context?.error, .credentialsRejected)
      // The helper rejects credentials before any work starts, so the one-shot
      // latch is released for a second attempt.
      XCTAssertFalse(session.hasExecutionStarted)
      XCTAssertTrue(session.canStartInstallation)

      await session.submit(try authorization())
      guard case .awaitingRecovery = session.phase else {
        return XCTFail("Expected awaitingRecovery, got \(session.phase)")
      }
      XCTAssertEqual(environment.executeCount, 2)
    }

    func testNonCredentialFailureKeepsTheOneShotLatch() async throws {
      let environment = MockInstallerEnvironment()
      environment.executeResults = [
        .failure(EngineXPCSubmissionError.connectionFailed)
      ]
      let session = InstallerSession(environment: environment)
      await session.inspect()
      await session.continueToPlan()
      session.continueToPlanReview()
      session.setAcknowledged(true)
      session.approve()
      session.presentInstallCredentials()

      await session.submit(try authorization())

      guard case .failed(let failure) = session.phase else {
        return XCTFail("Expected failed, got \(session.phase)")
      }
      XCTAssertFalse(failure.retryRecoveryAvailable)
      XCTAssertTrue(session.hasExecutionStarted)
      XCTAssertNotNil(failure.technicalDetail)
    }

    func testRecoveryRetryIsOnlyReachableWhenEligible() async throws {
      let environment = MockInstallerEnvironment()
      environment.executeResults = [
        .failure(EngineXPCSubmissionError.recoveryAuthorizationFailed),
        .success(MockInstallerEnvironment.recoveryCompletion),
      ]
      let session = InstallerSession(environment: environment)
      await session.inspect()
      await session.continueToPlan()
      session.continueToPlanReview()
      session.setAcknowledged(true)
      session.approve()
      session.presentInstallCredentials()
      await session.submit(try authorization())

      guard case .failed(let failure) = session.phase else {
        return XCTFail("Expected failed, got \(session.phase)")
      }
      XCTAssertTrue(failure.retryRecoveryAvailable)
      XCTAssertTrue(session.canRetryRecoveryAuthorization)

      session.presentRecoveryRetryCredentials()
      XCTAssertEqual(
        session.credentialSheet.context?.kind,
        .retryRecoveryAuthorization
      )

      await session.submit(try authorization())
      XCTAssertEqual(environment.lastOperation, .retryRecoveryAuthorization)
      guard case .awaitingRecovery = session.phase else {
        return XCTFail("Expected awaitingRecovery, got \(session.phase)")
      }
    }

    func testRetrySheetStaysClosedWithoutEligibility() async throws {
      let environment = MockInstallerEnvironment()
      environment.executeResults = [
        .failure(EngineXPCSubmissionError.connectionFailed)
      ]
      let session = InstallerSession(environment: environment)
      await session.inspect()
      await session.continueToPlan()
      session.continueToPlanReview()
      session.setAcknowledged(true)
      session.approve()
      session.presentInstallCredentials()
      await session.submit(try authorization())

      session.presentRecoveryRetryCredentials()

      XCTAssertNil(session.credentialSheet.context)
      XCTAssertFalse(session.canRetryRecoveryAuthorization)
    }

    func testHelperMustBeReachableBeforeInstallationCanStart() async {
      let environment = MockInstallerEnvironment()
      environment.helper = HelperDisplay(
        status: .notInstalled,
        summary: PlainLanguage.helperSummary(.notInstalled)
      )
      let session = InstallerSession(environment: environment)
      await session.inspect()
      await session.continueToPlan()
      session.continueToPlanReview()
      session.setAcknowledged(true)
      session.approve()

      XCTAssertFalse(session.canStartInstallation)
      session.presentInstallCredentials()
      XCTAssertNil(session.credentialSheet.context)

      // The installer package installs the system daemon; refreshing picks it
      // up. There is no registration or Login Items approval step.
      environment.helper = HelperDisplay(
        status: .enabled,
        summary: PlainLanguage.helperSummary(.enabled)
      )
      session.refreshHelperStatus()
      XCTAssertTrue(session.canStartInstallation)
    }

    func testJournalChunksDriveTheInstallingDisplay() async throws {
      let environment = MockInstallerEnvironment()
      environment.journalChunks = try JournalFixture.lines()
      let session = InstallerSession(environment: environment)
      await session.inspect()
      await session.continueToPlan()
      session.continueToPlanReview()
      session.setAcknowledged(true)
      session.approve()
      session.presentInstallCredentials()

      await session.submit(try authorization())

      XCTAssertEqual(
        session.journal.checkpoints.map(\.identifier),
        [
          "apfs-target-prepared", "stub-and-esp-installed",
          "recovery-handoff-prepared",
        ]
      )
      XCTAssertFalse(session.journal.degraded)
    }

    func testDownloadProgressIsKeyedByRole() async {
      let environment = MockInstallerEnvironment()
      environment.progressUpdates = [
        AssetProgressUpdate(
          stage: .downloading,
          rows: [
            AssetProgressRow(
              role: "payload",
              fileName: "payload.zip",
              bytesCompleted: 10,
              totalBytes: 100,
              phase: .downloading
            )
          ]
        ),
        AssetProgressUpdate(
          stage: .downloading,
          rows: [
            AssetProgressRow(
              role: "payload",
              fileName: "payload.zip",
              bytesCompleted: 100,
              totalBytes: 100,
              phase: .verified
            ),
            AssetProgressRow(
              role: "engine",
              fileName: "engine.tar.gz",
              bytesCompleted: 5,
              totalBytes: 20,
              phase: .downloading
            ),
          ]
        ),
      ]
      let session = InstallerSession(environment: environment)
      await session.inspect()
      await session.continueToPlan()
      session.continueToPlanReview()

      XCTAssertEqual(session.stagingProgress["payload"]?.phase, .verified)
      XCTAssertEqual(session.stagingProgress["payload"]?.bytesCompleted, 100)
      XCTAssertEqual(session.stagingProgress["engine"]?.bytesCompleted, 5)
    }

    func testReInspectionResetsApprovalAndLatches() async throws {
      let environment = MockInstallerEnvironment()
      environment.executeResults = [
        .failure(EngineXPCSubmissionError.recoveryAuthorizationFailed)
      ]
      let session = InstallerSession(environment: environment)
      await session.inspect()
      await session.continueToPlan()
      session.continueToPlanReview()
      session.setAcknowledged(true)
      session.approve()
      session.presentInstallCredentials()
      await session.submit(try authorization())
      XCTAssertTrue(session.hasExecutionStarted)
      XCTAssertTrue(session.recoveryRetryAvailable)

      let discardsBefore = environment.discardCount
      await session.inspect()

      XCTAssertFalse(session.hasExecutionStarted)
      XCTAssertFalse(session.recoveryRetryAvailable)
      XCTAssertTrue(session.stagingProgress.isEmpty)
      XCTAssertTrue(session.journal.raw.isEmpty)
      XCTAssertNil(session.credentialSheet.context)
      XCTAssertGreaterThan(environment.discardCount, discardsBefore)
      guard case .welcome = session.phase else {
        return XCTFail("Expected welcome, got \(session.phase)")
      }
    }

    func testPreparationFailureSurfacesTechnicalDetail() async {
      let environment = MockInstallerEnvironment()
      environment.prepareError =
        InstallerReleaseConfigurationError
        .releaseResourcesUnavailable
      let session = InstallerSession(environment: environment)
      await session.inspect()

      await session.continueToPlan()
      session.continueToPlanReview()

      guard case .failed(let failure) = session.phase else {
        return XCTFail("Expected failed, got \(session.phase)")
      }
      XCTAssertEqual(failure.plainDetail, PlainLanguage.releaseResourcesUnavailable)
      XCTAssertNotNil(failure.technicalDetail)
    }

    private func authorization() throws -> MachineOwnerAuthorization {
      try MachineOwnerAuthorization(
        username: "owner",
        password: Data("secret".utf8)
      )
    }

    // MARK: Existing-install choice

    func testExistingInstallChoicePausesBeforePlanReview() async {
      let environment = MockInstallerEnvironment()
      let install = ExistingInstallDisplay(
        sourceIdentifier: "disk0s3",
        sizeDescription: "128 GB"
      )
      environment.existingInstalls = [install]
      let session = InstallerSession(environment: environment)
      await session.inspect()

      await session.continueToPlan()
      session.continueToPlanReview()

      guard case .existingInstallChoice(let options, let host) = session.phase
      else {
        return XCTFail("Expected existingInstallChoice, got \(session.phase)")
      }
      XCTAssertEqual(options, [install])
      XCTAssertEqual(host, MockInstallerEnvironment.supportedHost)
      XCTAssertEqual(session.railStep, .plan)
      XCTAssertEqual(environment.lastSelection, .automatic)

      await session.chooseReplaceExistingInstall(install)
      session.continueToPlanReview()

      guard case .planReview = session.phase else {
        return XCTFail("Expected planReview, got \(session.phase)")
      }
      XCTAssertEqual(
        environment.lastSelection,
        .replaceExisting(sourceIdentifier: "disk0s3")
      )
      XCTAssertEqual(environment.prepareCount, 2)
    }

    func testKeepingTheExistingInstallPlansAlongside() async {
      let environment = MockInstallerEnvironment()
      environment.existingInstalls = [
        ExistingInstallDisplay(
          sourceIdentifier: "disk0s3",
          sizeDescription: "128 GB"
        )
      ]
      let session = InstallerSession(environment: environment)
      await session.inspect()
      await session.continueToPlan()
      session.continueToPlanReview()

      await session.chooseInstallAlongsideExistingInstall()
      session.continueToPlanReview()

      guard case .planReview = session.phase else {
        return XCTFail("Expected planReview, got \(session.phase)")
      }
      XCTAssertEqual(environment.lastSelection, .installAlongside)
    }

    func testCancellingTheExistingInstallChoiceReturnsToWelcome() async {
      let environment = MockInstallerEnvironment()
      environment.existingInstalls = [
        ExistingInstallDisplay(
          sourceIdentifier: "disk0s3",
          sizeDescription: "128 GB"
        )
      ]
      let session = InstallerSession(environment: environment)
      await session.inspect()
      await session.continueToPlan()
      session.continueToPlanReview()

      session.cancelExistingInstallChoice()

      guard case .welcome(let host) = session.phase else {
        return XCTFail("Expected welcome, got \(session.phase)")
      }
      XCTAssertEqual(host, MockInstallerEnvironment.supportedHost)
    }

    func testForeignReplaceOptionIsARefusedNoOp() async {
      let environment = MockInstallerEnvironment()
      let surfaced = ExistingInstallDisplay(
        sourceIdentifier: "disk0s3",
        sizeDescription: "128 GB"
      )
      environment.existingInstalls = [surfaced]
      let session = InstallerSession(environment: environment)
      await session.inspect()
      await session.continueToPlan()
      session.continueToPlanReview()
      let prepared = environment.prepareCount

      await session.chooseReplaceExistingInstall(
        ExistingInstallDisplay(
          sourceIdentifier: "disk0s9",
          sizeDescription: "1 GB"
        )
      )

      guard case .existingInstallChoice = session.phase else {
        return XCTFail("Expected existingInstallChoice, got \(session.phase)")
      }
      XCTAssertEqual(environment.prepareCount, prepared)
    }

    func testChoiceMethodsAreNoOpsOutsideTheirPhase() async {
      let environment = MockInstallerEnvironment()
      let session = InstallerSession(environment: environment)
      await session.inspect()

      await session.chooseReplaceExistingInstall(
        ExistingInstallDisplay(
          sourceIdentifier: "disk0s3",
          sizeDescription: "128 GB"
        )
      )
      await session.chooseInstallAlongsideExistingInstall()
      session.continueToPlanReview()
      session.cancelExistingInstallChoice()

      guard case .welcome = session.phase else {
        return XCTFail("Expected welcome, got \(session.phase)")
      }
      XCTAssertEqual(environment.prepareCount, 0)
    }
  }

  final class MockInstallerEnvironment: InstallerEnvironment, @unchecked Sendable {
    var host = MockInstallerEnvironment.supportedHost
    var plan = MockInstallerEnvironment.samplePlan
    var helper = HelperDisplay(
      status: .enabled,
      summary: PlainLanguage.helperSummary(.enabled)
    )
    var installationBlocked = false
    var engineSupported = true
    var requestShutdownCount = 0
    var inspectError: (any Error)?
    var prepareError: (any Error)?
    var approveError: (any Error)?
    var executeResults = [Result<CompletionDisplay, any Error>]()
    var journalChunks = [Data]()
    var progressUpdates = [AssetProgressUpdate]()
    var existingInstalls = [ExistingInstallDisplay]()

    private(set) var approveCount = 0
    private(set) var discardCount = 0
    private(set) var executeCount = 0
    private(set) var prepareCount = 0
    private(set) var lastOperation: InstallOperationKind?
    private(set) var lastSelection: InstallTargetSelection?
    private var approved = false

    var hasApprovedPlan: Bool { approved }
    var helperStatus: HelperDisplay { helper }

    func inspect() async throws -> HostDisplay {
      approved = false
      if let inspectError {
        throw inspectError
      }
      return host
    }

    var lastOmarchyBytes: UInt64?

    func preparePlan(
      selection: InstallTargetSelection,
      omarchyBytes: UInt64?,
      progress: @escaping @Sendable (AssetProgressUpdate) -> Void
    ) async throws -> PlanPreparationDisplay {
      prepareCount += 1
      lastSelection = selection
      lastOmarchyBytes = omarchyBytes
      approved = false
      for update in progressUpdates {
        progress(update)
        await Task.yield()
      }
      if let prepareError {
        throw prepareError
      }
      if case .automatic = selection, !existingInstalls.isEmpty {
        return .existingInstallChoice(existingInstalls)
      }
      return .plan(plan)
    }

    func approve() throws {
      if let approveError {
        throw approveError
      }
      approveCount += 1
      approved = true
    }

    func discardApproval() {
      discardCount += 1
      approved = false
    }

    func refreshHelperStatus() -> HelperDisplay { helper }

    func requestShutdown() -> Bool {
      requestShutdownCount += 1
      return false
    }

    func execute(
      operation: InstallOperationKind,
      authorization: MachineOwnerAuthorization,
      journal: @escaping @Sendable (Data) -> Void
    ) async throws -> CompletionDisplay {
      executeCount += 1
      lastOperation = operation
      for chunk in journalChunks {
        journal(chunk)
        await Task.yield()
      }
      // Give the session's main-actor hops a chance to land.
      try? await Task.sleep(for: .milliseconds(20))
      if executeResults.isEmpty {
        return Self.recoveryCompletion
      }
      return try executeResults.removeFirst().get()
    }

    static let supportedHost = HostDisplay(
      modelName: "MacBookPro18,3",
      chipAndSpace: "Apple M1 Pro · 464 GB free",
      deviceIdentifier: "apple,j314s",
      supported: true,
      checks: [],
      helper: HelperDisplay(
        status: .enabled,
        summary: PlainLanguage.helperSummary(.enabled)
      )
    )

    static let blockedHost = HostDisplay(
      modelName: "MacBookPro16,1",
      chipAndSpace: "Apple M4 · apple,j614s",
      deviceIdentifier: "apple,j614s",
      supported: false,
      checks: [],
      helper: HelperDisplay(
        status: .notInstalled,
        summary: PlainLanguage.helperSummary(.notInstalled)
      )
    )

    static let samplePlan = PlanDisplay(
      headline: "137 GB for Omarchy",
      subheadline: PlainLanguage.planSubheadline,
      diskTotalBytes: 994_662_584_320,
      omarchyBytes: 137_438_953_472,
      macOSBytes: 857_223_630_848,
      bindingDigest: "sha256:" + String(repeating: "b", count: 64),
      planDigest: String(repeating: "c", count: 64),
      artifacts: [],
      facts: []
    )

    static let recoveryCompletion = CompletionDisplay(
      nextAction: .enterRecovery,
      headline: PlainLanguage.recoveryHeadline,
      subheadline: PlainLanguage.recoverySubheadline,
      verified: PlainLanguage.doneVerifiedRows,
      handoff: HandoffDisplay(
        headline: PlainLanguage.recoveryHeadline,
        subheadline: PlainLanguage.recoverySubheadline,
        steps: PlainLanguage.recoverySteps(for: [
          "enterOneTrueRecovery", "authenticateMachineOwner",
        ]),
        explainer: PlainLanguage.recoveryExplainer,
        hint: PlainLanguage.recoveryHint
      )
    )
  }
#endif
