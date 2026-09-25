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

  /// Sorts prefetch errors into ones a later attempt can get past and says,
  /// in one sentence, what went wrong. The sentence is what the failed strip
  /// shows, so a report names the real check instead of a generic message.
  public enum PayloadPrefetchFailure {
    private static let transientURLErrors: Set<URLError.Code> = [
      .timedOut,
      .networkConnectionLost,
      .notConnectedToInternet,
      .cannotConnectToHost,
      .cannotFindHost,
      .dnsLookupFailed,
      .resourceUnavailable,
      .dataNotAllowed,
      .internationalRoamingOff,
      .callIsActive,
      .backgroundSessionWasDisconnected,
      .badServerResponse,
    ]

    /// Network faults and server-side hiccups. Size and digest mismatches,
    /// space, and staging conflicts are not retried.
    public static func isTransient(_ error: any Error) -> Bool {
      if let urlError = error as? URLError {
        return transientURLErrors.contains(urlError.code)
      }
      if case ArtifactStageError.unexpectedHTTPStatus(let status) = error {
        return status == 0 || status == 408 || status == 429 || (500...599).contains(status)
      }
      return false
    }

    public static func reason(for error: any Error) -> String {
      switch error {
      case PayloadPrefetchError.failed(let message):
        return message
      case PayloadPrefetchError.insufficientSpace(let required, let available):
        return "Not enough free space: the download needs \(bytes(required)) and "
          + "\(bytes(available)) is free."
      case PayloadPrefetchError.meteredNetwork:
        return "The download needs Wi-Fi or Ethernet without Low Data Mode."
      case PayloadPrefetchError.cancelled:
        return "The download was stopped."
      case ArtifactStageError.digestMismatch(let expected, let actual):
        return "The downloaded file does not match the signed release "
          + "(expected \(expected), got \(actual))."
      case ArtifactStageError.sizeMismatch(let expected, let actual):
        return "The downloaded file does not match the signed release "
          + "(expected \(expected) bytes, got \(actual))."
      case ArtifactStageError.unexpectedHTTPStatus(let status):
        return "The download server answered HTTP \(status)."
      case ArtifactStageError.destinationConflict(let name):
        return "A different copy of \(name) is already in the installer's staging folder."
      case let urlError as URLError:
        return "The download was interrupted: \(urlError.localizedDescription)"
      default:
        return "The download failed: \(String(describing: error))"
      }
    }

    private static func bytes(_ value: UInt64) -> String {
      ByteCountFormatter.string(
        fromByteCount: Int64(clamping: value), countStyle: .file)
    }
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
    private let retryDelays: [Duration]
    private let sleep: @Sendable (Duration) async throws -> Void
    private let retainedBytes: (@Sendable () -> UInt64)?

    /// A multi-gigabyte download on Wi-Fi meets dropped connections and stalls.
    /// Each is retried after these delays; the count starts again once a retry
    /// gets further than the one before.
    public static let defaultRetryDelays: [Duration] = [
      .seconds(2), .seconds(5), .seconds(15), .seconds(30), .seconds(60),
    ]

    public init(
      network: any InstallerNetworkPathObserving,
      freeSpace: any InstallerFreeSpaceChecking,
      keepAwake: any InstallerKeepAwakeHolding,
      retryDelays: [Duration] = PayloadPrefetchController.defaultRetryDelays,
      sleep: @escaping @Sendable (Duration) async throws -> Void = {
        try await Task.sleep(for: $0)
      },
      retainedBytes: (@Sendable () -> UInt64)? = nil,
      onState: @escaping @Sendable (PayloadPrefetchState) -> Void = { _ in }
    ) {
      self.network = network
      self.freeSpace = freeSpace
      self.keepAwake = keepAwake
      self.retryDelays = retryDelays
      self.sleep = sleep
      self.retainedBytes = retainedBytes
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

    /// Only a running download moves to verifying; a late hop after the
    /// download finished, failed or was cancelled is ignored.
    public func reportVerifying() {
      guard case .downloading = state else {
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
      var transientFailures = 0
      var furthestFailure: UInt64 = 0
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
          // An interrupted transfer starts again from zero; only files the
          // stager kept (verified parts) already occupy their share.
          let credited = retainedBytes.map { min(completed, $0()) } ?? completed
          let requiredNow = requiredBytes > credited ? requiredBytes - credited : 0
          if available < requiredNow {
            let error = PayloadPrefetchError.insufficientSpace(
              requiredBytes: requiredNow,
              availableBytes: available
            )
            setState(.failed(PayloadPrefetchFailure.reason(for: error)))
            failWaiters(error)
            return
          }
        } catch {
          setState(.failed(PayloadPrefetchFailure.reason(for: error)))
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
          if case .cancelled = state {
            return
          }
          if case .downloading(let current, let knownTotal) = state {
            completed = current
            total = knownTotal
          }
          if PayloadPrefetchFailure.isTransient(error) {
            if completed > furthestFailure {
              transientFailures = 0
              furthestFailure = completed
            }
            if transientFailures < retryDelays.count {
              let delay = retryDelays[transientFailures]
              transientFailures += 1
              setState(.paused(completed: completed, total: total))
              do {
                try await sleep(delay)
              } catch {
                break
              }
              continue
            }
          }
          setState(.failed(PayloadPrefetchFailure.reason(for: error)))
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
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var cancelEpoch: UInt64 = 0
    /// Work directories this orchestrator created for earlier generations.
    /// Another window's orchestrator shares the staging folder, so only
    /// these are ever reclaimed.
    private var ownedWorkDirectories: [URL] = []

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
        // Earlier generations of this orchestrator have been told to stop and
        // nothing they produce is published any more, so their directories
        // are reclaimed before the space check; otherwise every Try again
        // would count a failed run's parts as used. The generation check and
        // the removal share one lock hold, so a replaced task can never
        // delete its successor's directory.
        let stillCurrent = self.lock.withLock { () -> Bool in
          guard self.generation == generation else { return false }
          for directory in self.ownedWorkDirectories {
            try? FileManager.default.removeItem(at: directory)
          }
          self.ownedWorkDirectories.removeAll()
          return true
        }
        guard stillCurrent else { return }
        self.publish(.verifying, generation: generation)
        if self.matchesPinned(artifact, canonical) {
          self.publish(.verified, generation: generation)
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
          self.publish(
            .failed(PayloadPrefetchFailure.reason(for: error)), generation: generation)
          return
        }
        let owned = self.lock.withLock { () -> Bool in
          guard self.generation == generation else { return false }
          self.ownedWorkDirectories.append(work)
          return true
        }
        guard owned else {
          try? FileManager.default.removeItem(at: work)
          return
        }

        let controller = PayloadPrefetchController(
          network: self.makeNetwork(),
          freeSpace: self.makeFreeSpace(work),
          keepAwake: self.makeKeepAwake(),
          retainedBytes: { Self.regularFileBytes(in: work) },
          onState: { [weak self] state in
            self?.publish(state, generation: generation)
          }
        )
        let current = self.lock.withLock { () -> Bool in
          guard self.generation == generation else { return false }
          self.controller = controller
          return true
        }
        guard current else { return }

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
      let (current, epoch) = lock.withLock { () -> (PayloadPrefetchState, UInt64) in
        observers[token] = progress
        return (latest, cancelEpoch)
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
      // A watcher that stops watching leaves the shared download running.
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, any Error>) in
          lock.lock()
          if Task.isCancelled {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
          }
          if cancelEpoch != epoch {
            lock.unlock()
            continuation.resume(throwing: PayloadPrefetchError.cancelled)
            return
          }
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
            waiters[token] = continuation
            lock.unlock()
          }
        }
      } onCancel: {
        let waiter = lock.withLock { waiters.removeValue(forKey: token) }
        waiter?.resume(throwing: CancellationError())
      }
    }

    public func cancel() {
      lock.lock()
      latest = .idle
      runningDigest = nil
      cancelEpoch &+= 1
      let existing = controller
      controller = nil
      generation = UUID()
      let pending = Array(waiters.values)
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

    /// Checks and publishes under one lock hold, so a replaced or cancelled
    /// download can never write its result into the current one.
    private func publish(_ state: PayloadPrefetchState, generation: UUID) {
      let observers: [@Sendable (PayloadPrefetchState) -> Void]
      let pending: [CheckedContinuation<Void, any Error>]
      lock.lock()
      guard self.generation == generation else {
        lock.unlock()
        return
      }
      latest = state
      observers = Array(self.observers.values)
      switch state {
      case .verified:
        pending = Array(waiters.values)
        waiters.removeAll()
        lock.unlock()
        for waiter in pending {
          waiter.resume()
        }
      case .failed(let message):
        pending = Array(waiters.values)
        waiters.removeAll()
        lock.unlock()
        for waiter in pending {
          waiter.resume(throwing: PayloadPrefetchError.failed(message))
        }
      case .cancelled:
        pending = Array(waiters.values)
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

    static func regularFileBytes(in directory: URL) -> UInt64 {
      guard
        let entries = try? FileManager.default.contentsOfDirectory(
          at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
      else { return 0 }
      var total: UInt64 = 0
      for entry in entries {
        guard let values = try? entry.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
          values.isRegularFile == true, let size = values.fileSize, size > 0
        else { continue }
        total &+= UInt64(size)
      }
      return total
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
