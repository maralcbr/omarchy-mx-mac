#if os(macOS)
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  final class InstallConfESPWriterTests: XCTestCase {
    func testRecordPolicyWritesAfterInstallAndRecoveryRetry() {
      XCTAssertTrue(
        InstallConfRecordPolicy.shouldRecord(
          operation: .install, nextAction: .enterRecovery))
      XCTAssertTrue(
        InstallConfRecordPolicy.shouldRecord(
          operation: .retryRecoveryAuthorization, nextAction: .enterRecovery))
      XCTAssertFalse(
        InstallConfRecordPolicy.shouldRecord(
          operation: .install, nextAction: .verifyInstalledSystem))
    }

    func testLocatorPicksTheEFIVolumeInsideThePlanExtent() throws {
      let identity = try InstallConfESPLocator.identify(
        storeIdentifier: "disk0",
        offsetBytes: 800_000_000_000,
        lengthBytes: 137_000_000_000,
        partitions: [
          .init(
            identifier: "disk0s2", storeIdentifier: "disk0", type: "Apple_APFS",
            name: "Macintosh HD", offsetBytes: 500_000_000, lengthBytes: 799_500_000_000),
          .init(
            identifier: "disk0s4", storeIdentifier: "disk0", type: "Apple_APFS",
            name: "Omarchy", offsetBytes: 800_000_000_000, lengthBytes: 3_000_000_000),
          .init(
            identifier: "disk0s5", storeIdentifier: "disk0", type: "EFI",
            name: "EFI - OMARC", offsetBytes: 803_000_000_000, lengthBytes: 500_000_000),
          .init(
            identifier: "disk0s6", storeIdentifier: "disk0", type: "Linux Filesystem",
            name: "OMARCHY_BOOT", offsetBytes: 803_500_000_000, lengthBytes: 2_000_000_000),
        ]
      )
      XCTAssertEqual(identity.partitionIdentifier, "disk0s5")
      XCTAssertEqual(identity.storeIdentifier, "disk0")
    }

    func testLocatorIgnoresAnEFIOutsideThePlanExtent() {
      XCTAssertThrowsError(
        try InstallConfESPLocator.identify(
          storeIdentifier: "disk0",
          offsetBytes: 800_000_000_000,
          lengthBytes: 137_000_000_000,
          partitions: [
            .init(
              identifier: "disk0s1", storeIdentifier: "disk0", type: "EFI",
              name: "EFI - OMARC", offsetBytes: 40_000, lengthBytes: 500_000_000)
          ]
        )
      ) { XCTAssertEqual($0 as? InstallConfESPError, .notFound) }
    }

    func testLocatorRejectsAnEFIThatExtendsPastThePlanExtent() {
      XCTAssertThrowsError(
        try InstallConfESPLocator.identify(
          storeIdentifier: "disk0",
          offsetBytes: 800_000_000_000,
          lengthBytes: 137_000_000_000,
          partitions: [
            .init(
              identifier: "disk0s5", storeIdentifier: "disk0", type: "EFI",
              name: "EFI - OMARC", offsetBytes: 803_000_000_000,
              lengthBytes: 200_000_000_000)
          ]
        )
      ) { XCTAssertEqual($0 as? InstallConfESPError, .notFound) }
    }

    func testLocatorRejectsAnEFIWhoseEndOverflows() {
      XCTAssertThrowsError(
        try InstallConfESPLocator.identify(
          storeIdentifier: "disk0",
          offsetBytes: 100,
          lengthBytes: 200,
          partitions: [
            .init(
              identifier: "disk0s5", storeIdentifier: "disk0", type: "EFI",
              name: "EFI - OMARC", offsetBytes: 150,
              lengthBytes: UInt64.max - 40)
          ]
        )
      ) { XCTAssertEqual($0 as? InstallConfESPError, .notFound) }
    }

    func testWriterRecordsSuccessFromTheHelper() async throws {
      let helper = MockInstallConfESPHelper(result: .success(()))
      let writer = InstallConfESPWriter(helper: helper)
      let conf = try InstallConf(encrypt: true, lane: "stable")
      let outcome = await writer.record(
        conf, storeIdentifier: "disk0", offsetBytes: 1, lengthBytes: 2)
      XCTAssertEqual(outcome, .recorded)
      XCTAssertEqual(helper.storeIdentifier, "disk0")
      XCTAssertEqual(helper.conf, conf)
    }

    func testWriterTreatsMountFailureAsDefaultOn() async throws {
      let helper = MockInstallConfESPHelper(result: .failure(.mountFailed))
      let writer = InstallConfESPWriter(helper: helper)
      let outcome = await writer.record(
        try InstallConf(encrypt: false, lane: "rc"),
        storeIdentifier: "disk0", offsetBytes: 1, lengthBytes: 2)
      XCTAssertEqual(outcome, .notRecorded)
    }

    func testWriterTreatsUnmountFailureAfterWriteAsUnconfirmed() async throws {
      let helper = MockInstallConfESPHelper(result: .failure(.unmountFailed))
      let writer = InstallConfESPWriter(helper: helper)
      let outcome = await writer.record(
        try InstallConf(encrypt: false, lane: "rc"),
        storeIdentifier: "disk0", offsetBytes: 1, lengthBytes: 2)
      XCTAssertEqual(outcome, .unconfirmed(encrypt: false))
    }

    func testWriterTreatsReadbackMismatchAfterAConfirmedWriteAsUnconfirmed() async throws {
      let helper = MockInstallConfESPHelper(result: .failure(.readbackMismatch))
      let writer = InstallConfESPWriter(helper: helper)
      let outcome = await writer.record(
        try InstallConf(encrypt: true, lane: "rc-aurora"),
        storeIdentifier: "disk0", offsetBytes: 1, lengthBytes: 2)
      XCTAssertEqual(outcome, .unconfirmed(encrypt: true))
    }

    func testWriterPreservesTypedOutcomesThroughTheXPCCodec() async throws {
      let conf = try InstallConf(encrypt: false, lane: "rc")
      let unmount = await InstallConfESPWriter(
        helper: XPCCodecInstallConfHelper(helperError: .unmountFailed)
      ).record(conf, storeIdentifier: "disk0", offsetBytes: 1, lengthBytes: 2)
      XCTAssertEqual(unmount, .unconfirmed(encrypt: false))

      let readback = await InstallConfESPWriter(
        helper: XPCCodecInstallConfHelper(helperError: .readbackMismatch)
      ).record(
        try InstallConf(encrypt: true, lane: "stable"),
        storeIdentifier: "disk0", offsetBytes: 1, lengthBytes: 2)
      XCTAssertEqual(readback, .unconfirmed(encrypt: true))

      let mount = await InstallConfESPWriter(
        helper: XPCCodecInstallConfHelper(helperError: .mountFailed)
      ).record(conf, storeIdentifier: "disk0", offsetBytes: 1, lengthBytes: 2)
      XCTAssertEqual(mount, .notRecorded)

      let recorded = await InstallConfESPWriter(
        helper: XPCCodecInstallConfHelper(helperError: nil)
      ).record(conf, storeIdentifier: "disk0", offsetBytes: 1, lengthBytes: 2)
      XCTAssertEqual(recorded, .recorded)

      let (data, error) = InstallConfXPCCodec.encodeReply(
        error: ClosedEngineHelperError.invalidMachineOwnerCredentials,
        encrypt: false
      )
      XCTAssertNil(data)
      XCTAssertEqual(
        error?.domain,
        EngineXPCErrorBridge.machineOwnerAuthorizationDomain
      )
      XCTAssertThrowsError(try InstallConfXPCCodec.decodeReply(data: data, error: error)) {
        XCTAssertEqual(
          $0 as? EngineXPCSubmissionError,
          .machineOwnerCredentialsRejected
        )
      }
    }

    func testMountWriterWritesAtomicallyAndUnmounts() throws {
      let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("esp-writer-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let disks = MockESPDisks(
        partitions: [
          .init(
            identifier: "disk0s5", storeIdentifier: "disk0", type: "EFI",
            name: "EFI - OMARC", offsetBytes: 100, lengthBytes: 50)
        ]
      )
      let writer = InstallConfESPMountWriter(disks: disks, workingDirectory: root)
      let conf = try InstallConf(encrypt: false, lane: "rc")
      try writer.write(conf, storeIdentifier: "disk0", offsetBytes: 50, lengthBytes: 200)
      XCTAssertEqual(disks.mounted, [])
      XCTAssertEqual(disks.mountCalls, 1)
      XCTAssertEqual(disks.unmountCalls, 1)
      XCTAssertEqual(disks.capturedDocuments, [conf.serializedData])
      XCTAssertEqual(disks.mountPoints.count, 1)
      XCTAssertTrue(disks.mountPoints[0].lastPathComponent.hasPrefix("esp-handoff-"))
      XCTAssertFalse(FileManager.default.fileExists(atPath: disks.mountPoints[0].path))
    }

    func testMountWriterUsesAFreshDirectoryAndLeavesAMountedOneAlone() throws {
      let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("esp-writer-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let disks = MockESPDisks(
        partitions: [
          .init(
            identifier: "disk0s5", storeIdentifier: "disk0", type: "EFI",
            name: "EFI - OMARC", offsetBytes: 100, lengthBytes: 50)
        ],
        unmountFailuresRemaining: 1
      )
      let writer = InstallConfESPMountWriter(disks: disks, workingDirectory: root)
      XCTAssertThrowsError(
        try writer.write(
          try InstallConf(encrypt: false, lane: "rc"),
          storeIdentifier: "disk0", offsetBytes: 50, lengthBytes: 200)
      ) { XCTAssertEqual($0 as? InstallConfESPError, .unmountFailed) }
      XCTAssertEqual(disks.mountPoints.count, 1)
      let first = disks.mountPoints[0]
      let sentinel = first.appendingPathComponent("sentinel")
      try Data("keep".utf8).write(to: sentinel)
      try writer.write(
        try InstallConf(encrypt: true, lane: "stable"),
        storeIdentifier: "disk0", offsetBytes: 50, lengthBytes: 200)
      XCTAssertEqual(disks.mountPoints.count, 2)
      XCTAssertNotEqual(disks.mountPoints[0], disks.mountPoints[1])
      XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
    }

    func testMountWriterReplacesAnExistingDocumentAtomically() throws {
      let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("esp-writer-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let previous = try InstallConf(encrypt: true, lane: "stable")
      let disks = MockESPDisks(
        partitions: [
          .init(
            identifier: "disk0s5", storeIdentifier: "disk0", type: "EFI",
            name: "EFI - OMARC", offsetBytes: 100, lengthBytes: 50)
        ],
        seedDocument: previous.serializedData
      )
      let next = try InstallConf(encrypt: false, lane: "rc")
      try InstallConfESPMountWriter(disks: disks, workingDirectory: root).write(
        next, storeIdentifier: "disk0", offsetBytes: 50, lengthBytes: 200)
      XCTAssertEqual(disks.capturedDocuments, [next.serializedData])
    }

    func testMountWriterSurfacesMountFailure() {
      let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("esp-writer-\(UUID().uuidString)", isDirectory: true)
      try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let disks = MockESPDisks(
        partitions: [
          .init(
            identifier: "disk0s5", storeIdentifier: "disk0", type: "EFI",
            name: "EFI - OMARC", offsetBytes: 100, lengthBytes: 50)
        ],
        mountError: InstallConfESPError.mountFailed
      )
      XCTAssertThrowsError(
        try InstallConfESPMountWriter(disks: disks, workingDirectory: root).write(
          try InstallConf(encrypt: true, lane: "stable"),
          storeIdentifier: "disk0", offsetBytes: 50, lengthBytes: 200)
      ) { XCTAssertEqual($0 as? InstallConfESPError, .mountFailed) }
    }

    func testMountWriterSurfacesReadbackMismatch() throws {
      let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("esp-writer-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let disks = MockESPDisks(
        partitions: [
          .init(
            identifier: "disk0s5", storeIdentifier: "disk0", type: "EFI",
            name: "EFI - OMARC", offsetBytes: 100, lengthBytes: 50)
        ]
      )
      XCTAssertThrowsError(
        try InstallConfESPMountWriter(
          disks: disks,
          workingDirectory: root,
          contentsOf: { _ in Data("tampered".utf8) }
        ).write(
          try InstallConf(encrypt: true, lane: "stable"),
          storeIdentifier: "disk0", offsetBytes: 50, lengthBytes: 200)
      ) { XCTAssertEqual($0 as? InstallConfESPError, .readbackMismatch) }
    }
  }

  private final class MockInstallConfESPHelper: InstallConfESPHelping, @unchecked Sendable {
    let result: Result<Void, InstallConfESPError>
    private(set) var conf: InstallConf?
    private(set) var storeIdentifier: String?

    init(result: Result<Void, InstallConfESPError>) {
      self.result = result
    }

    func write(
      _ conf: InstallConf,
      storeIdentifier: String,
      offsetBytes: UInt64,
      lengthBytes: UInt64
    ) async throws -> InstallConfHandoff {
      self.conf = conf
      self.storeIdentifier = storeIdentifier
      _ = offsetBytes
      _ = lengthBytes
      try result.get()
      return .recorded
    }
  }

  private final class XPCCodecInstallConfHelper: InstallConfESPHelping, @unchecked Sendable {
    let helperError: InstallConfESPError?

    init(helperError: InstallConfESPError?) {
      self.helperError = helperError
    }

    func write(
      _ conf: InstallConf,
      storeIdentifier: String,
      offsetBytes: UInt64,
      lengthBytes: UInt64
    ) async throws -> InstallConfHandoff {
      _ = storeIdentifier
      _ = offsetBytes
      _ = lengthBytes
      let (data, error) = InstallConfXPCCodec.encodeReply(
        error: helperError,
        encrypt: conf.encrypt
      )
      let payload = try InstallConfXPCCodec.decodeReply(data: data, error: error)
      return try InstallConfXPCCodec.decode(payload)
    }
  }

  private final class MockESPDisks: InstallConfESPDiskOperating, @unchecked Sendable {
    let partitionsToReturn: [InstallConfESPPartition]
    let mountError: InstallConfESPError?
    let seedDocument: Data?
    var unmountFailuresRemaining: Int
    private(set) var mounted: [String] = []
    private(set) var mountCalls = 0
    private(set) var unmountCalls = 0
    private(set) var mountPoints: [URL] = []
    private(set) var capturedDocuments: [Data] = []
    private var lastMountPoint: URL?

    init(
      partitions: [InstallConfESPPartition],
      mountError: InstallConfESPError? = nil,
      unmountFailuresRemaining: Int = 0,
      seedDocument: Data? = nil
    ) {
      partitionsToReturn = partitions
      self.mountError = mountError
      self.unmountFailuresRemaining = unmountFailuresRemaining
      self.seedDocument = seedDocument
    }

    func partitions(on storeIdentifier: String) throws -> [InstallConfESPPartition] {
      partitionsToReturn.filter { $0.storeIdentifier == storeIdentifier }
    }

    func mount(_ identifier: String, at mountPoint: URL) throws {
      mountCalls += 1
      mountPoints.append(mountPoint)
      lastMountPoint = mountPoint
      if let mountError { throw mountError }
      try FileManager.default.createDirectory(
        at: mountPoint, withIntermediateDirectories: true)
      if let seedDocument {
        let directory = mountPoint.appendingPathComponent(
          InstallConf.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try seedDocument.write(
          to: directory.appendingPathComponent(InstallConf.fileName), options: .atomic)
      }
      mounted.append(identifier)
    }

    func unmount(_ identifier: String) throws {
      unmountCalls += 1
      if let lastMountPoint {
        let file =
          lastMountPoint
          .appendingPathComponent(InstallConf.directoryName, isDirectory: true)
          .appendingPathComponent(InstallConf.fileName)
        if let data = try? Data(contentsOf: file) {
          capturedDocuments.append(data)
        }
      }
      if unmountFailuresRemaining > 0 {
        unmountFailuresRemaining -= 1
        throw InstallConfESPError.unmountFailed
      }
      mounted.removeAll { $0 == identifier }
    }
  }
#endif
