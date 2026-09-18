import Darwin
import Foundation
import OmarchyInstallerSystem

public enum InstallerExecutionLeaseError: Error, Equatable, Sendable {
  case busy
  case unsafePath
  case invalidRecord
  case invalidProcessGroup
  case systemCallFailed
}

/// One lease per worker lifetime, acquired before the worker accepts requests.
/// All mutating children must inherit this worker's process group. The durable
/// record closes the gap between worker death (which releases flock) and the
/// last child's exit. Never unlink or replace the lock file during cleanup.
public final class InstallerExecutionLease: Sendable {
  private let descriptor: Int32

  private struct Record: Codable {
    let version: Int
    let boot: UUID
    let processGroup: Int32
  }

  private init(descriptor: Int32) { self.descriptor = descriptor }

  deinit { Darwin.close(descriptor) }

  public static func acquire() throws -> InstallerExecutionLease {
    guard geteuid() == 0 else { throw InstallerExecutionLeaseError.unsafePath }
    return try acquire(
      directory: URL(fileURLWithPath: InstallerProductIdentity.helperWorkingDirectory),
      owner: 0, processGroup: getpgrp(), processID: getpid(), boot: bootSession(),
      groupExists: groupExists)
  }

  static func acquire(
    directory: URL, owner: uid_t, processGroup: Int32, processID: Int32, boot: UUID,
    groupExists: (Int32) throws -> Bool
  ) throws -> InstallerExecutionLease {
    // launchd gives each worker its own group. Refuse a launch arrangement that
    // could include unrelated processes or escape the recorded group.
    guard processGroup > 1, processGroup == processID else {
      throw InstallerExecutionLeaseError.invalidProcessGroup
    }
    let parent = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard parent >= 0 else { throw InstallerExecutionLeaseError.unsafePath }
    defer { Darwin.close(parent) }
    var info = stat()
    guard fstat(parent, &info) == 0, info.st_uid == owner,
      info.st_mode & 0o077 == 0
    else { throw InstallerExecutionLeaseError.unsafePath }
    let file = openat(parent, "execution.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard file >= 0 else { throw InstallerExecutionLeaseError.unsafePath }
    do {
      guard fstat(file, &info) == 0, info.st_uid == owner,
        info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0, info.st_nlink == 1
      else { throw InstallerExecutionLeaseError.unsafePath }
      guard omarchy_installer_flock(file, LOCK_EX | LOCK_NB) == 0 else {
        if errno == EWOULDBLOCK || errno == EAGAIN { throw InstallerExecutionLeaseError.busy }
        throw InstallerExecutionLeaseError.systemCallFailed
      }
      // The size is read after acquiring the lock: another owner could have
      // completed its record between our open and flock.
      guard fstat(file, &info) == 0, (0...512).contains(info.st_size) else {
        throw InstallerExecutionLeaseError.invalidRecord
      }
      if info.st_size > 0 {
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
        guard pread(file, &bytes, bytes.count, 0) == bytes.count,
          let record = try? JSONDecoder().decode(Record.self, from: Data(bytes)),
          record.version == 1, record.processGroup > 1
        else { throw InstallerExecutionLeaseError.invalidRecord }
        if record.boot == boot, try groupExists(record.processGroup) {
          throw InstallerExecutionLeaseError.busy
        }
      }
      let data = try JSONEncoder().encode(
        Record(version: 1, boot: boot, processGroup: processGroup))
      let written = data.withUnsafeBytes { pwrite(file, $0.baseAddress, $0.count, 0) }
      guard written == data.count, ftruncate(file, off_t(data.count)) == 0,
        fsync(file) == 0, fsync(parent) == 0
      else { throw InstallerExecutionLeaseError.systemCallFailed }
      return InstallerExecutionLease(descriptor: file)
    } catch {
      Darwin.close(file)
      throw error
    }
  }

  public func requireIdleGroup() throws {
    if try Self.hasChildren() { throw InstallerExecutionLeaseError.busy }
  }

  /// A direct child's exit is not enough: grandchildren may still be using
  /// imported files or mutating the disk. Keep the current request admitted.
  static func waitForChildren() {
    // Uncertain enumeration keeps both admission and execution files intact.
    // A later successful observation can finish draining; an error cannot.
    while (try? hasChildren()) != false { Thread.sleep(forTimeInterval: 0.05) }
  }

  private static func hasChildren() throws -> Bool {
    var present: Int32 = 0
    guard omarchy_installer_group_has_children(&present) == 0 else {
      throw InstallerExecutionLeaseError.systemCallFailed
    }
    return present != 0
  }

  static func groupExists(_ group: Int32) throws -> Bool {
    guard group > 1 else { throw InstallerExecutionLeaseError.invalidProcessGroup }
    if kill(-group, 0) == 0 { return true }
    if errno == ESRCH { return false }
    if errno == EPERM { return true }
    throw InstallerExecutionLeaseError.systemCallFailed
  }

  private static func bootSession() throws -> UUID {
    var bytes = [CChar](repeating: 0, count: 128)
    var count = bytes.count
    guard sysctlbyname("kern.bootsessionuuid", &bytes, &count, nil, 0) == 0,
      count > 1, count <= bytes.count, bytes[count - 1] == 0,
      let uuid = UUID(
        uuidString: String(
          decoding: bytes.prefix(count - 1).map { UInt8(bitPattern: $0) }, as: UTF8.self))
    else { throw InstallerExecutionLeaseError.systemCallFailed }
    return uuid
  }
}
