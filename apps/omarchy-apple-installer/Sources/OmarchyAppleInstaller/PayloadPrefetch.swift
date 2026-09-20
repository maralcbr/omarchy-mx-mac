#if os(macOS)
  import Foundation
  import IOKit.pwr_mgt
  import Network

  public struct InstallerNetworkPathSnapshot: Equatable, Sendable {
    public let isSatisfied: Bool
    public let isExpensive: Bool
    public let isConstrained: Bool

    public init(isSatisfied: Bool, isExpensive: Bool, isConstrained: Bool) {
      self.isSatisfied = isSatisfied
      self.isExpensive = isExpensive
      self.isConstrained = isConstrained
    }

    /// Wi-Fi/Ethernet only: cellular and Low Data Mode pause the prefetch.
    public var allowsPrefetch: Bool {
      isSatisfied && !isExpensive && !isConstrained
    }
  }

  public protocol InstallerNetworkPathObserving: Sendable {
    func current() -> InstallerNetworkPathSnapshot
    func updates() -> AsyncStream<InstallerNetworkPathSnapshot>
  }

  public protocol InstallerFreeSpaceChecking: Sendable {
    func availableBytes() throws -> UInt64
  }

  public protocol InstallerKeepAwakeHolding: Sendable {
    func acquire()
    func release()
  }

  public protocol PayloadPrefetchDownloading: Sendable {
    func download(
      report: @escaping @Sendable (_ completed: UInt64, _ total: UInt64) -> Void
    ) async throws
  }

  public enum PayloadPrefetchError: Error, Equatable, Sendable {
    case meteredNetwork
    case insufficientSpace(requiredBytes: UInt64, availableBytes: UInt64)
    case cancelled
    case failed(String)
  }

  public enum PayloadPrefetchState: Equatable, Sendable {
    case idle
    case waitingForUnmeteredNetwork
    case downloading(completed: UInt64, total: UInt64)
    case paused(completed: UInt64, total: UInt64)
    case verifying
    case verified
    case failed(String)
    case cancelled
  }

  /// Downloads and verifies the selected channel while the disk-size screen is
  /// up. Metered or constrained paths pause; quitting cancels.
  public actor PayloadPrefetchController {
    private let network: any InstallerNetworkPathObserving
    private let freeSpace: any InstallerFreeSpaceChecking
    private let keepAwake: any InstallerKeepAwakeHolding
    private let onState: @Sendable (PayloadPrefetchState) -> Void
    private var state: PayloadPrefetchState = .idle
    private var runTask: Task<Void, Error>?
    private var waiters: [CheckedContinuation<Void, Error>] = []

    public init(
      network: any InstallerNetworkPathObserving,
      freeSpace: any InstallerFreeSpaceChecking,
      keepAwake: any InstallerKeepAwakeHolding,
      onState: @escaping @Sendable (PayloadPrefetchState) -> Void = { _ in }
    ) {
      self.network = network
      self.freeSpace = freeSpace
      self.keepAwake = keepAwake
      self.onState = onState
    }

    public func currentState() -> PayloadPrefetchState {
      state
    }

    public func start(
      requiredBytes: UInt64,
      downloader: any PayloadPrefetchDownloading
    ) {
      start(requiredBytes: requiredBytes) {
        try await downloader.download { completed, total in
          Task { [weak self] in
            await self?.reportDownload(completed: completed, total: total)
          }
        }
        await self.reportVerifying()
      }
    }

    public func start(
      requiredBytes: UInt64,
      work: @escaping @Sendable () async throws -> Void
    ) {
      runTask?.cancel()
      runTask = Task { try await self.drive(requiredBytes: requiredBytes, work: work) }
    }

    public func reportDownload(completed: UInt64, total: UInt64) {
      guard case .downloading = state else {
        return
      }
      setState(.downloading(completed: completed, total: total))
    }

    public func reportVerifying() {
      if case .cancelled = state {
        return
      }
      setState(.verifying)
    }

    public func cancel() {
      setState(.cancelled)
      runTask?.cancel()
      failWaiters(PayloadPrefetchError.cancelled)
    }

    public func waitUntilVerified() async throws {
      switch state {
      case .verified:
        return
      case .failed(let message):
        throw PayloadPrefetchError.failed(message)
      case .cancelled:
        throw PayloadPrefetchError.cancelled
      default:
        break
      }
      try await withCheckedThrowingContinuation { continuation in
        waiters.append(continuation)
      }
    }

    private func drive(
      requiredBytes: UInt64,
      work: @escaping @Sendable () async throws -> Void
    ) async throws {
      var completed: UInt64 = 0
      var total: UInt64 = requiredBytes
      while !Task.isCancelled {
        if case .cancelled = state {
          return
        }
        if case .paused(let current, let knownTotal) = state {
          completed = current
          total = knownTotal
        } else if case .downloading(let current, let knownTotal) = state {
          completed = current
          total = knownTotal
        }
        let path = network.current()
        if !path.allowsPrefetch {
          if completed > 0 {
            setState(.paused(completed: completed, total: total))
          } else {
            setState(.waitingForUnmeteredNetwork)
          }
          await waitForUnmeteredPath()
          continue
        }
        do {
          let available = try freeSpace.availableBytes()
          let requiredNow = requiredBytes > completed ? requiredBytes - completed : 0
          if available < requiredNow {
            let error = PayloadPrefetchError.insufficientSpace(
              requiredBytes: requiredNow,
              availableBytes: available
            )
            setState(.failed(String(describing: error)))
            failWaiters(error)
            return
          }
        } catch {
          setState(.failed(String(describing: error)))
          failWaiters(error)
          return
        }

        setState(.downloading(completed: completed, total: total))
        do {
          keepAwake.acquire()
          defer { keepAwake.release() }
          try await runInterruptible(work: work)
          setState(.verified)
          resumeWaiters()
          return
        } catch is CancellationError {
          if case .cancelled = state {
            return
          }
          if case .downloading(let current, let knownTotal) = state {
            completed = current
            total = knownTotal
          }
          setState(.paused(completed: completed, total: total))
          await waitForUnmeteredPath()
        } catch PayloadPrefetchError.meteredNetwork {
          if case .downloading(let current, let knownTotal) = state {
            completed = current
            total = knownTotal
          }
          setState(.paused(completed: completed, total: total))
          await waitForUnmeteredPath()
        } catch PayloadPrefetchError.cancelled {
          setState(.cancelled)
          failWaiters(PayloadPrefetchError.cancelled)
          return
        } catch {
          setState(.failed(String(describing: error)))
          failWaiters(error)
          return
        }
      }
      setState(.cancelled)
      failWaiters(PayloadPrefetchError.cancelled)
    }

    private func runInterruptible(
      work: @escaping @Sendable () async throws -> Void
    ) async throws {
      let stream = network.updates()
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await work() }
        group.addTask {
          for await path in stream {
            if Task.isCancelled {
              return
            }
            if !path.allowsPrefetch {
              throw PayloadPrefetchError.meteredNetwork
            }
          }
        }
        do {
          try await group.next()
          group.cancelAll()
        } catch {
          group.cancelAll()
          throw error
        }
      }
    }

    private func waitForUnmeteredPath() async {
      if network.current().allowsPrefetch {
        return
      }
      for await path in network.updates() {
        if Task.isCancelled {
          return
        }
        if path.allowsPrefetch {
          return
        }
      }
    }

    private func setState(_ next: PayloadPrefetchState) {
      state = next
      onState(next)
    }

    private func resumeWaiters() {
      let pending = waiters
      waiters.removeAll()
      for waiter in pending {
        waiter.resume()
      }
    }

    private func failWaiters(_ error: any Error) {
      let pending = waiters
      waiters.removeAll()
      for waiter in pending {
        waiter.resume(throwing: error)
      }
    }
  }

  public final class NWInstallerNetworkPathObserver:
    InstallerNetworkPathObserving, @unchecked Sendable
  {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var last = InstallerNetworkPathSnapshot(
      isSatisfied: false,
      isExpensive: true,
      isConstrained: true
    )
    private var continuations: [UUID: AsyncStream<InstallerNetworkPathSnapshot>.Continuation] = [:]

    public init() {
      monitor.pathUpdateHandler = { [weak self] path in
        self?.publish(
          InstallerNetworkPathSnapshot(
            isSatisfied: path.status == .satisfied,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
          )
        )
      }
      monitor.start(queue: DispatchQueue(label: "omarchy.installer.prefetch.network"))
    }

    deinit {
      monitor.cancel()
    }

    public func current() -> InstallerNetworkPathSnapshot {
      lock.withLock { last }
    }

    public func updates() -> AsyncStream<InstallerNetworkPathSnapshot> {
      AsyncStream { continuation in
        let id = UUID()
        lock.lock()
        continuations[id] = continuation
        let snapshot = last
        lock.unlock()
        continuation.yield(snapshot)
        continuation.onTermination = { [weak self] _ in
          self?.lock.lock()
          self?.continuations[id] = nil
          self?.lock.unlock()
        }
      }
    }

    private func publish(_ snapshot: InstallerNetworkPathSnapshot) {
      lock.lock()
      last = snapshot
      let pending = Array(continuations.values)
      lock.unlock()
      for continuation in pending {
        continuation.yield(snapshot)
      }
    }
  }

  public struct StagingVolumeFreeSpace: InstallerFreeSpaceChecking, Sendable {
    private let directory: URL

    public init(directory: URL) {
      self.directory = directory
    }

    public func availableBytes() throws -> UInt64 {
      let values = try directory.resourceValues(forKeys: [
        .volumeAvailableCapacityForImportantUsageKey
      ])
      let available = values.volumeAvailableCapacityForImportantUsage ?? 0
      return available > 0 ? UInt64(available) : 0
    }
  }

  public final class IOPMInstallerKeepAwake: InstallerKeepAwakeHolding, @unchecked Sendable {
    private let lock = NSLock()
    private var assertionID = IOPMAssertionID(0)
    private var held = false

    public init() {}

    public func acquire() {
      lock.lock()
      defer { lock.unlock() }
      guard !held else { return }
      var identifier = IOPMAssertionID(0)
      let created = IOPMAssertionCreateWithName(
        kIOPMAssertionTypeNoIdleSleep as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        "Omarchy installer downloading" as CFString,
        &identifier
      )
      guard created == kIOReturnSuccess else { return }
      assertionID = identifier
      held = true
    }

    public func release() {
      lock.lock()
      defer { lock.unlock() }
      guard held else { return }
      IOPMAssertionRelease(assertionID)
      held = false
      assertionID = IOPMAssertionID(0)
    }
  }

  /// One live prefetch at a time: reuse the in-flight controller when the
  /// artifact is unchanged, otherwise cancel it before starting a unique work
  /// directory so staging filenames cannot collide.
  public final class PayloadPrefetchOrchestrator: @unchecked Sendable {
    public typealias StageHandler =
      @Sendable (
        PinnedInstallerArtifact, URL, ArtifactStagingProgressHandler?
      ) async throws -> StagedInstallerArtifact

    private let lock = NSLock()
    private let makeNetwork: @Sendable () -> any InstallerNetworkPathObserving
    private let makeKeepAwake: @Sendable () -> any InstallerKeepAwakeHolding
    private let makeFreeSpace: @Sendable (URL) -> any InstallerFreeSpaceChecking
    private let matchesPinned: @Sendable (PinnedInstallerArtifact, URL) -> Bool
    private let requiredFreeBytes: @Sendable (UInt64) -> UInt64
    private let stage: StageHandler

    private var generation = UUID()
    private var controller: PayloadPrefetchController?
    private var runningDigest: String?
    private var latest: PayloadPrefetchState = .idle
    private var observers: [UUID: @Sendable (PayloadPrefetchState) -> Void] = [:]
    private var waiters: [CheckedContinuation<Void, any Error>] = []

    public convenience init() {
      self.init(
        makeNetwork: { NWInstallerNetworkPathObserver() },
        makeKeepAwake: { IOPMInstallerKeepAwake() },
        makeFreeSpace: { StagingVolumeFreeSpace(directory: $0) },
        matchesPinned: { VerifiedArtifactStager().matches($0, at: $1) },
        requiredFreeBytes: { VerifiedArtifactStager.requiredFreeBytes(forPayloadSize: $0) },
        stage: { artifact, directory, progress in
          try await InstallerAssetPreparer().stagePayload(
            artifact, in: directory, progress: progress)
        }
      )
    }

    public init(
      makeNetwork: @escaping @Sendable () -> any InstallerNetworkPathObserving,
      makeKeepAwake: @escaping @Sendable () -> any InstallerKeepAwakeHolding,
      makeFreeSpace: @escaping @Sendable (URL) -> any InstallerFreeSpaceChecking,
      matchesPinned: @escaping @Sendable (PinnedInstallerArtifact, URL) -> Bool,
      requiredFreeBytes: @escaping @Sendable (UInt64) -> UInt64,
      stage: @escaping StageHandler
    ) {
      self.makeNetwork = makeNetwork
      self.makeKeepAwake = makeKeepAwake
      self.makeFreeSpace = makeFreeSpace
      self.matchesPinned = matchesPinned
      self.requiredFreeBytes = requiredFreeBytes
      self.stage = stage
    }

    public func currentState() -> PayloadPrefetchState {
      lock.withLock { latest }
    }

    public func begin(payload: StagedInstallerArtifact) {
      let artifact = payload.artifact
      let canonical = payload.fileURL
      let parent = canonical.deletingLastPathComponent()

      let reuse = lock.withLock { () -> Bool in
        if runningDigest == artifact.expectedDigest {
          switch latest {
          case .failed, .cancelled:
            return false
          default:
            return true
          }
        }
        return false
      }
      if reuse {
        return
      }

      let predecessor: PayloadPrefetchController?
      let generation: UUID
      lock.lock()
      predecessor = controller
      controller = nil
      runningDigest = artifact.expectedDigest
      generation = UUID()
      self.generation = generation
      latest = .idle
      lock.unlock()

      Task {
        if let predecessor {
          await predecessor.cancel()
        }
        guard self.lock.withLock({ self.generation == generation }) else {
          return
        }

        self.publish(.verifying)
        if self.matchesPinned(artifact, canonical) {
          self.publish(.verified)
          return
        }

        let work = parent.appendingPathComponent(
          "prefetch-\(generation.uuidString.lowercased())",
          isDirectory: true
        )
        do {
          try FileManager.default.createDirectory(
            at: work,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
          )
        } catch {
          self.publish(.failed(String(describing: error)))
          return
        }

        let controller = PayloadPrefetchController(
          network: self.makeNetwork(),
          freeSpace: self.makeFreeSpace(work),
          keepAwake: self.makeKeepAwake(),
          onState: { [weak self] state in
            guard let self, self.lock.withLock({ self.generation == generation }) else {
              return
            }
            self.publish(state)
          }
        )
        self.lock.withLock {
          guard self.generation == generation else { return }
          self.controller = controller
        }

        let required = self.requiredFreeBytes(artifact.expectedSizeBytes)
        await controller.start(requiredBytes: required) {
          let staged = try await self.stage(artifact, work) { event in
            Task {
              await controller.reportDownload(
                completed: event.bytesCompleted,
                total: event.totalBytes
              )
              if event.phase == .verified || event.phase == .assembling {
                await controller.reportVerifying()
              }
            }
          }
          try self.promote(staged.fileURL, to: canonical)
          try? FileManager.default.removeItem(at: work)
        }
      }
    }

    public func waitUntilVerified(
      progress: @escaping @Sendable (PayloadPrefetchState) -> Void
    ) async throws {
      let token = UUID()
      let current: PayloadPrefetchState = lock.withLock {
        observers[token] = progress
        return latest
      }
      defer { lock.withLock { observers[token] = nil } }
      progress(current)
      switch current {
      case .verified:
        return
      case .failed(let message):
        throw PayloadPrefetchError.failed(message)
      case .cancelled:
        throw PayloadPrefetchError.cancelled
      default:
        break
      }
      try await withCheckedThrowingContinuation { continuation in
        lock.lock()
        switch latest {
        case .verified:
          lock.unlock()
          continuation.resume()
        case .failed(let message):
          lock.unlock()
          continuation.resume(throwing: PayloadPrefetchError.failed(message))
        case .cancelled:
          lock.unlock()
          continuation.resume(throwing: PayloadPrefetchError.cancelled)
        default:
          waiters.append(continuation)
          lock.unlock()
        }
      }
    }

    public func cancel() {
      lock.lock()
      latest = .idle
      runningDigest = nil
      let existing = controller
      controller = nil
      generation = UUID()
      let pending = waiters
      waiters.removeAll()
      let observers = Array(self.observers.values)
      lock.unlock()
      for waiter in pending {
        waiter.resume(throwing: PayloadPrefetchError.cancelled)
      }
      if let existing {
        Task { await existing.cancel() }
      }
      for observer in observers {
        observer(.idle)
      }
    }

    private func publish(_ state: PayloadPrefetchState) {
      let observers: [@Sendable (PayloadPrefetchState) -> Void]
      let pending: [CheckedContinuation<Void, any Error>]
      lock.lock()
      latest = state
      observers = Array(self.observers.values)
      switch state {
      case .verified:
        pending = waiters
        waiters.removeAll()
        lock.unlock()
        for waiter in pending {
          waiter.resume()
        }
      case .failed(let message):
        pending = waiters
        waiters.removeAll()
        lock.unlock()
        for waiter in pending {
          waiter.resume(throwing: PayloadPrefetchError.failed(message))
        }
      case .cancelled:
        pending = waiters
        waiters.removeAll()
        lock.unlock()
        for waiter in pending {
          waiter.resume(throwing: PayloadPrefetchError.cancelled)
        }
      default:
        pending = []
        lock.unlock()
      }
      _ = pending
      for observer in observers {
        observer(state)
      }
    }

    private func promote(_ staged: URL, to canonical: URL) throws {
      let fileManager = FileManager.default
      guard staged != canonical else { return }
      if fileManager.fileExists(atPath: canonical.path) {
        _ = try fileManager.replaceItemAt(canonical, withItemAt: staged)
      } else {
        try fileManager.moveItem(at: staged, to: canonical)
      }
    }
  }
#endif
