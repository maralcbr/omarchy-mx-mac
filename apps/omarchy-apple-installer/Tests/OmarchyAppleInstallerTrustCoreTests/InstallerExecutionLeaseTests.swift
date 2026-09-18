import Darwin
import Foundation
import XCTest

@testable import OmarchyAppleInstallerTrustCore

final class InstallerExecutionLeaseTests: XCTestCase {
  func testLockBlocksAnotherOwnerAndSurvivingGroupBlocksAfterOwnerCloses() throws {
    let directory = try scratch()
    defer { try? FileManager.default.removeItem(at: directory) }
    let boot = UUID()
    var first: InstallerExecutionLease? = try acquire(directory, boot: boot) { _ in false }
    XCTAssertNotNil(first)
    XCTAssertThrowsError(try acquire(directory, boot: boot) { _ in false }) {
      XCTAssertEqual($0 as? InstallerExecutionLeaseError, .busy)
    }
    first = nil
    XCTAssertThrowsError(try acquire(directory, boot: boot) { _ in true }) {
      XCTAssertEqual($0 as? InstallerExecutionLeaseError, .busy)
    }
    let replacement = try acquire(directory, boot: boot) { _ in false }
    withExtendedLifetime(replacement) {}
  }

  func testPreviousBootDoesNotBlockOnReusedGroupNumber() throws {
    let directory = try scratch()
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
      let first = try acquire(directory, boot: UUID()) { _ in false }
      withExtendedLifetime(first) {}
    }
    let next = try acquire(directory, boot: UUID()) { _ in
      XCTFail("Old-boot group identities must not be probed")
      return true
    }
    withExtendedLifetime(next) {}
  }

  func testRealSurvivingChildBlocksReplacementAfterLeaderAndLockOwnerExit() throws {
    let directory = try scratch()
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = Pipe()
    let gate = Pipe()
    let leader = try InstallerChildProcess.launch(
      executable: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", "read permit; /bin/sleep 3 >/dev/null 2>&1 & echo $!; exit 0"],
      environment: [:], directory: directory, input: gate.fileHandleForReading,
      output: output.fileHandleForWriting, processGroup: 0)
    try output.fileHandleForWriting.close()
    try gate.fileHandleForReading.close()
    let boot = UUID()
    var owner: InstallerExecutionLease? = try InstallerExecutionLease.acquire(
      directory: directory, owner: geteuid(), processGroup: leader.identifier,
      processID: leader.identifier, boot: boot, groupExists: InstallerExecutionLease.groupExists)
    XCTAssertNotNil(owner)
    try gate.fileHandleForWriting.write(contentsOf: Data("go\n".utf8))
    try gate.fileHandleForWriting.close()
    let childLine = try XCTUnwrap(output.fileHandleForReading.read(upToCount: 128))
    let childPID = try XCTUnwrap(
      Int32(
        String(decoding: childLine, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
    XCTAssertEqual(getpgid(childPID), leader.identifier)
    XCTAssertEqual(try leader.wait(), 0)
    owner = nil
    XCTAssertThrowsError(
      try acquire(directory, boot: boot, probe: InstallerExecutionLease.groupExists)
    ) {
      XCTAssertEqual($0 as? InstallerExecutionLeaseError, .busy)
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while try InstallerExecutionLease.groupExists(leader.identifier), ContinuousClock.now < deadline
    {
      Thread.sleep(forTimeInterval: 0.05)
    }
    XCTAssertFalse(try InstallerExecutionLease.groupExists(leader.identifier))
    let replacement = try acquire(directory, boot: boot, probe: InstallerExecutionLease.groupExists)
    withExtendedLifetime(replacement) {}
  }

  func testCorruptRecordAndSymlinkFailClosed() throws {
    let directory = try scratch()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("execution.lock")
    try Data("broken".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    XCTAssertThrowsError(try acquire(directory, boot: UUID()) { _ in false }) {
      XCTAssertEqual($0 as? InstallerExecutionLeaseError, .invalidRecord)
    }
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: "/dev/null")
    XCTAssertThrowsError(try acquire(directory, boot: UUID()) { _ in false }) {
      XCTAssertEqual($0 as? InstallerExecutionLeaseError, .unsafePath)
    }
  }

  func testInspectionFailureCannotPermitReplacement() throws {
    let directory = try scratch()
    defer { try? FileManager.default.removeItem(at: directory) }
    let boot = UUID()
    do {
      let lease = try acquire(directory, boot: boot) { _ in false }
      withExtendedLifetime(lease) {}
    }
    XCTAssertThrowsError(try acquire(directory, boot: boot) { _ in throw POSIXError(.EIO) })
  }

  func testRealChildInheritsGroupAndPreservesArgumentsEnvironmentAndExitStatus() throws {
    let pipe = Pipe()
    let child = try InstallerChildProcess.launch(
      executable: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", "printf '%s\\n' \"$VALUE\"; /bin/ps -o pgid= -p $$; exit 7"],
      environment: ["VALUE": "literal $value with spaces"],
      directory: URL(fileURLWithPath: "/"), output: pipe.fileHandleForWriting)
    try pipe.fileHandleForWriting.close()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    XCTAssertEqual(try child.wait(), 7)
    let lines = output.split(separator: "\n")
    XCTAssertEqual(lines.first, "literal $value with spaces")
    XCTAssertEqual(Int32(lines.last!.trimmingCharacters(in: .whitespaces)), getpgrp())
  }

  private func scratch() throws -> URL {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: path, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    return path
  }

  private func acquire(_ directory: URL, boot: UUID, probe: (Int32) throws -> Bool) throws
    -> InstallerExecutionLease
  {
    try InstallerExecutionLease.acquire(
      directory: directory, owner: geteuid(),
      processGroup: 12345, processID: 12345, boot: boot, groupExists: probe)
  }
}
