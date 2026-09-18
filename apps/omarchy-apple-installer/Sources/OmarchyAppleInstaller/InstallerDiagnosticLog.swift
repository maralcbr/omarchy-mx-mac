import Darwin
import Foundation

/// Durable lifecycle evidence. Never accepts passwords, environment values,
/// command arguments, transcripts, or error descriptions.
public final class InstallerDiagnosticLog: @unchecked Sendable {
  public static let shared = InstallerDiagnosticLog()
  private let lock = NSLock()
  private var handle: FileHandle?
  public let fileURL: URL?

  public init(directory: URL? = nil) {
    let base =
      directory
      ?? (geteuid() == 0
        ? URL(fileURLWithPath: "/var/db/com.omarchy.mx.installer/diagnostics")
        : FileManager.default.homeDirectoryForCurrentUser
          .appendingPathComponent("Library/Logs/Omarchy MX Mac Installer"))
    let url = base.appendingPathComponent("install-\(UUID().uuidString).jsonl")
    do {
      try FileManager.default.createDirectory(
        at: base, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      var info = stat()
      guard lstat(base.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
        info.st_uid == geteuid(), info.st_mode & 0o077 == 0
      else {
        fileURL = nil
        return
      }
      let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
      guard fd >= 0 else {
        fileURL = nil
        return
      }
      handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
      fileURL = url
    } catch { fileURL = nil }
  }

  /// Event names are static call-site literals; only numeric error codes are saved.
  public func record(_ event: StaticString, code: Int? = nil) {
    lock.lock()
    defer { lock.unlock() }
    guard let handle else { return }
    var entry: [String: Any] = [
      "timestamp": ISO8601DateFormatter().string(from: Date()),
      "event": event.description, "pid": Int(getpid()), "uid": Int(geteuid()),
      "version": 1,
    ]
    if let code { entry["code"] = code }
    do {
      var data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
      data.append(10)
      try handle.write(contentsOf: data)
      try handle.synchronize()
    } catch { self.handle = nil }
  }
}
