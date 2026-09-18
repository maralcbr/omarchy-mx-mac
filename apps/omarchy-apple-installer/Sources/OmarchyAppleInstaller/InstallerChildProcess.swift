import Darwin
import Foundation
import OmarchyInstallerSystem

/// Fixed executable/argument construction remains with each trusted caller.
/// Launches preserve the worker process group and inherit only standard I/O.
struct InstallerChildProcess {
  let identifier: pid_t

  static func launch(
    executable: URL, arguments: [String], environment: [String: String], directory: URL,
    input: FileHandle = .nullDevice, output: FileHandle = .nullDevice,
    error: FileHandle = .nullDevice, processGroup: pid_t = getpgrp()
  ) throws -> InstallerChildProcess {
    let args = [executable.path] + arguments
    let env = environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
    guard executable.isFileURL, directory.isFileURL,
      !executable.path.utf8.contains(0), !directory.path.utf8.contains(0),
      (args + env).allSatisfy({ !$0.utf8.contains(0) }),
      environment.keys.allSatisfy({ !$0.isEmpty && !$0.contains("=") })
    else { throw POSIXError(.EINVAL) }
    return try withCStrings(args) { argv in
      try withCStrings(env) { envp in
        var pid: pid_t = 0
        let result = omarchy_installer_spawn(
          &pid, executable.path, argv, envp, directory.path,
          input.fileDescriptor, output.fileDescriptor, error.fileDescriptor, processGroup)
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        return InstallerChildProcess(identifier: pid)
      }
    }
  }

  func wait() throws -> Int32 {
    var status: Int32 = 0
    let result = omarchy_installer_wait(identifier, &status)
    guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
    return status
  }

  private static func withCStrings<T>(
    _ values: [String], body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) throws -> T
  ) throws -> T {
    var strings = values.map { strdup($0) }
    defer { for string in strings { free(string) } }
    guard strings.allSatisfy({ $0 != nil }) else { throw POSIXError(.ENOMEM) }
    strings.append(nil)
    return try strings.withUnsafeBufferPointer { try body($0.baseAddress!) }
  }
}
