#if os(macOS)
  import Foundation
  import XCTest

  @testable import OmarchyInstallerUXCore

  /// Proves the preview mode compiles out: the same assertions run in debug and
  /// release configurations with opposite expectations.
  final class InstallerPreviewSelectionTests: XCTestCase {
    func testScenarioSelectionFollowsBuildConfiguration() {
      let environment = [
        InstallerPreviewSelection.environmentKey: "fresh-install",
        InstallerPreviewSelection.journalEnvironmentKey: "/tmp/journal.jsonl",
      ]

      let scenario = InstallerPreviewSelection.scenario(from: environment)
      let journal = InstallerPreviewSelection.journalURL(from: environment)

      #if DEBUG
        XCTAssertEqual(scenario, .freshInstall)
        XCTAssertEqual(journal?.path, "/tmp/journal.jsonl")
      #else
        XCTAssertNil(scenario)
        XCTAssertNil(journal)
      #endif
    }

    func testExistingInstallScenarioIsSelectable() {
      let scenario = InstallerPreviewSelection.scenario(
        from: [InstallerPreviewSelection.environmentKey: "existing-install"]
      )
      #if DEBUG
        XCTAssertEqual(scenario, .existingInstall)
      #else
        XCTAssertNil(scenario)
      #endif
    }

    func testEmptyOrUnknownValuesSelectNothing() {
      XCTAssertNil(InstallerPreviewSelection.scenario(from: [:]))
      XCTAssertNil(
        InstallerPreviewSelection.scenario(
          from: [InstallerPreviewSelection.environmentKey: ""]
        )
      )
      XCTAssertNil(
        InstallerPreviewSelection.scenario(
          from: [InstallerPreviewSelection.environmentKey: "not-a-scenario"]
        )
      )
    }

    func testEveryScenarioHasAStableRawValue() {
      XCTAssertEqual(
        Set(InstallerPreviewScenario.allCases.map(\.rawValue)),
        [
          "fresh-install", "existing-install", "unsupported",
          "credential-reject", "recovery-retry", "degraded-journal",
        ]
      )
    }
  }
#endif
