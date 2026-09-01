import Foundation
import OmarchyAppleInstallerTrustCore

@main
enum OmarchyInstallerLifecycleProbe {
  static func main() throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try manager.createDirectory(
      at: directory,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    defer { try? manager.removeItem(at: directory) }

    let lockFile = directory.appendingPathComponent("instance.lock")
    let first = try InstallerAppInstanceLease.acquire(at: lockFile)
    do {
      _ = try InstallerAppInstanceLease.acquire(at: lockFile)
      throw ProbeError.duplicateLeaseAdmitted
    } catch InstallerAppInstanceLeaseError.alreadyRunning {
      // Expected.
    }

    first.release()
    let replacement = try InstallerAppInstanceLease.acquire(at: lockFile)
    replacement.release()

    try manager.removeItem(at: lockFile)
    let target = directory.appendingPathComponent("target")
    guard manager.createFile(atPath: target.path, contents: Data()) else {
      throw ProbeError.fixtureCreationFailed
    }
    try manager.createSymbolicLink(at: lockFile, withDestinationURL: target)
    do {
      _ = try InstallerAppInstanceLease.acquire(at: lockFile)
      throw ProbeError.symlinkLeaseAdmitted
    } catch InstallerAppInstanceLeaseError.unsafeLockPath {
      // Expected.
    }

    print("{\"result\":\"passed\",\"checks\":3}")
  }
}

private enum ProbeError: Error {
  case duplicateLeaseAdmitted
  case fixtureCreationFailed
  case symlinkLeaseAdmitted
}
