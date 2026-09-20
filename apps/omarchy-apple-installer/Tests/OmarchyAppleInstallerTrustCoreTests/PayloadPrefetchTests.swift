#if os(macOS)
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
      if delayNanoseconds > 0 {
        try await Task.sleep(nanoseconds: delayNanoseconds)
      }
      try Task.checkCancellation()
      report(100, 100)
    }
  }
#endif
