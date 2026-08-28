import CryptoKit
import Foundation
import XCTest

@testable import OmarchyAppleInstallerTrustCore

final class VerifiedArtifactStagerTests: XCTestCase {
  func testDescriptorRejectsUntrustedInputs() {
    XCTAssertThrowsError(
      try descriptor(source: "http://example.com/installer.tar.gz")
    ) {
      XCTAssertEqual($0 as? ArtifactStageError, .invalidSourceURL)
    }
    XCTAssertThrowsError(try descriptor(fileName: "../installer.tar.gz")) {
      XCTAssertEqual($0 as? ArtifactStageError, .invalidFileName)
    }
    XCTAssertThrowsError(try descriptor(fileName: "installer\0ignored.tar.gz")) {
      XCTAssertEqual($0 as? ArtifactStageError, .invalidFileName)
    }
    XCTAssertThrowsError(try descriptor(digest: "sha256:ABC")) {
      XCTAssertEqual($0 as? ArtifactStageError, .invalidDigest)
    }
  }

  func testValidDownloadIsVerifiedAndAcceptedAtomically() async throws {
    let data = Data("pinned installer payload".utf8)
    let downloader = FixtureArtifactDownloader(data: data)
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let artifact = try descriptor(data: data)

    let result = try await VerifiedArtifactStager(
      downloader: downloader
    ).stage(artifact, in: directory)

    XCTAssertEqual(try Data(contentsOf: result.fileURL), data)
    XCTAssertFalse(result.reusedExistingFile)
    let downloadCount = await downloader.downloadCount
    XCTAssertEqual(downloadCount, 1)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: directory.path),
      [artifact.fileName]
    )
  }

  func testExactExistingArtifactIsReusedWithoutDownload() async throws {
    let data = Data("pinned installer payload".utf8)
    let downloader = FixtureArtifactDownloader(data: data)
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let artifact = try descriptor(data: data)
    let stager = VerifiedArtifactStager(downloader: downloader)

    _ = try await stager.stage(artifact, in: directory)
    let replay = try await stager.stage(artifact, in: directory)

    XCTAssertTrue(replay.reusedExistingFile)
    let downloadCount = await downloader.downloadCount
    XCTAssertEqual(downloadCount, 1)
  }

  func testDigestMismatchLeavesNoAcceptedOrPendingFile() async throws {
    let expected = Data("expected".utf8)
    let delivered = Data("tampered".utf8)
    let downloader = FixtureArtifactDownloader(data: delivered)
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let artifact = try descriptor(data: expected)

    await assertThrows(
      try await VerifiedArtifactStager(downloader: downloader).stage(
        artifact,
        in: directory
      )
    ) { error in
      guard case .digestMismatch = error as? ArtifactStageError else {
        return XCTFail("Expected digestMismatch, got \(error)")
      }
    }

    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: directory.path),
      []
    )
  }

  func testWrongExistingDestinationFailsClosed() async throws {
    let data = Data("expected".utf8)
    let downloader = FixtureArtifactDownloader(data: data)
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let artifact = try descriptor(data: data)
    try Data("wrong".utf8).write(
      to: directory.appendingPathComponent(artifact.fileName)
    )

    await assertThrows(
      try await VerifiedArtifactStager(downloader: downloader).stage(
        artifact,
        in: directory
      )
    ) {
      XCTAssertEqual(
        $0 as? ArtifactStageError,
        .destinationConflict(artifact.fileName)
      )
    }
    let downloadCount = await downloader.downloadCount
    XCTAssertEqual(downloadCount, 0)
  }

  func testSizeMismatchIsRejectedBeforeAcceptance() async throws {
    let data = Data("payload".utf8)
    let downloader = FixtureArtifactDownloader(data: data)
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let artifact = try PinnedInstallerArtifact(
      role: "engine",
      sourceURL: URL(string: "https://example.com/installer.tar.gz")!,
      fileName: "installer.tar.gz",
      expectedDigest: digest(data),
      expectedSizeBytes: UInt64(data.count + 1)
    )

    await assertThrows(
      try await VerifiedArtifactStager(downloader: downloader).stage(
        artifact,
        in: directory
      )
    ) {
      XCTAssertEqual(
        $0 as? ArtifactStageError,
        .sizeMismatch(
          expected: UInt64(data.count + 1),
          actual: UInt64(data.count)
        )
      )
    }
  }

  private func descriptor(
    source: String = "https://example.com/installer.tar.gz",
    fileName: String = "installer.tar.gz",
    digest: String? = nil,
    data: Data = Data("pinned installer payload".utf8)
  ) throws -> PinnedInstallerArtifact {
    try PinnedInstallerArtifact(
      role: "engine",
      sourceURL: URL(string: source)!,
      fileName: fileName,
      expectedDigest: digest ?? self.digest(data),
      expectedSizeBytes: UInt64(data.count)
    )
  }

  private func digest(_ data: Data) -> String {
    "sha256:"
      + SHA256.hash(data: data)
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "omarchy-artifact-stager-\(UUID().uuidString.lowercased())",
      isDirectory: true
    )
  }
}

private actor FixtureArtifactDownloader: ArtifactDownloading {
  private let data: Data
  private(set) var downloadCount = 0

  init(data: Data) {
    self.data = data
  }

  func download(from sourceURL: URL) async throws -> URL {
    downloadCount += 1
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "omarchy-downloader-\(UUID().uuidString.lowercased())"
    )
    try data.write(to: fileURL, options: .withoutOverwriting)
    return fileURL
  }
}

private func assertThrows<T>(
  _ expression: @autoclosure () async throws -> T,
  handler: (any Error) -> Void
) async {
  do {
    _ = try await expression()
    XCTFail("Expected expression to throw")
  } catch {
    handler(error)
  }
}
