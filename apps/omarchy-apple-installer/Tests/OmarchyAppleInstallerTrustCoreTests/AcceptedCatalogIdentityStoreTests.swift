#if os(macOS)
  import Foundation
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  final class AcceptedCatalogIdentityStoreTests: XCTestCase {
    func testMissingStateThenAtomicRoundTrip() throws {
      let directory = try privateDirectory()
      defer { try? FileManager.default.removeItem(at: directory) }
      let store = AcceptedCatalogIdentityStore(directory: directory)
      let identity = try catalogIdentity(sequence: 8, digit: "a")

      XCTAssertNil(try store.load())
      try store.store(identity)

      XCTAssertEqual(try store.load(), identity)
      let state = directory.appendingPathComponent(
        AcceptedCatalogIdentityStore.fileName
      )
      let permissions = try XCTUnwrap(
        try FileManager.default.attributesOfItem(atPath: state.path)[
          .posixPermissions
        ] as? NSNumber
      )
      XCTAssertEqual(permissions.intValue & 0o077, 0)
    }

    func testRollbackSequenceIsRejected() throws {
      let directory = try privateDirectory()
      defer { try? FileManager.default.removeItem(at: directory) }
      let store = AcceptedCatalogIdentityStore(directory: directory)
      try store.store(try catalogIdentity(sequence: 9, digit: "a"))

      XCTAssertThrowsError(
        try store.store(try catalogIdentity(sequence: 8, digit: "b"))
      ) {
        XCTAssertEqual(
          $0 as? SupportCatalogSequenceError,
          .rollback(stored: 9, candidate: 8)
        )
      }
    }

    func testSequenceReuseWithDifferentPayloadIsRejected() throws {
      let directory = try privateDirectory()
      defer { try? FileManager.default.removeItem(at: directory) }
      let store = AcceptedCatalogIdentityStore(directory: directory)
      try store.store(try catalogIdentity(sequence: 9, digit: "a"))

      XCTAssertThrowsError(
        try store.store(try catalogIdentity(sequence: 9, digit: "b"))
      ) {
        XCTAssertEqual(
          $0 as? SupportCatalogSequenceError,
          .sequenceReuse(9)
        )
      }
    }

    func testSymlinkedStateIsRejected() throws {
      let directory = try privateDirectory()
      defer { try? FileManager.default.removeItem(at: directory) }
      let external = directory.deletingLastPathComponent()
        .appendingPathComponent(
          "omarchy-catalog-external-\(UUID().uuidString.lowercased())"
        )
      defer { try? FileManager.default.removeItem(at: external) }
      try Data("{}".utf8).write(
        to: external,
        options: .withoutOverwriting
      )
      try FileManager.default.createSymbolicLink(
        at: directory.appendingPathComponent(
          AcceptedCatalogIdentityStore.fileName
        ),
        withDestinationURL: external
      )

      XCTAssertThrowsError(
        try AcceptedCatalogIdentityStore(directory: directory).load()
      ) {
        XCTAssertEqual(
          $0 as? AcceptedCatalogIdentityStoreError,
          .unsafeState
        )
      }
    }

    private func catalogIdentity(
      sequence: UInt64,
      digit: Character
    ) throws -> AcceptedCatalogIdentity {
      try AcceptedCatalogIdentity(
        sequence: sequence,
        payloadDigest: "sha256:" + String(repeating: digit, count: 64)
      )
    }

    private func privateDirectory() throws -> URL {
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
          "omarchy-catalog-store-\(UUID().uuidString.lowercased())",
          isDirectory: true
        )
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      return directory
    }
  }
#endif
