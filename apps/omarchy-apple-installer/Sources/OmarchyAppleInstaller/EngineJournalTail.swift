#if os(macOS)
  import Darwin
  import Foundation

  public enum EngineJournalLocator {
    /// Mirrors `PinnedAsahiEngineExecutor.preparePersistentJournal`:
    /// `<workingDirectory>/execution-journals/<bindingDigest hex>.jsonl`.
    /// A malformed digest resolves to nil, which disables streaming rather
    /// than guessing a path.
    public static func journalURL(
      workingDirectory: URL,
      bindingDigest: String
    ) -> URL? {
      guard let digest = SHA256Digest(rawValue: bindingDigest) else {
        return nil
      }
      return
        workingDirectory
        .appendingPathComponent("execution-journals", isDirectory: true)
        .appendingPathComponent("\(digest.hexadecimal).jsonl")
    }
  }

  /// Follows the root-owned execution journal while the engine runs and hands
  /// whole lines to a sink.
  ///
  /// Every read repeats the executor's fail-closed file checks (regular file,
  /// no group/other bits, expected owner, size ceiling) but tolerates a file
  /// that does not exist yet or is still growing. Anything unexpected stops
  /// forwarding silently: this channel is advisory, and the authoritative
  /// transcript is still read and validated by the executor and the app.
  public actor EngineJournalTailer {
    private let journalURL: URL
    private let expectedOwner: uid_t
    private let pollInterval: Duration
    private let maximumChunkBytes: Int
    private let sink: any EngineJournalProgressSink

    private var offset: UInt64 = 0
    private var task: Task<Void, Never>?
    private var disabled = false

    public init(
      journalURL: URL,
      expectedOwner: uid_t,
      pollInterval: Duration = .milliseconds(250),
      maximumChunkBytes: Int = 262_144,
      sink: any EngineJournalProgressSink
    ) {
      self.journalURL = journalURL
      self.expectedOwner = expectedOwner
      self.pollInterval = pollInterval
      self.maximumChunkBytes = max(1, maximumChunkBytes)
      self.sink = sink
    }

    public func start() {
      guard task == nil else {
        return
      }
      task = Task { [pollInterval] in
        while !Task.isCancelled {
          self.drain()
          do {
            try await Task.sleep(for: pollInterval)
          } catch {
            return
          }
        }
      }
    }

    /// Cancels the poll loop, then performs one final drain so the last lines
    /// written before the engine exited are not lost.
    public func stop() async {
      task?.cancel()
      _ = await task?.value
      task = nil
      drain()
    }

    /// Always replays from offset 0 on the first drain, which is what makes a
    /// reattach trivial: a fresh connection simply receives the whole journal
    /// again, and the app replaces its buffer when it sees sequence 1.
    private func drain() {
      guard !disabled else {
        return
      }
      let descriptor = Darwin.open(
        journalURL.path,
        O_RDONLY | O_CLOEXEC | O_NOFOLLOW
      )
      guard descriptor >= 0 else {
        return
      }
      defer { Darwin.close(descriptor) }

      var status = stat()
      guard fstat(descriptor, &status) == 0,
        (status.st_mode & S_IFMT) == S_IFREG,
        status.st_mode & 0o077 == 0,
        status.st_uid == expectedOwner,
        status.st_size <= PinnedAsahiEngineExecutor.maximumTranscriptBytes
      else {
        disabled = true
        return
      }

      let size = UInt64(max(0, status.st_size))
      guard size > offset else {
        return
      }
      guard Darwin.lseek(descriptor, off_t(offset), SEEK_SET) >= 0 else {
        disabled = true
        return
      }

      let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
      guard let appended = try? handle.read(upToCount: Int(size - offset)),
        !appended.isEmpty
      else {
        return
      }
      guard let lastNewline = appended.lastIndex(of: 0x0A) else {
        return
      }

      let completeLines = appended[appended.startIndex...lastNewline]
      offset += UInt64(completeLines.count)
      forward(Data(completeLines))
    }

    /// Forwards at most `maximumChunkBytes` per message, always splitting on a
    /// line boundary. A single line longer than the cap is forwarded alone.
    private func forward(_ lines: Data) {
      var remaining = lines[...]
      while !remaining.isEmpty {
        if remaining.count <= maximumChunkBytes {
          sink.journalDidAppend(Data(remaining))
          return
        }
        let window = remaining.prefix(maximumChunkBytes)
        guard let boundary = window.lastIndex(of: 0x0A) else {
          guard let nextBoundary = remaining.firstIndex(of: 0x0A) else {
            return
          }
          let single = remaining[remaining.startIndex...nextBoundary]
          sink.journalDidAppend(Data(single))
          remaining = remaining[remaining.index(after: nextBoundary)...]
          continue
        }
        let chunk = remaining[remaining.startIndex...boundary]
        sink.journalDidAppend(Data(chunk))
        remaining = remaining[remaining.index(after: boundary)...]
      }
    }
  }
#endif
