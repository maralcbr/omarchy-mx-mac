#if os(macOS)
  import Foundation

  public enum ValidationEngineArtifactError: Error, Equatable, Sendable {
    case unavailable
  }

  public struct ValidationEngineArtifactLocator: Sendable {
    public static let version = "v0.9.0-omarchy.9"
    public static let fileName = "installer-v0.9.0-omarchy.9.tar.gz"
    public static let expectedDigest =
      "sha256:355f74cfdc457c837541282220fc8540baacdbe9d2b6e0f9da12db5ba0e8ea93"
    public static let expectedSizeBytes: UInt64 = 17_915_770

    public init() {}

    public func locate() throws -> PinnedAsahiEngineArchive {
      try locate(
        environment: ProcessInfo.processInfo.environment,
        currentDirectory: URL(
          fileURLWithPath: FileManager.default.currentDirectoryPath,
          isDirectory: true
        ),
        resourceDirectory: Bundle.main.resourceURL
      )
    }

    func locate(
      environment: [String: String],
      currentDirectory: URL,
      resourceDirectory: URL?
    ) throws -> PinnedAsahiEngineArchive {
      var candidates = [URL]()
      if let override = environment["OMARCHY_VALIDATION_ENGINE_ARCHIVE"],
        !override.isEmpty
      {
        candidates.append(URL(fileURLWithPath: override))
      }
      if let resourceDirectory {
        candidates.append(
          resourceDirectory
            .appendingPathComponent("Engine", isDirectory: true)
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent(Self.fileName)
        )
      }
      candidates.append(
        currentDirectory
          .appendingPathComponent("Engine", isDirectory: true)
          .appendingPathComponent("artifacts", isDirectory: true)
          .appendingPathComponent(Self.fileName)
      )
      candidates.append(
        currentDirectory
          .appendingPathComponent("apps", isDirectory: true)
          .appendingPathComponent("omarchy-apple-installer", isDirectory: true)
          .appendingPathComponent("Engine", isDirectory: true)
          .appendingPathComponent("artifacts", isDirectory: true)
          .appendingPathComponent(Self.fileName)
      )

      guard
        let fileURL = candidates.first(where: {
          FileManager.default.fileExists(atPath: $0.path)
        })
      else {
        throw ValidationEngineArtifactError.unavailable
      }
      return try PinnedAsahiEngineArchive(
        fileURL: fileURL,
        expectedDigest: Self.expectedDigest,
        expectedSizeBytes: Self.expectedSizeBytes
      )
    }
  }
#endif
