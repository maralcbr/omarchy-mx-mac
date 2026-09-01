#if os(macOS)
  import Darwin
  import Foundation
  import XCTest

  @testable import OmarchyAppleInstallerTrustCore

  final class EngineJournalTailTests: XCTestCase {
    func testLocatorMirrorsExecutorJournalPath() {
      let workingDirectory = URL(
        fileURLWithPath: "/var/db/com.omarchy.mx.installer",
        isDirectory: true
      )
      let hex = String(repeating: "a", count: 64)

      let url = EngineJournalLocator.journalURL(
        workingDirectory: workingDirectory,
        bindingDigest: "sha256:" + hex
      )

      XCTAssertEqual(
        url?.path,
        "/var/db/com.omarchy.mx.installer/execution-journals/\(hex).jsonl"
      )
    }

    func testLocatorRejectsMalformedDigest() {
      let workingDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)

      XCTAssertNil(
        EngineJournalLocator.journalURL(
          workingDirectory: workingDirectory,
          bindingDigest: "sha256:not-a-digest"
        )
      )
      XCTAssertNil(
        EngineJournalLocator.journalURL(
          workingDirectory: workingDirectory,
          bindingDigest: "../../etc/passwd"
        )
      )
    }

    func testTailerForwardsOnlyCompleteLinesAndBuffersPartialTail() async throws {
      let journal = temporaryJournalURL()
      defer { try? FileManager.default.removeItem(at: journal) }
      let sink = RecordingJournalSink()
      let tailer = EngineJournalTailer(
        journalURL: journal,
        expectedOwner: geteuid(),
        pollInterval: .milliseconds(20),
        sink: sink
      )

      // Tolerates a journal that does not exist yet.
      await tailer.start()
      try write("first\n", to: journal, append: false)
      try await Task.sleep(for: .milliseconds(80))
      try write("second\npart", to: journal, append: true)
      try await Task.sleep(for: .milliseconds(80))
      await tailer.stop()

      XCTAssertEqual(sink.text, "first\nsecond\n")
      XCTAssertFalse(sink.text.contains("part"))
    }

    func testStopPerformsFinalDrain() async throws {
      let journal = temporaryJournalURL()
      defer { try? FileManager.default.removeItem(at: journal) }
      let sink = RecordingJournalSink()
      let tailer = EngineJournalTailer(
        journalURL: journal,
        expectedOwner: geteuid(),
        pollInterval: .seconds(30),
        sink: sink
      )

      await tailer.start()
      try write("only-line\n", to: journal, append: false)
      await tailer.stop()

      XCTAssertEqual(sink.text, "only-line\n")
    }

    func testForeignOwnerStopsForwarding() async throws {
      let journal = temporaryJournalURL()
      defer { try? FileManager.default.removeItem(at: journal) }
      try write("line\n", to: journal, append: false)
      let sink = RecordingJournalSink()
      let tailer = EngineJournalTailer(
        journalURL: journal,
        expectedOwner: geteuid() &+ 1,
        pollInterval: .milliseconds(20),
        sink: sink
      )

      await tailer.start()
      try await Task.sleep(for: .milliseconds(60))
      await tailer.stop()

      XCTAssertEqual(sink.chunks.count, 0)
    }

    func testGroupReadableJournalStopsForwarding() async throws {
      let journal = temporaryJournalURL()
      defer { try? FileManager.default.removeItem(at: journal) }
      try write("line\n", to: journal, append: false)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: journal.path
      )
      let sink = RecordingJournalSink()
      let tailer = EngineJournalTailer(
        journalURL: journal,
        expectedOwner: geteuid(),
        pollInterval: .milliseconds(20),
        sink: sink
      )

      await tailer.start()
      try await Task.sleep(for: .milliseconds(60))
      await tailer.stop()

      XCTAssertEqual(sink.chunks.count, 0)
    }

    func testChunkCapSplitsOnLineBoundaries() async throws {
      let journal = temporaryJournalURL()
      defer { try? FileManager.default.removeItem(at: journal) }
      let sink = RecordingJournalSink()
      let tailer = EngineJournalTailer(
        journalURL: journal,
        expectedOwner: geteuid(),
        pollInterval: .seconds(30),
        maximumChunkBytes: 8,
        sink: sink
      )

      await tailer.start()
      try write("aaa\nbbb\nccc\n", to: journal, append: false)
      await tailer.stop()

      XCTAssertEqual(sink.text, "aaa\nbbb\nccc\n")
      XCTAssertTrue(sink.chunks.count > 1)
      for chunk in sink.chunks {
        XCTAssertEqual(chunk.last, 0x0A)
      }
    }

    func testOversizedSingleLineIsForwardedAlone() async throws {
      let journal = temporaryJournalURL()
      defer { try? FileManager.default.removeItem(at: journal) }
      let sink = RecordingJournalSink()
      let tailer = EngineJournalTailer(
        journalURL: journal,
        expectedOwner: geteuid(),
        pollInterval: .seconds(30),
        maximumChunkBytes: 4,
        sink: sink
      )

      await tailer.start()
      try write("aaaaaaaaaa\nbb\n", to: journal, append: false)
      await tailer.stop()

      XCTAssertEqual(sink.chunks.first.map { String(decoding: $0, as: UTF8.self) }, "aaaaaaaaaa\n")
      XCTAssertEqual(sink.text, "aaaaaaaaaa\nbb\n")
    }

    private func temporaryJournalURL() -> URL {
      FileManager.default.temporaryDirectory.appendingPathComponent(
        "omarchy-journal-\(UUID().uuidString.lowercased()).jsonl"
      )
    }

    private func write(
      _ text: String,
      to url: URL,
      append: Bool
    ) throws {
      if append, FileManager.default.fileExists(atPath: url.path) {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        return
      }
      try Data(text.utf8).write(to: url, options: .atomic)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: url.path
      )
    }
  }

  final class RecordingJournalSink: EngineJournalProgressSink, @unchecked Sendable {
    private let lock = NSLock()
    private var storage = [Data]()

    var chunks: [Data] {
      lock.withLock { storage }
    }

    var text: String {
      String(decoding: chunks.reduce(into: Data()) { $0.append($1) }, as: UTF8.self)
    }

    func journalDidAppend(_ completeLines: Data) {
      lock.withLock { storage.append(completeLines) }
    }
  }
#endif
