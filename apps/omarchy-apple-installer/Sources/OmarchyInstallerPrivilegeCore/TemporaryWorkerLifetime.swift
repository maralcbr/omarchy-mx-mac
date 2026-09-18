import Foundation

/// The worker owns this state and serializes access to it. XPC connection loss
/// is deliberately not a retirement signal: every request uses a new connection.
/// A timer may retire an idle worker, but must never terminate disk work.
public struct TemporaryWorkerLifetime: Sendable {
  public enum AdmissionError: Error, Equatable, Sendable {
    case busy
    case retiring
    case invalidOperation
  }

  /// Only the request that acquired admission may complete it. In particular,
  /// a late completion from an earlier request cannot release newer work.
  public struct Operation: Equatable, Sendable {
    fileprivate let identifier = UUID()
  }

  private enum State: Sendable {
    case idle(until: ContinuousClock.Instant)
    case active(Operation, retireAfterCompletion: Bool)
    case retiring
  }

  private let idleTimeout: Duration
  private var state: State

  public init(now: ContinuousClock.Instant, idleTimeout: Duration = .seconds(300)) {
    precondition(idleTimeout > .zero)
    self.idleTimeout = idleTimeout
    state = .idle(until: now.advanced(by: idleTimeout))
  }

  /// Call before accepting an operation, including credential validation and
  /// removal previews. Rejected credentials complete normally here so the
  /// same authenticated worker can accept a corrected request.
  public mutating func begin(now: ContinuousClock.Instant) throws -> Operation {
    switch state {
    case .active:
      throw AdmissionError.busy
    case .retiring:
      throw AdmissionError.retiring
    case .idle(let deadline):
      guard now < deadline else {
        state = .retiring
        throw AdmissionError.retiring
      }
      let operation = Operation()
      state = .active(operation, retireAfterCompletion: false)
      return operation
    }
  }

  /// The owner must call this only after its executor AND owned child processes
  /// have finished. This policy does not itself prove process-tree retirement
  /// or provide machine-wide exclusion; those are execution-layer obligations.
  public mutating func complete(_ operation: Operation, now: ContinuousClock.Instant) throws {
    guard case .active(let current, let retiring) = state, current == operation else {
      throw AdmissionError.invalidOperation
    }
    state = retiring ? .retiring : .idle(until: now.advanced(by: idleTimeout))
  }

  /// Closing prevents another request immediately, but defers worker exit until
  /// admitted work completes. It must not be translated into SMJobRemove while
  /// an operation or one of its children is still running.
  public mutating func requestRetirement() {
    switch state {
    case .active(let operation, _):
      state = .active(operation, retireAfterCompletion: true)
    case .idle, .retiring:
      state = .retiring
    }
  }

  /// Called by the worker's independent idle timer. Once true, admission is
  /// permanently closed; a late request cannot resurrect this worker.
  public mutating func shouldRetire(now: ContinuousClock.Instant) -> Bool {
    switch state {
    case .active:
      return false
    case .idle(let deadline):
      guard now >= deadline else { return false }
      state = .retiring
      return true
    case .retiring:
      return true
    }
  }
}
