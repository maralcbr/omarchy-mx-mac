import Darwin
import Foundation
import OmarchyInstallerSystem

public enum InstallerAppInstanceLeaseError: Error, Equatable, Sendable {
  case alreadyRunning
  case unsafeLockPath
  case systemCallFailed
}

/// A per-user advisory lease that prevents automation or `open -n` from
/// accumulating installer processes. The kernel releases the lease if the app
/// exits or crashes, so a stale PID cannot strand future launches.
public final class InstallerAppInstanceLease {
  private var descriptor: Int32?

  private init(descriptor: Int32) {
    self.descriptor = descriptor
  }

  deinit {
    release()
  }

  public static func defaultLockFileURL() throws -> URL {
    guard
      let caches = FileManager.default.urls(
        for: .cachesDirectory,
        in: .userDomainMask
      ).first
    else {
      throw InstallerAppInstanceLeaseError.unsafeLockPath
    }
    return
      caches
      .appendingPathComponent("com.omarchy.mx.installer", isDirectory: true)
      .appendingPathComponent("instance.lock", isDirectory: false)
  }

  public static func acquire(at lockFile: URL) throws -> InstallerAppInstanceLease {
    guard lockFile.isFileURL, lockFile.path.hasPrefix("/") else {
      throw InstallerAppInstanceLeaseError.unsafeLockPath
    }

    let directory = lockFile.deletingLastPathComponent()
    try ensurePrivateDirectory(directory)

    let descriptor = Darwin.open(
      lockFile.path,
      O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
      mode_t(S_IRUSR | S_IWUSR)
    )
    guard descriptor >= 0 else {
      if errno == ELOOP {
        throw InstallerAppInstanceLeaseError.unsafeLockPath
      }
      throw InstallerAppInstanceLeaseError.systemCallFailed
    }

    do {
      try validateLockFile(descriptor)
      guard omarchy_installer_flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
        if errno == EWOULDBLOCK || errno == EAGAIN {
          throw InstallerAppInstanceLeaseError.alreadyRunning
        }
        throw InstallerAppInstanceLeaseError.systemCallFailed
      }
      return InstallerAppInstanceLease(descriptor: descriptor)
    } catch {
      Darwin.close(descriptor)
      throw error
    }
  }

  public func release() {
    guard let descriptor else { return }
    self.descriptor = nil
    _ = omarchy_installer_flock(descriptor, LOCK_UN)
    Darwin.close(descriptor)
  }

  private static func ensurePrivateDirectory(_ directory: URL) throws {
    var information = stat()
    if Darwin.lstat(directory.path, &information) != 0 {
      guard errno == ENOENT else {
        throw InstallerAppInstanceLeaseError.systemCallFailed
      }
      guard Darwin.mkdir(directory.path, mode_t(0o700)) == 0 || errno == EEXIST else {
        throw InstallerAppInstanceLeaseError.systemCallFailed
      }
      guard Darwin.lstat(directory.path, &information) == 0 else {
        throw InstallerAppInstanceLeaseError.systemCallFailed
      }
    }

    let fileType = information.st_mode & mode_t(S_IFMT)
    let unsafePermissions = information.st_mode & mode_t(S_IWGRP | S_IWOTH)
    guard
      fileType == mode_t(S_IFDIR),
      information.st_uid == Darwin.getuid(),
      unsafePermissions == 0
    else {
      throw InstallerAppInstanceLeaseError.unsafeLockPath
    }
  }

  private static func validateLockFile(_ descriptor: Int32) throws {
    var information = stat()
    guard Darwin.fstat(descriptor, &information) == 0 else {
      throw InstallerAppInstanceLeaseError.systemCallFailed
    }
    let fileType = information.st_mode & mode_t(S_IFMT)
    let unsafePermissions = information.st_mode & mode_t(S_IWGRP | S_IWOTH)
    guard
      fileType == mode_t(S_IFREG),
      information.st_uid == Darwin.getuid(),
      unsafePermissions == 0
    else {
      throw InstallerAppInstanceLeaseError.unsafeLockPath
    }
  }
}
