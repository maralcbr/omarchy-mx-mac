#if os(macOS)
  import CryptoKit
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  final class PayloadPrefetchTests: XCTestCase {
    func testDownloadsThenVerifiesOnUnmeteredPath() async throws {
      let network = MockNetworkPath(
        InstallerNetworkPathSnapshot(isSatisfied: true, isExpensive: false, isConstrained: false)
      )
      let keepAwake = MockKeepAwake()
      let downloader = MockPrefetchDownloader()
      let controller = PayloadPrefetchController(
        network: network,
        freeSpace: MockFreeSpace(bytes: 8_000_000_000),
        keepAwake: keepAwake
      )
      await controller.start(requiredBytes: 100, downloader: downloader)
      try await controller.waitUntilVerified()
      let state = await controller.currentState()
      XCTAssertEqual(state, .verified)
      XCTAssertEqual(downloader.starts, 1)
      XCTAssertEqual(keepAwake.acquired, 1)
      XCTAssertEqual(keepAwake.released, 1)
    }

    func testWaitsForUnmeteredNetworkThenResumes() async throws {
      let network = MockNetworkPath(
        InstallerNetworkPathSnapshot(isSatisfied: true, isExpensive: true, isConstrained: false)
      )
      let controller = PayloadPrefetchController(
        network: network,
        freeSpace: MockFreeSpace(bytes: 8_000_000_000),
        keepAwake: MockKeepAwake()
      )
      let downloader = MockPrefetchDownloader(delayNanoseconds: 200_000_000)
      await controller.start(requiredBytes: 100, downloader: downloader)
      try await Task.sleep(for: .milliseconds(50))
      var state = await controller.currentState()
      XCTAssertEqual(state, .waitingForUnmeteredNetwork)
      XCTAssertEqual(downloader.starts, 0)
      network.publish(
        InstallerNetworkPathSnapshot(isSatisfied: true, isExpensive: false, isConstrained: false)
      )
      try await controller.waitUntilVerified()
      state = await controller.currentState()
      XCTAssertEqual(state, .verified)
    }

    func testPausesWhenThePathBecomesExpensive() async throws {
      let network = MockNetworkPath(
        InstallerNetworkPathSnapshot(isSatisfied: true, isExpensive: false, isConstrained: false)
      )
      let downloader = MockPrefetchDownloader(delayNanoseconds: 800_000_000)
      let controller = PayloadPrefetchController(
        network: network,
        freeSpace: MockFreeSpace(bytes: 8_000_000_000),
        keepAwake: MockKeepAwake()
      )
      await controller.start(requiredBytes: 100, downloader: downloader)
      try await Task.sleep(for: .milliseconds(40))
      network.publish(
        InstallerNetworkPathSnapshot(isSatisfied: true, isExpensive: true, isConstrained: false)
      )
      try await Task.sleep(for: .milliseconds(80))
      let state = await controller.currentState()
      guard case .paused = state else {
        return XCTFail("Expected paused, got \(state)")
      }
      await controller.cancel()
    }

    func testFailsWhenTheVolumeIsTooSmall() async throws {
      let controller = PayloadPrefetchController(
        network: MockNetworkPath(
          InstallerNetworkPathSnapshot(isSatisfied: true, isExpensive: false, isConstrained: false)
        ),
        freeSpace: MockFreeSpace(bytes: 10),
        keepAwake: MockKeepAwake()
      )
      await controller.start(requiredBytes: 100, downloader: MockPrefetchDownloader())
      do {
        try await controller.waitUntilVerified()
        XCTFail("Expected insufficient space")
      } catch let error as PayloadPrefetchError {
        guard case .insufficientSpace = error else {
          return XCTFail("Expected insufficientSpace, got \(error)")
        }
      }
      let state = await controller.currentState()
      guard case .failed = state else {
        return XCTFail("Expected failed, got \(state)")
      }
    }

    func testResumeRequiresRemainingBytesPlusAssemblyHeadroom() async throws {
      let network = MockNetworkPath(
        InstallerNetworkPathSnapshot(isSatisfied: true, isExpensive: false, isConstrained: false)
      )
      let freeSpace = MutableFreeSpace(bytes: 8_000_000_000)
      let downloader = MockPrefetchDownloader(delayNanoseconds: 800_000_000)
      let controller = PayloadPrefetchController(
        network: network,
        freeSpace: freeSpace,
        keepAwake: MockKeepAwake()
      )
      let payloadSize: UInt64 = 100
      let required = VerifiedArtifactStager.requiredFreeBytes(forPayloadSize: payloadSize)
      await controller.start(requiredBytes: required, downloader: downloader)
      try await Task.sleep(for: .milliseconds(40))
      network.publish(
        InstallerNetworkPathSnapshot(isSatisfied: true, isExpensive: true, isConstrained: false)
      )
      try await Task.sleep(for: .milliseconds(80))
      let paused = await controller.currentState()
      guard case .paused(let completed, _) = paused else {
        return XCTFail("Expected paused, got \(paused)")
      }
      XCTAssertGreaterThan(completed, 0)
      let remaining = VerifiedArtifactStager.requiredFreeBytes(
        forPayloadSize: payloadSize,
        alreadyOnDisk: completed
      )
      XCTAssertLessThan(remaining, required)
      freeSpace.bytes = remaining
      network.publish(
        InstallerNetworkPathSnapshot(isSatisfied: true, isExpensive: false, isConstrained: false)
      )
      try await controller.waitUntilVerified()
      let state = await controller.currentState()
      XCTAssertEqual(state, .verified)
    }

    func testCancelStopsWaiters() async throws {
      let network = MockNetworkPath(
        InstallerNetworkPathSnapshot(isSatisfied: true, isExpensive: false, isConstrained: false)
      )
      let controller = PayloadPrefetchController(
        network: network,
        freeSpace: MockFreeSpace(bytes: 8_000_000_000),
        keepAwake: MockKeepAwake()
      )
      await controller.start(
        requiredBytes: 100,
        downloader: MockPrefetchDownloader(delayNanoseconds: 2_000_000_000)
      )
      await controller.cancel()
      do {
        try await controller.waitUntilVerified()
        XCTFail("Expected cancellation")
      } catch let error as PayloadPrefetchError {
        XCTAssertEqual(error, .cancelled)
      }
      let state = await controller.currentState()
      XCTAssertEqual(state, .cancelled)
    }

    func testOrchestratorReusesThePredecessorAndUsesUniqueWorkDirectories() async throws {
      let data = Data("payload-bytes".utf8)
      let artifact = try pinnedPayload(data)
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "prefetch-orch-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let canonical = root.appendingPathComponent(artifact.fileName)
      let payload = StagedInstallerArtifact(
        artifact: artifact, fileURL: canonical, reusedExistingFile: false)
      let stagedDirectories = RecordingBox<URL>()
      let required = RecordingBox<UInt64>()
      let states = RecordingBox<PayloadPrefetchState>()
      let orchestrator = PayloadPrefetchOrchestrator(
        makeNetwork: {
          MockNetworkPath(
            InstallerNetworkPathSnapshot(
              isSatisfied: true, isExpensive: false, isConstrained: false))
        },
        makeKeepAwake: { MockKeepAwake() },
        makeFreeSpace: { _ in MockFreeSpace(bytes: 8_000_000_000) },
        matchesPinned: { _, _ in false },
        requiredFreeBytes: { size in
          let value = VerifiedArtifactStager.requiredFreeBytes(forPayloadSize: size)
          required.append(value)
          return value
        },
        stage: { artifact, directory, progress in
          stagedDirectories.append(directory)
          try await Task.sleep(for: .milliseconds(80))
          progress?(
            ArtifactStagingProgress(
              role: artifact.role, fileName: artifact.fileName, phase: .downloading,
              bytesCompleted: UInt64(data.count), totalBytes: UInt64(data.count)))
          let file = directory.appendingPathComponent(artifact.fileName)
          try data.write(to: file)
          progress?(
            ArtifactStagingProgress(
              role: artifact.role, fileName: artifact.fileName, phase: .verified,
              bytesCompleted: UInt64(data.count), totalBytes: UInt64(data.count)))
          return StagedInstallerArtifact(
            artifact: artifact, fileURL: file, reusedExistingFile: false)
        }
      )
      orchestrator.begin(payload: payload)
      orchestrator.begin(payload: payload)
      try await orchestrator.waitUntilVerified { states.append($0) }
      XCTAssertEqual(stagedDirectories.values.count, 1)
      XCTAssertTrue(stagedDirectories.values[0].lastPathComponent.hasPrefix("prefetch-"))
      XCTAssertNotEqual(stagedDirectories.values[0], root)
      XCTAssertEqual(
        required.values,
        [VerifiedArtifactStager.requiredFreeBytes(forPayloadSize: UInt64(data.count))]
      )
      XCTAssertTrue(states.values.contains { if case .downloading = $0 { true } else { false } })
      XCTAssertEqual(try Data(contentsOf: canonical), data)
    }

    func testOrchestratorHashesBeforePublishingVerified() async throws {
      let data = Data("cached-payload".utf8)
      let artifact = try pinnedPayload(data)
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "prefetch-hash-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let canonical = root.appendingPathComponent(artifact.fileName)
      try data.write(to: canonical)
      let staged = RecordingBox<Int>()
      let hashed = RecordingBox<Int>()
      let states = RecordingBox<PayloadPrefetchState>()
      let orchestrator = PayloadPrefetchOrchestrator(
        makeNetwork: {
          MockNetworkPath(
            InstallerNetworkPathSnapshot(
              isSatisfied: true, isExpensive: false, isConstrained: false))
        },
        makeKeepAwake: { MockKeepAwake() },
        makeFreeSpace: { _ in MockFreeSpace(bytes: 8_000_000_000) },
        matchesPinned: { candidate, url in
          hashed.append(1)
          return VerifiedArtifactStager().matches(candidate, at: url)
        },
        requiredFreeBytes: { VerifiedArtifactStager.requiredFreeBytes(forPayloadSize: $0) },
        stage: { _, _, _ in
          staged.append(1)
          throw PayloadPrefetchError.failed("must not download a hashed cache")
        }
      )
      orchestrator.begin(
        payload: StagedInstallerArtifact(
          artifact: artifact, fileURL: canonical, reusedExistingFile: false))
      try await orchestrator.waitUntilVerified { states.append($0) }
      XCTAssertEqual(hashed.values.count, 1)
      XCTAssertEqual(staged.values.count, 0)
      XCTAssertTrue(states.values.contains(.verifying))
      XCTAssertEqual(orchestrator.currentState(), .verified)
    }

    func testOrchestratorCancelsThePredecessorOnANewArtifact() async throws {
      let first = try pinnedPayload(Data("first-payload".utf8), fileName: "first.bin")
      let second = try pinnedPayload(Data("second-payload".utf8), fileName: "second.bin")
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "prefetch-cancel-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let stagedNames = RecordingBox<String>()
      let orchestrator = PayloadPrefetchOrchestrator(
        makeNetwork: {
          MockNetworkPath(
            InstallerNetworkPathSnapshot(
              isSatisfied: true, isExpensive: false, isConstrained: false))
        },
        makeKeepAwake: { MockKeepAwake() },
        makeFreeSpace: { _ in MockFreeSpace(bytes: 8_000_000_000) },
        matchesPinned: { _, _ in false },
        requiredFreeBytes: { VerifiedArtifactStager.requiredFreeBytes(forPayloadSize: $0) },
        stage: { artifact, directory, _ in
          stagedNames.append(artifact.fileName)
          if artifact.fileName == "first.bin" {
            try await Task.sleep(for: .seconds(2))
            try Task.checkCancellation()
          }
          let file = directory.appendingPathComponent(artifact.fileName)
          try Data(artifact.fileName.utf8).write(to: file)
          return StagedInstallerArtifact(
            artifact: artifact, fileURL: file, reusedExistingFile: false)
        }
      )
      orchestrator.begin(
        payload: StagedInstallerArtifact(
          artifact: first, fileURL: root.appendingPathComponent(first.fileName),
          reusedExistingFile: false))
      try await Task.sleep(for: .milliseconds(40))
      orchestrator.begin(
        payload: StagedInstallerArtifact(
          artifact: second, fileURL: root.appendingPathComponent(second.fileName),
          reusedExistingFile: false))
      try await orchestrator.waitUntilVerified { _ in }
      XCTAssertEqual(orchestrator.currentState(), .verified)
      XCTAssertEqual(
        try Data(contentsOf: root.appendingPathComponent("second.bin")), Data("second.bin".utf8))
    }

    private func pinnedPayload(_ data: Data, fileName: String = "os.bin") throws
      -> PinnedInstallerArtifact
    {
      try PinnedInstallerArtifact(
        role: "payload",
        sourceURL: URL(string: "https://example.com/\(fileName)")!,
        fileName: fileName,
        expectedDigest: "sha256:"
          + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
        expectedSizeBytes: UInt64(data.count)
      )
    }
  }

  private final class RecordingBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []
    func append(_ value: Value) {
      lock.withLock { storage.append(value) }
    }
    var values: [Value] {
      lock.withLock { storage }
    }
  }

  private final class MockNetworkPath: InstallerNetworkPathObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: InstallerNetworkPathSnapshot
    private var continuations: [UUID: AsyncStream<InstallerNetworkPathSnapshot>.Continuation] = [:]

    init(_ snapshot: InstallerNetworkPathSnapshot) {
      self.snapshot = snapshot
    }

    func current() -> InstallerNetworkPathSnapshot {
      lock.withLock { snapshot }
    }

    func updates() -> AsyncStream<InstallerNetworkPathSnapshot> {
      AsyncStream { continuation in
        let id = UUID()
        lock.lock()
        continuations[id] = continuation
        let snapshot = snapshot
        lock.unlock()
        continuation.yield(snapshot)
        continuation.onTermination = { [weak self] _ in
          self?.lock.lock()
          self?.continuations[id] = nil
          self?.lock.unlock()
        }
      }
    }

    func publish(_ snapshot: InstallerNetworkPathSnapshot) {
      lock.lock()
      self.snapshot = snapshot
      let pending = Array(continuations.values)
      lock.unlock()
      for continuation in pending {
        continuation.yield(snapshot)
      }
    }
  }

  private struct MockFreeSpace: InstallerFreeSpaceChecking, Sendable {
    let bytes: UInt64
    func availableBytes() throws -> UInt64 { bytes }
  }

  private final class MutableFreeSpace: InstallerFreeSpaceChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: UInt64

    init(bytes: UInt64) {
      storage = bytes
    }

    var bytes: UInt64 {
      get { lock.withLock { storage } }
      set { lock.withLock { storage = newValue } }
    }

    func availableBytes() throws -> UInt64 { bytes }
  }

  private final class MockKeepAwake: InstallerKeepAwakeHolding, @unchecked Sendable {
    private(set) var acquired = 0
    private(set) var released = 0
    func acquire() { acquired += 1 }
    func release() { released += 1 }
  }

  private final class MockPrefetchDownloader: PayloadPrefetchDownloading, @unchecked Sendable {
    let delayNanoseconds: UInt64
    private(set) var starts = 0

    init(delayNanoseconds: UInt64 = 0) {
      self.delayNanoseconds = delayNanoseconds
    }

    func download(
      report: @escaping @Sendable (UInt64, UInt64) -> Void
    ) async throws {
      starts += 1
      report(50, 100)
      if starts == 1, delayNanoseconds > 0 {
        try await Task.sleep(nanoseconds: delayNanoseconds)
      }
      try Task.checkCancellation()
      report(100, 100)
    }
  }
#endif
