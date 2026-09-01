#if os(macOS)
  import Foundation

  /// Advisory, one-way progress channel from the privileged helper to the app.
  ///
  /// The helper exports nothing new on the authoritative path:
  /// `ClosedEngineXPCService.submit` is unchanged and still carries the sealed
  /// transcript on its reply. This callback interface is opportunistic — a peer
  /// that does not implement it simply never receives a chunk, and the run is
  /// unaffected.
  @objc public protocol ClosedEngineProgressClient {
    /// One or more complete, newline-terminated NDJSON envelope lines in file
    /// order. Fire-and-forget: no reply block, so XPC never queues replies.
    func engineJournalDidAppend(_ completeLines: Data)
  }

  public protocol EngineJournalProgressSink: Sendable {
    func journalDidAppend(_ completeLines: Data)
  }

  /// Bridges the daemon-side tailer to the connected client proxy.
  public final class XPCJournalProgressSink: EngineJournalProgressSink,
    @unchecked Sendable
  {
    private let client: any ClosedEngineProgressClient

    public init(client: any ClosedEngineProgressClient) {
      self.client = client
    }

    public func journalDidAppend(_ completeLines: Data) {
      client.engineJournalDidAppend(completeLines)
    }
  }

  /// App-side exported object: hands forwarded lines to the UI closure.
  public final class EngineProgressClientRelay: NSObject,
    ClosedEngineProgressClient
  {
    private let handler: @Sendable (Data) -> Void

    public init(handler: @escaping @Sendable (Data) -> Void) {
      self.handler = handler
    }

    public func engineJournalDidAppend(_ completeLines: Data) {
      handler(completeLines)
    }
  }
#endif
