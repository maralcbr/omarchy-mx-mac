import Foundation
import XCTest

@testable import OmarchyAppleInstallerTrustCore

final class InstallerAppInstanceLeaseTests: XCTestCase {
  func testSecondLeaseFailsWhileFirstLeaseIsHeld() throws {
    let lockFile = try temporaryLockFile()
    let first = try InstallerAppInstanceLease.acquire(at: lockFile)

    XCTAssertThrowsError(try InstallerAppInstanceLease.acquire(at: lockFile)) { error in
      XCTAssertEqual(error as? InstallerAppInstanceLeaseError, .alreadyRunning)
    }

    withExtendedLifetime(first) {}
  }

  func testReleasedLeaseCanBeAcquiredAgain() throws {
    let lockFile = try temporaryLockFile()
    let first = try InstallerAppInstanceLease.acquire(at: lockFile)
    first.release()

    let second = try InstallerAppInstanceLease.acquire(at: lockFile)
    withExtendedLifetime(second) {}
  }

  func testSymlinkLockFileFailsClosed() throws {
    let directory = try temporaryDirectory()
    let target = directory.appendingPathComponent("target")
    let link = directory.appendingPathComponent("instance.lock")
    XCTAssertTrue(FileManager.default.createFile(atPath: target.path, contents: Data()))
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    XCTAssertThrowsError(try InstallerAppInstanceLease.acquire(at: link)) { error in
      XCTAssertEqual(error as? InstallerAppInstanceLeaseError, .unsafeLockPath)
    }
  }

  private func temporaryLockFile() throws -> URL {
    try temporaryDirectory().appendingPathComponent("instance.lock")
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    addTeardownBlock {
      try? FileManager.default.removeItem(at: directory)
    }
    return directory
  }
}
