import Foundation
import OmarchyAppleInstallerTrustCore

struct EngineInspectionRunner: Sendable {
  func inspect() async throws -> EngineInspectionResult {
    let scratch = try scratchDirectory()
    let archive = try ValidationEngineArtifactLocator().locate()
    return try await inspect(archive, in: scratch)
  }

  func inspect(
    _ archive: PinnedAsahiEngineArchive
  ) async throws -> EngineInspectionResult {
    try await inspect(archive, in: scratchDirectory())
  }

  private func inspect(
    _ archive: PinnedAsahiEngineArchive,
    in scratch: URL
  ) async throws -> EngineInspectionResult {
    let transcript = try await PinnedAsahiEngineExecutor().inspect(
      archive,
      in: scratch
    )
    return EngineInspectionResult(
      transcript: transcript,
      validated: try AppleInstallerTrustCore()
        .validateEngineTranscript(transcript)
    )
  }

  private func scratchDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "com.omarchy.mx.installer-engine",
      isDirectory: true
    )
    if !FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
    }
    return directory
  }
}

struct EngineInspectionResult: Sendable {
  let transcript: Data
  let validated: ValidatedEngineTranscript
}

enum InstallerAppError: Error {
  case hostChanged
  case workspaceUnavailable
  case inspectionRequired
  case approvalUnavailable
  case previewFixtureUnavailable
  case existingInstallUnavailable
}
