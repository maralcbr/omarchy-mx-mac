#if os(macOS)
  import Foundation
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  final class MacHostInspectionTests: XCTestCase {
    func testSupportedM1InspectionRemainsCatalogGated() throws {
      let inspector = makeInspector(target: "J314s")

      let result = try inspector.inspect()

      XCTAssertEqual(result.identity.model, "MacBookPro18,3")
      XCTAssertEqual(result.identity.chip, "Apple M1 Pro")
      XCTAssertEqual(result.identity.deviceIdentifier, "apple,j314s")
      XCTAssertEqual(result.eligibility, .requiresSignedCatalog)
      XCTAssertEqual(result.macOSVersion, "Version 15.6 (Build 24G84)")
      XCTAssertEqual(result.powerSource, .ac)
      XCTAssertTrue(result.fileVaultEnabled)
      XCTAssertEqual(result.storage.containerIdentifier, "disk3")
      XCTAssertEqual(result.storage.physicalStoreIdentifier, "disk0s2")
      XCTAssertEqual(result.storage.shrinkableBytes, 400)
    }

    func testM4InspectionIsBlockedBeforeCatalogOrAuthorization() throws {
      let inspector = makeInspector(
        model: "Mac16,8",
        chip: "Apple M4 Pro",
        target: "J614s"
      )

      let result = try inspector.inspect()

      XCTAssertEqual(result.identity.deviceIdentifier, "apple,j614s")
      XCTAssertEqual(
        result.eligibility,
        .blocked(
          reason: "This installer doesn’t support this Mac model yet."
        )
      )
    }

    func testUnsafeContainerIdentifierStopsBeforeLimitsQuery() {
      let commands = FixtureReadOnlyCommandRunner(
        root: propertyList([
          "APFSContainerReference": "disk3;eraseDisk"
        ]),
        limits: Data(),
        power: Data("Now drawing from 'AC Power'\n".utf8)
      )
      let inspector = AppleSiliconHostInspector(
        hardware: FixtureHardwarePropertyReader(values: [
          "hw.model": "MacBookPro18,3",
          "machdep.cpu.brand_string": "Apple M1 Pro",
          "hw.targettype": "J314s",
        ]),
        commands: commands,
        operatingSystem: FixtureOperatingSystemVersionReader()
      )

      XCTAssertThrowsError(try inspector.inspect()) {
        XCTAssertEqual(
          $0 as? AppleSiliconHostInspectionError,
          .unsafeContainerIdentifier("disk3;eraseDisk")
        )
      }
    }

    func testInvalidTargetTypeFailsClosed() {
      let inspector = makeInspector(target: "J314s;touch")

      XCTAssertThrowsError(try inspector.inspect()) {
        XCTAssertEqual(
          $0 as? AppleSiliconHostInspectionError,
          .invalidHardwareProperty("hw.targettype")
        )
      }
    }

    func testLiveInspectionIsReadOnlyAndReturnsCoherentHostState() throws {
      let result = try AppleSiliconHostInspector().inspect()

      XCTAssertTrue(result.identity.model.hasPrefix("Mac"))
      XCTAssertTrue(result.identity.chip.hasPrefix("Apple M"))
      XCTAssertTrue(result.identity.deviceIdentifier.hasPrefix("apple,j"))
      XCTAssertFalse(result.macOSVersion.isEmpty)
      XCTAssertTrue(result.storage.isInternal)
      XCTAssertGreaterThan(result.storage.containerSizeBytes, 0)
      XCTAssertLessThanOrEqual(
        result.storage.minimumPreferredSizeBytes,
        result.storage.containerSizeBytes
      )
    }

    private func makeInspector(
      model: String = "MacBookPro18,3",
      chip: String = "Apple M1 Pro",
      target: String
    ) -> AppleSiliconHostInspector {
      AppleSiliconHostInspector(
        hardware: FixtureHardwarePropertyReader(values: [
          "hw.model": model,
          "machdep.cpu.brand_string": chip,
          "hw.targettype": target,
        ]),
        commands: FixtureReadOnlyCommandRunner(
          root: propertyList([
            "APFSContainerReference": "disk3",
            "APFSPhysicalStores": [["APFSPhysicalStore": "disk0s2"]],
            "APFSContainerSize": 1_000,
            "APFSContainerFree": 500,
            "Internal": true,
            "FileVault": true,
          ]),
          limits: propertyList(["MinimumSizePreferred": 600]),
          power: Data("Now drawing from 'AC Power'\n".utf8)
        ),
        operatingSystem: FixtureOperatingSystemVersionReader()
      )
    }
  }

  final class APFSSnapshotInspectorTests: XCTestCase {
    func testLimitingTimeMachineSnapshotSurvivesAnotherVolumeQueryFailure() {
      let commands = snapshotRunner(
        volumes: ["disk9s1", "disk9s5"],
        snapshots: [
          "disk9s5": propertyList([
            "Snapshots": [
              [
                "SnapshotName": "com.apple.TimeMachine.2000-01-01-000000.local",
                "LimitingContainerShrink": true,
                "Purgeable": true,
              ]
            ]
          ])
        ]
      )

      XCTAssertEqual(
        APFSSnapshotInspector(commands: commands).constraint(in: storage()),
        .timeMachine
      )
    }

    func testSystemConstraintDoesNotBlameUnrelatedTimeMachineSnapshot() {
      let commands = snapshotRunner(snapshots: [
        "disk9s5": propertyList([
          "Snapshots": [
            [
              "SnapshotName": "com.apple.TimeMachine.2000-01-01-000000.local",
              "LimitingContainerShrink": false,
            ],
            [
              "SnapshotName": "com.apple.os.update-synthetic",
              "LimitingContainerShrink": true,
            ],
          ]
        ])
      ])

      XCTAssertEqual(
        APFSSnapshotInspector(commands: commands).constraint(in: storage()),
        .other
      )
    }

    func testSnapshotPresenceOrMalformedLimitFlagDoesNotProveAConstraint() {
      let commands = snapshotRunner(snapshots: [
        "disk9s5": propertyList([
          "Snapshots": [
            ["SnapshotName": "com.apple.TimeMachine.2000-01-01-000000.local"],
            [
              "SnapshotName": "com.apple.TimeMachine.2000-01-02-000000.local",
              "LimitingContainerShrink": 1,
            ],
            [
              "SnapshotName": "com.apple.TimeMachine.2000-01-03-000000.local",
              "LimitingContainerShrink": "true",
            ],
          ]
        ])
      ])

      XCTAssertNil(APFSSnapshotInspector(commands: commands).constraint(in: storage()))
    }

    func testLimitingSnapshotWithUnknownNameUsesGeneralDiagnosis() {
      let commands = snapshotRunner(snapshots: [
        "disk9s5": propertyList([
          "Snapshots": [
            [
              "SnapshotName": "com.apple.TimeMachine.synthetic.backup",
              "LimitingContainerShrink": true,
            ]
          ]
        ])
      ])

      XCTAssertEqual(
        APFSSnapshotInspector(commands: commands).constraint(in: storage()),
        .other
      )
    }

    func testFailedOrUnsupportedQueriesLeaveDiagnosisUnknown() {
      let runners = [
        SnapshotCommandRunner(volumes: nil, snapshots: [:]),
        SnapshotCommandRunner(volumes: Data("unsupported".utf8), snapshots: [:]),
        snapshotRunner(snapshots: [:]),
        snapshotRunner(snapshots: ["disk9s5": Data("invalid plist".utf8)]),
        snapshotRunner(snapshots: ["disk9s5": propertyList([:])]),
      ]

      for commands in runners {
        XCTAssertNil(APFSSnapshotInspector(commands: commands).constraint(in: storage()))
      }
    }

    func testExternalOrDifferentContainerCannotSupplySnapshotEvidence() {
      let snapshots = [
        "disk9s5": propertyList([
          "Snapshots": [["LimitingContainerShrink": true]]
        ])
      ]
      let commands = snapshotRunner(snapshots: snapshots)
      XCTAssertNil(
        APFSSnapshotInspector(commands: commands).constraint(in: storage(isInternal: false))
      )
      let otherContainer = snapshotRunner(container: "disk8", snapshots: snapshots)
      XCTAssertNil(
        APFSSnapshotInspector(commands: otherContainer).constraint(in: storage())
      )
    }

    func testUnsafeVolumeIdentifierIsRejectedBeforeSnapshotQuery() {
      for unsafe in ["disk", "disk9", "disk9s", "diskss5", "disk9s5;eraseDisk"] {
        let commands = snapshotRunner(
          volumes: [unsafe],
          snapshots: [
            unsafe: propertyList(["Snapshots": [["LimitingContainerShrink": true]]])
          ]
        )

        XCTAssertNil(APFSSnapshotInspector(commands: commands).constraint(in: storage()))
      }

    }

    private func storage(isInternal: Bool = true) -> APFSStorageInspection {
      APFSStorageInspection(
        containerIdentifier: "disk9",
        physicalStoreIdentifier: "disk0s2",
        isInternal: isInternal,
        containerSizeBytes: 1_000,
        containerFreeBytes: 200,
        minimumPreferredSizeBytes: 1_000
      )
    }

    private func snapshotRunner(
      container: String = "disk9",
      volumes: [String] = ["disk9s5"],
      snapshots: [String: Data]
    ) -> SnapshotCommandRunner {
      SnapshotCommandRunner(
        volumes: propertyList([
          "Containers": [
            [
              "ContainerReference": container,
              "Volumes": volumes.map { ["DeviceIdentifier": $0] },
            ]
          ]
        ]),
        snapshots: snapshots
      )
    }
  }

  private struct SnapshotCommandRunner: ReadOnlyMacCommandRunning {
    let volumes: Data?
    let snapshots: [String: Data]

    func run(_ command: ReadOnlyMacCommand) throws -> Data {
      let response: Data?
      switch command {
      case .apfsVolumes:
        response = volumes
      case .apfsSnapshots(let volume):
        response = snapshots[volume.rawValue]
      default:
        XCTFail("Snapshot diagnostics must use only APFS list and listSnapshots.")
        response = nil
      }
      guard let response else {
        throw AppleSiliconHostInspectionError.commandFailed(command.auditName, 1)
      }
      return response
    }
  }

  private struct FixtureHardwarePropertyReader: HardwarePropertyReading {
    let values: [String: String]

    func string(named name: String) throws -> String {
      guard let value = values[name] else {
        throw AppleSiliconHostInspectionError.hardwarePropertyUnavailable(name)
      }
      return value
    }
  }

  private struct FixtureReadOnlyCommandRunner: ReadOnlyMacCommandRunning {
    let root: Data
    let limits: Data
    let power: Data

    func run(_ command: ReadOnlyMacCommand) throws -> Data {
      switch command {
      case .rootDiskInfo:
        root
      case .apfsResizeLimits:
        limits
      case .apfsVolumes, .apfsSnapshots:
        throw AppleSiliconHostInspectionError.commandFailed(command.auditName, 1)
      case .powerSource:
        power
      }
    }
  }

  private struct FixtureOperatingSystemVersionReader:
    OperatingSystemVersionReading
  {
    func versionString() -> String {
      "Version 15.6 (Build 24G84)"
    }
  }

  private func propertyList(_ values: [String: Any]) -> Data {
    try! PropertyListSerialization.data(
      fromPropertyList: values,
      format: .xml,
      options: 0
    )
  }
#endif
