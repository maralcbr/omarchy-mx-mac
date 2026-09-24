#if os(macOS)
  import Darwin
  import Foundation

  /// Why the pinned engine stopped, as far as the privileged helper can tell
  /// from the engine's final exception line. Only a fixed set of exact engine
  /// messages maps to a named reason; everything else is `unclassified`.
  ///
  /// The reason chooses wording and offers in the app. It never feeds a
  /// security decision: a re-plan it offers runs the full signed plan flow,
  /// and the disk-unchanged claim comes from the root-owned journal, not from
  /// engine output.
  public enum EngineFailureReason: Int, Equatable, Sendable, CaseIterable {
    case unclassified = 0
    /// The approved Linux allocation no longer fits what macOS can give up
    /// (`approved extent changed`, issue #105).
    case approvedSpaceChanged = 1
    /// The disk or partition layout changed after the plan was approved.
    case diskLayoutChanged = 2
    /// The engine refused this Mac model.
    case deviceUnsupported = 3
    /// The plan, request, or identity failed an integrity check.
    case planIntegrity = 4

    /// Exact final-exception messages raised before the first mutation by
    /// `omarchy_execution.admit_execution`, `omarchy_runtime` and the Asahi
    /// adapter preflight. Anything not listed stays unclassified.
    static func classify(exception: String, message: String) -> EngineFailureReason {
      guard knownExceptionTypes.contains(exception) else {
        return .unclassified
      }
      switch message {
      case "approved extent changed", "approved extent is too small",
        "approved extent is smaller than Asahi minimum":
        return .approvedSpaceChanged
      case "disk layout changed", "system store changed",
        "approved candidate is unavailable", "system store changed during resume",
        "inventory changed during resume":
        return .diskLayoutChanged
      case "device is explicitly unsupported":
        return .deviceUnsupported
      case "plan digest mismatch", "helper environment binding mismatch",
        "request identity mismatch":
        return .planIntegrity
      default:
        return .unclassified
      }
    }

    private static let knownExceptionTypes: Set<String> = [
      "ExecutionAdmissionError", "EngineRuntimeError", "AsahiAdapterError",
      "ContractError",
    ]
  }

  /// The part of an engine failure that may leave the privileged helper: a
  /// typed reason, the exit status, whether the journal proves that nothing
  /// was changed, and one short redacted summary line for diagnostics.
  public struct EngineFailureNotice: Equatable, Sendable, CustomStringConvertible {
    public static let maximumSummaryCharacters = 200

    public let reason: EngineFailureReason
    public let exitStatus: Int32
    /// True only when the run's root-owned journal holds no event, checkpoint
    /// or completion record, i.e. no disk mutation began. Every engine
    /// mutation stage journals its start event before it touches the disk.
    public let diskUnchanged: Bool
    /// The engine's final exception line after redaction, printable ASCII,
    /// display and diagnostics only.
    public let summary: String

    public init(
      reason: EngineFailureReason,
      exitStatus: Int32,
      diskUnchanged: Bool,
      summary: String
    ) {
      self.reason = reason
      self.exitStatus = exitStatus
      self.diskUnchanged = diskUnchanged
      self.summary = Self.sanitizedSummary(summary)
    }

    public var description: String {
      "engineFailed(reason: \(reason), exit: \(exitStatus), diskUnchanged: \(diskUnchanged)"
        + (summary.isEmpty ? ")" : ", summary: \"\(summary)\")")
    }

    /// Printable ASCII only, one line, bounded. Applied on both sides of XPC
    /// so a malformed or hostile value can never carry control characters or
    /// unbounded text into the UI or logs.
    static func sanitizedSummary(
      _ value: String,
      limit: Int? = EngineFailureNotice.maximumSummaryCharacters
    ) -> String {
      var result = ""
      for scalar in value.unicodeScalars {
        if let limit, result.count >= limit { break }
        if scalar.value >= 0x20 && scalar.value < 0x7F {
          result.unicodeScalars.append(scalar)
        } else if scalar == "\t" {
          result.append(" ")
        } else if scalar == "\n" || scalar == "\r" {
          break
        }
      }
      return result.trimmingCharacters(in: .whitespaces)
    }
  }

  /// A failed engine run as the privileged helper sees it: the notice that may
  /// cross XPC plus the redacted stderr tail, which stays in the helper's
  /// root-only diagnostics directory.
  public struct EngineFailureReport: Equatable, Sendable {
    public let notice: EngineFailureNotice
    public let redactedStandardErrorTail: String

    public init(notice: EngineFailureNotice, redactedStandardErrorTail: String) {
      self.notice = notice
      self.redactedStandardErrorTail = redactedStandardErrorTail
    }
  }

  /// Turns captured engine stderr into something safe to keep.
  ///
  /// Why the engine's stderr should already be credential-free: the engine
  /// reads the machine-owner password once from stdin, hands it to macOS
  /// tools on their stdin (`--stdinpass`, their stderr discarded), and never
  /// prints it. Python tracebacks show source lines and exception messages,
  /// not local values. This redactor is defense in depth for a future engine
  /// change or an unexpected library message:
  /// - every occurrence of the exact password bytes is removed before the
  ///   bytes are decoded;
  /// - a tail that was truncated drops its first, partial line, so a password
  ///   split by the cut cannot survive as a fragment (the engine rejects
  ///   passwords containing a newline);
  /// - Python bytes literals (the engine holds the password as bytes) and
  ///   `key=value` / `key: value` pairs whose key names a credential are
  ///   replaced;
  /// - terminal escapes and control characters are removed.
  public enum EngineStandardErrorRedactor {
    public static let redaction = "[redacted]"
    /// The persisted tail after redaction.
    public static let maximumTailCharacters = 16_384

    public static func redact(
      _ captured: Data,
      truncated: Bool,
      secrets: [Data]
    ) -> String {
      let replacement = Data(redaction.utf8)
      var bytes = captured
      for secret in secrets where !secret.isEmpty {
        bytes = replacingOccurrences(of: secret, in: bytes, with: replacement)
      }
      var text = String(decoding: bytes, as: UTF8.self)
      if truncated, let newline = text.firstIndex(of: "\n") {
        text = String(text[text.index(after: newline)...])
      } else if truncated {
        text = ""
      }
      text = removingTerminalEscapes(text)
      // Escape removal can join a password that escapes had split, so the
      // exact-secret pass runs again on the cleaned text, for the secret as
      // given and as the same cleaning would leave it.
      for secret in secrets where !secret.isEmpty {
        let raw = String(decoding: secret, as: UTF8.self)
        for form in Set([raw, removingTerminalEscapes(raw)]) where !form.isEmpty {
          text = text.replacingOccurrences(of: form, with: redaction)
        }
      }
      text = text.replacingOccurrences(
        of: #"\bb(['"])(?:\\.|(?!\1).)*\1"#,
        with: "b'\(redaction)'",
        options: .regularExpression
      )
      // A credential-named key followed by `=` or `:` loses everything after
      // the separator to the end of the line, so multiword values
      // (`Authorization: Bearer x`) and escaped quotes cannot leave a tail.
      text = text.replacingOccurrences(
        of:
          #"(?im)\b([A-Za-z0-9_-]*(?:password|passwd|passphrase|secret|token|credential|api[_-]?key|authorization|bearer|cookie)[A-Za-z0-9_-]*)(\s*[=:]).*$"#,
        with: "$1$2 \(redaction)",
        options: .regularExpression
      )
      text = text.replacingOccurrences(
        // Schemes are case-insensitive (RFC 9110 11.1); over-redacting a
        // word that follows "basic" in ordinary text is the accepted cost.
        of: #"(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]+"#,
        with: "$1 \(redaction)",
        options: .regularExpression
      )
      if text.count > maximumTailCharacters {
        text = String(text.suffix(maximumTailCharacters))
        if let newline = text.firstIndex(of: "\n") {
          text = String(text[text.index(after: newline)...])
        }
      }
      return text
    }

    /// The one line that may leave the helper. It is normalized to the
    /// summary's printable-ASCII form first and redacted after that, so the
    /// normalization cannot rejoin a secret that other characters had split.
    public static func summary(from line: String, secrets: [Data]) -> String {
      // Normalize without truncating: a cut before redaction could leave most
      // of a secret that no longer matches in full. The limit comes last.
      var text = EngineFailureNotice.sanitizedSummary(line, limit: nil)
      for secret in secrets where !secret.isEmpty {
        let raw = String(decoding: secret, as: UTF8.self)
        for form in Set([raw, EngineFailureNotice.sanitizedSummary(raw, limit: nil)])
        where !form.isEmpty {
          text = text.replacingOccurrences(of: form, with: redaction)
        }
      }
      text = redact(Data(text.utf8), truncated: false, secrets: [])
      return EngineFailureNotice.sanitizedSummary(text)
    }

    /// The last Python exception line (`module.Name: message`) of an already
    /// redacted stderr text, split into the bare class name and the message.
    public static func finalException(in redacted: String) -> (
      line: String, exception: String, message: String
    )? {
      for rawLine in redacted.split(separator: "\n").reversed() {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { continue }
        guard
          let match = line.firstMatch(
            of: /^([A-Za-z_][A-Za-z0-9_.]*): (.+)$/
          )
        else {
          return nil
        }
        let qualified = String(match.1)
        let exception = qualified.split(separator: ".").last.map(String.init) ?? qualified
        guard
          exception.hasSuffix("Error") || exception.hasSuffix("Exception")
            || exception.hasSuffix("State")
        else {
          return nil
        }
        return (line, exception, String(match.2))
      }
      return nil
    }

    static func removingTerminalEscapes(_ text: String) -> String {
      let withoutEscapes = text.replacingOccurrences(
        of: #"\x1B\[[0-9;?]*[ -/]*[@-~]"#,
        with: "",
        options: .regularExpression
      )
      var result = String.UnicodeScalarView()
      for scalar in withoutEscapes.unicodeScalars
      where scalar == "\n" || scalar == "\t"
        || (scalar.value >= 0x20 && scalar.value != 0x7F
          && !(0x80...0x9F).contains(scalar.value)
          && scalar.properties.generalCategory != .format)
      {
        result.append(scalar)
      }
      return String(result)
    }

    static func replacingOccurrences(
      of needle: Data,
      in haystack: Data,
      with replacement: Data
    ) -> Data {
      guard !needle.isEmpty, haystack.count >= needle.count else {
        return haystack
      }
      var output = Data()
      output.reserveCapacity(haystack.count)
      var index = haystack.startIndex
      while index < haystack.endIndex {
        if let range = haystack.range(of: needle, in: index..<haystack.endIndex) {
          output.append(haystack[index..<range.lowerBound])
          output.append(replacement)
          index = range.upperBound
        } else {
          output.append(haystack[index..<haystack.endIndex])
          break
        }
      }
      return output
    }
  }

  /// Keeps only the last `limit` bytes read from a pipe. A dispatch read
  /// source drains its own duplicate of the descriptor without blocking, so
  /// the engine can never stall on a full pipe. Each callback reads a bounded
  /// amount and stops once cancelled, and cancelling closes the descriptor,
  /// so a stray child holding stderr open, even one that keeps writing,
  /// cannot keep a thread or descriptor alive past `finish` or `cancel`.
  final class BoundedStandardErrorCollector: @unchecked Sendable {
    static let defaultLimit = 65_536
    static let maximumBytesPerCallback = 262_144

    enum SetupError: Error { case descriptorUnavailable }

    private let lock = NSLock()
    private let limit: Int
    private var buffer = Data()
    private var truncated = false
    private var source: (any DispatchSourceRead)?
    private let drained = DispatchSemaphore(value: 0)
    private let queue = DispatchQueue(label: "com.omarchy.mx.installer.engine-stderr")

    init(limit: Int = BoundedStandardErrorCollector.defaultLimit) {
      self.limit = limit
    }

    deinit {
      source?.cancel()
    }

    /// Call before launching the engine: a failure here must stop the launch
    /// rather than leave a running engine with nobody draining its stderr.
    func start(reading handle: FileHandle) throws {
      let descriptor = dup(handle.fileDescriptor)
      guard descriptor >= 0 else { throw SetupError.descriptorUnavailable }
      let flags = fcntl(descriptor, F_GETFL)
      guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0,
        flags >= 0,
        fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0
      else {
        Darwin.close(descriptor)
        throw SetupError.descriptorUnavailable
      }
      let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
      source.setEventHandler { [weak self, weak source] in
        var chunk = [UInt8](repeating: 0, count: 16_384)
        var consumed = 0
        while consumed < Self.maximumBytesPerCallback, source?.isCancelled == false {
          let count = chunk.withUnsafeMutableBytes {
            Darwin.read(descriptor, $0.baseAddress, $0.count)
          }
          if count > 0 {
            consumed += count
            self?.append(Data(chunk[0..<count]))
          } else if count < 0 && errno == EINTR {
            continue
          } else if count < 0 && errno == EAGAIN {
            return
          } else {
            source?.cancel()
            return
          }
        }
      }
      source.setCancelHandler { [drained] in
        Darwin.close(descriptor)
        drained.signal()
      }
      lock.withLock { self.source = source }
      source.resume()
    }

    /// Waits for EOF until the deadline, then cancels the reader, and returns
    /// the retained tail.
    func finish(timeout: DispatchTime = .now() + 5) -> (data: Data, truncated: Bool) {
      if let source = lock.withLock({ self.source }) {
        if drained.wait(timeout: timeout) == .timedOut {
          source.cancel()
          drained.wait()
        }
        lock.withLock { self.source = nil }
      }
      return lock.withLock { (buffer, truncated) }
    }

    /// Stops reading now; safe to call more than once.
    func cancel() {
      _ = finish(timeout: .now())
    }

    func append(_ chunk: Data) {
      lock.withLock {
        buffer.append(chunk)
        if buffer.count > limit {
          buffer = Data(buffer.suffix(limit))
          truncated = true
        }
      }
    }
  }

  /// Root-only, credential-free diagnostics next to the helper's journals:
  /// `<helper working directory>/diagnostics/engine-failure-<time>.log`.
  public enum EngineFailureDiagnosticsStore {
    public static let directoryName = "diagnostics"
    static let maximumRetainedReports = 20

    @discardableResult
    public static func write(
      _ report: EngineFailureReport,
      operation: String,
      in workingDirectory: URL,
      now: Date = Date()
    ) -> URL? {
      let directory = workingDirectory.appendingPathComponent(
        directoryName, isDirectory: true)
      var status = stat()
      if lstat(directory.path, &status) != 0 {
        guard errno == ENOENT, mkdir(directory.path, S_IRWXU) == 0 else { return nil }
      }
      guard lstat(directory.path, &status) == 0,
        (status.st_mode & S_IFMT) == S_IFDIR,
        status.st_uid == geteuid(),
        status.st_mode & 0o077 == 0
      else {
        return nil
      }
      let url = directory.appendingPathComponent(
        "engine-failure-\(timestamp(now)).log", isDirectory: false)
      let descriptor = Darwin.open(
        url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
      guard descriptor >= 0 else { return nil }
      let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
      let notice = report.notice
      let body = """
        Omarchy installer engine failure
        time: \(timestamp(now))
        operation: \(operation)
        reason: \(notice.reason)
        exit status: \(notice.exitStatus)
        disk unchanged (journal has no mutation record): \(notice.diskUnchanged)
        summary: \(notice.summary)
        --- engine stderr (redacted tail) ---
        \(report.redactedStandardErrorTail)

        """
      do {
        try handle.write(contentsOf: Data(body.utf8))
        try handle.synchronize()
      } catch {
        return nil
      }
      pruneOldReports(in: directory)
      return url
    }

    public static func timestamp(_ date: Date) -> String {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }

    static func pruneOldReports(in directory: URL) {
      guard
        let entries = try? FileManager.default.contentsOfDirectory(
          at: directory, includingPropertiesForKeys: nil)
      else { return }
      let reports = entries.filter {
        $0.lastPathComponent.hasPrefix("engine-failure-") && $0.pathExtension == "log"
      }.sorted { $0.lastPathComponent < $1.lastPathComponent }
      guard reports.count > maximumRetainedReports else { return }
      for stale in reports.prefix(reports.count - maximumRetainedReports) {
        try? FileManager.default.removeItem(at: stale)
      }
    }
  }

  /// The app's copy, in the person's own logs, of what the helper sent back:
  /// `~/Library/Logs/Omarchy MX Mac Installer/engine-failure-<time>.log`.
  /// It holds only the XPC notice, which is already credential-free.
  public enum EngineFailureUserLog {
    public static let directoryName = "Omarchy MX Mac Installer"

    public static func defaultDirectory() -> URL? {
      FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Logs", isDirectory: true)
        .appendingPathComponent(directoryName, isDirectory: true)
    }

    @discardableResult
    public static func write(
      _ notice: EngineFailureNotice,
      operation: String,
      in directory: URL? = defaultDirectory(),
      now: Date = Date()
    ) -> URL? {
      guard let directory else { return nil }
      do {
        try FileManager.default.createDirectory(
          at: directory, withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700])
      } catch {
        return nil
      }
      let stamp = EngineFailureDiagnosticsStore.timestamp(now)
      let url = directory.appendingPathComponent("engine-failure-\(stamp).log")
      let body = """
        Omarchy installer engine failure
        time: \(stamp)
        operation: \(operation)
        reason: \(notice.reason)
        exit status: \(notice.exitStatus)
        disk unchanged (journal has no mutation record): \(notice.diskUnchanged)
        summary: \(notice.summary)
        The redacted engine output is kept by the installation service in
        \(InstallerProductIdentity.helperWorkingDirectory)/\(EngineFailureDiagnosticsStore.directoryName) (administrator access).

        """
      let descriptor = Darwin.open(
        url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
      guard descriptor >= 0 else { return nil }
      let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
      guard (try? handle.write(contentsOf: Data(body.utf8))) != nil else { return nil }
      EngineFailureDiagnosticsStore.pruneOldReports(in: directory)
      return url
    }
  }
#endif
