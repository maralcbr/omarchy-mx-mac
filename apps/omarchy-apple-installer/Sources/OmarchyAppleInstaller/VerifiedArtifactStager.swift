import CryptoKit
import Foundation

public struct PinnedInstallerArtifact: Equatable, Sendable {
  public let role: String
  public let sourceURL: URL
  public let fileName: String
  public let expectedDigest: String
  public let expectedSizeBytes: UInt64

  public init(
    role: String,
    sourceURL: URL,
    fileName: String,
    expectedDigest: String,
    expectedSizeBytes: UInt64
  ) throws {
    guard !role.isEmpty, role.utf8.count <= 64 else {
      throw ArtifactStageError.invalidRole
    }
    guard sourceURL.scheme == "https",
      sourceURL.host?.isEmpty == false,
      sourceURL.user == nil,
      sourceURL.password == nil,
      sourceURL.fragment == nil
    else {
      throw ArtifactStageError.invalidSourceURL
    }
    guard Self.isSafeFileName(fileName) else {
      throw ArtifactStageError.invalidFileName
    }
    guard Self.isSHA256Digest(expectedDigest) else {
      throw ArtifactStageError.invalidDigest
    }
    guard expectedSizeBytes > 0 else {
      throw ArtifactStageError.invalidExpectedSize
    }

    self.role = role
    self.sourceURL = sourceURL
    self.fileName = fileName
    self.expectedDigest = expectedDigest
    self.expectedSizeBytes = expectedSizeBytes
  }

  private static func isSafeFileName(_ value: String) -> Bool {
    !value.isEmpty
      && value != "."
      && value != ".."
      && value.utf8.count <= 255
      && !value.utf8.contains(0)
      && !value.contains("/")
      && !value.contains("\\")
      && (value as NSString).lastPathComponent == value
  }

  private static func isSHA256Digest(_ value: String) -> Bool {
    guard value.hasPrefix("sha256:") else {
      return false
    }
    let hexadecimal = value.dropFirst(7)
    return hexadecimal.count == 64
      && hexadecimal.allSatisfy {
        $0.isNumber || ("a"..."f").contains($0)
      }
  }
}

public struct StagedInstallerArtifact: Equatable, Sendable {
  public let artifact: PinnedInstallerArtifact
  public let fileURL: URL
  public let reusedExistingFile: Bool
}

public enum ArtifactStageError: Error, Equatable, Sendable {
  case invalidRole
  case invalidSourceURL
  case invalidFileName
  case invalidDigest
  case invalidExpectedSize
  case unsafeStagingDirectory
  case unsafeStagedFile(String)
  case unexpectedHTTPStatus(Int)
  case sizeMismatch(expected: UInt64, actual: UInt64)
  case digestMismatch(expected: String, actual: String)
  case destinationConflict(String)
}

public struct VerifiedArtifactStager: Sendable {
  private let downloader: any ArtifactDownloading

  public init() {
    downloader = URLSessionArtifactDownloader()
  }

  init(downloader: any ArtifactDownloading) {
    self.downloader = downloader
  }

  public func stage(
    _ artifact: PinnedInstallerArtifact,
    in stagingDirectory: URL
  ) async throws -> StagedInstallerArtifact {
    let fileManager = FileManager.default
    try ensureSafeDirectory(stagingDirectory, fileManager: fileManager)
    let destination = stagingDirectory.appendingPathComponent(
      artifact.fileName,
      isDirectory: false
    )

    if fileManager.fileExists(atPath: destination.path) {
      do {
        try verify(artifact, at: destination)
      } catch {
        throw ArtifactStageError.destinationConflict(artifact.fileName)
      }
      return StagedInstallerArtifact(
        artifact: artifact,
        fileURL: destination,
        reusedExistingFile: true
      )
    }

    let downloaded = try await downloader.download(from: artifact.sourceURL)
    defer { try? fileManager.removeItem(at: downloaded) }

    let pending = stagingDirectory.appendingPathComponent(
      ".pending-\(UUID().uuidString.lowercased())",
      isDirectory: false
    )
    defer { try? fileManager.removeItem(at: pending) }

    try fileManager.copyItem(at: downloaded, to: pending)
    try verify(artifact, at: pending)

    do {
      try fileManager.moveItem(at: pending, to: destination)
    } catch {
      guard fileManager.fileExists(atPath: destination.path) else {
        throw error
      }
      do {
        try verify(artifact, at: destination)
      } catch {
        throw ArtifactStageError.destinationConflict(artifact.fileName)
      }
    }

    return StagedInstallerArtifact(
      artifact: artifact,
      fileURL: destination,
      reusedExistingFile: false
    )
  }

  private func ensureSafeDirectory(
    _ directory: URL,
    fileManager: FileManager
  ) throws {
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(
      atPath: directory.path,
      isDirectory: &isDirectory
    ) {
      let values = try directory.resourceValues(
        forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
      )
      guard isDirectory.boolValue,
        values.isDirectory == true,
        values.isSymbolicLink != true
      else {
        throw ArtifactStageError.unsafeStagingDirectory
      }
      return
    }

    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let values = try directory.resourceValues(
      forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
    )
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw ArtifactStageError.unsafeStagingDirectory
    }
  }

  private func verify(
    _ artifact: PinnedInstallerArtifact,
    at fileURL: URL
  ) throws {
    let values = try fileURL.resourceValues(
      forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
    )
    guard values.isRegularFile == true, values.isSymbolicLink != true else {
      throw ArtifactStageError.unsafeStagedFile(artifact.fileName)
    }

    let result = try digestAndSize(of: fileURL)
    guard result.size == artifact.expectedSizeBytes else {
      throw ArtifactStageError.sizeMismatch(
        expected: artifact.expectedSizeBytes,
        actual: result.size
      )
    }
    guard result.digest == artifact.expectedDigest else {
      throw ArtifactStageError.digestMismatch(
        expected: artifact.expectedDigest,
        actual: result.digest
      )
    }
  }

  private func digestAndSize(
    of fileURL: URL
  ) throws -> (digest: String, size: UInt64) {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }
    var hasher = SHA256()
    var size: UInt64 = 0

    while let chunk = try handle.read(upToCount: 1_048_576),
      !chunk.isEmpty
    {
      let addition = UInt64(chunk.count)
      guard !size.addingReportingOverflow(addition).overflow else {
        throw ArtifactStageError.invalidExpectedSize
      }
      size += addition
      hasher.update(data: chunk)
    }

    let digest = "sha256:" + hasher.finalize()
      .map { String(format: "%02x", $0) }
      .joined()
    return (digest, size)
  }
}

protocol ArtifactDownloading: Sendable {
  func download(from sourceURL: URL) async throws -> URL
}

struct URLSessionArtifactDownloader: ArtifactDownloading {
  func download(from sourceURL: URL) async throws -> URL {
    let (temporaryURL, response) = try await URLSession.shared.download(
      from: sourceURL
    )
    guard let response = response as? HTTPURLResponse,
      (200...299).contains(response.statusCode)
    else {
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      throw ArtifactStageError.unexpectedHTTPStatus(status)
    }
    return temporaryURL
  }
}
