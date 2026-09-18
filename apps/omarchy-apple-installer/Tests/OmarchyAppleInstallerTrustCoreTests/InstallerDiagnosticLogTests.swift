import Foundation
import XCTest

@testable import OmarchyAppleInstallerTrustCore

final class InstallerDiagnosticLogTests: XCTestCase {
  func testEventsAreDurableBeforeLoggerClosesAndContainOnlyAllowedFields() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = InstallerDiagnosticLog(directory: directory)
    log.record("engine_exited", code: 7)
    log.record("session_execution_failed", code: 12)
    let url = try XCTUnwrap(log.fileURL)
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    XCTAssertEqual(lines.count, 2)
    let entry = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
    XCTAssertEqual(Set(entry.keys), ["timestamp", "event", "pid", "uid", "version", "code"])
    XCTAssertEqual(entry["event"] as? String, "engine_exited")
    XCTAssertEqual(entry["code"] as? Int, 7)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
  }

  func testSymlinkLogDirectoryIsRefused() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let link = root.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
    XCTAssertNil(InstallerDiagnosticLog(directory: link).fileURL)
  }
}
