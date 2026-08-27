#if os(macOS)
  import Darwin
  import Foundation

  public enum PinnedAsahiEngineExecutionError:
    Error, Equatable, Sendable
  {
    case privilegeRequired
    case unsafeArchive
    case unsafeArchiveEntry
    case extractionFailed(Int32)
    case invalidBundle
    case launchFailed
    case engineExited(Int32)
    case unsafeTranscript
  }

  public struct PinnedAsahiEngineExecutor:
    ImportedEngineHandoffExecuting, Sendable
  {
    public static let maximumArchiveBytes: Int64 = 67_108_864
    public static let maximumTranscriptBytes: Int64 = 8_388_608

    private let effectiveUserID: @Sendable () -> uid_t
    private let expectedFileOwnerID: @Sendable () -> uid_t

    public init() {
      effectiveUserID = { geteuid() }
      expectedFileOwnerID = { geteuid() }
    }

    init(
      effectiveUserID: @escaping @Sendable () -> uid_t,
      expectedFileOwnerID: @escaping @Sendable () -> uid_t = { geteuid() }
    ) {
      self.effectiveUserID = effectiveUserID
      self.expectedFileOwnerID = expectedFileOwnerID
    }

    public func execute(
      _ package: ImportedEngineHandoffPackage
    ) async throws -> Data {
      guard effectiveUserID() == 0 else {
        throw PinnedAsahiEngineExecutionError.privilegeRequired
      }
      try validateArchive(package.engineURL)

      let executionRoot = package.packageURL
        .deletingLastPathComponent()
        .appendingPathComponent(
          "engine-execution-\(UUID().uuidString.lowercased())",
          isDirectory: true
        )
      try FileManager.default.createDirectory(
        at: executionRoot,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      defer { try? FileManager.default.removeItem(at: executionRoot) }

      let bundle = executionRoot.appendingPathComponent(
        "bundle",
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: bundle,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      try validateArchiveEntries(package.engineURL)
      try extract(package.engineURL, into: bundle)
      try validateExtractedBundle(bundle)

      let journal = try preparePersistentJournal(for: package)
      let process = Process()
      process.executableURL = Self.pythonURL(in: bundle)
      process.arguments = [bundle.appendingPathComponent("main.py").path]
      process.environment = environment(
        bundle: bundle,
        executionRoot: executionRoot,
        journal: journal,
        package: package
      )
      process.currentDirectoryURL = bundle
      process.standardInput = FileHandle.nullDevice
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      do {
        try process.run()
        process.waitUntilExit()
      } catch {
        throw PinnedAsahiEngineExecutionError.launchFailed
      }
      guard process.terminationReason == .exit,
        process.terminationStatus == 0
      else {
        throw PinnedAsahiEngineExecutionError.engineExited(
          process.terminationStatus
        )
      }
      return try readTranscript(journal)
    }

    private func environment(
      bundle: URL,
      executionRoot: URL,
      journal: URL,
      package: ImportedEngineHandoffPackage
    ) -> [String: String] {
      [
        "HOME": executionRoot.path,
        "TMPDIR": executionRoot.path,
        "PATH": [
          bundle.appendingPathComponent("bin").path,
          "/usr/bin",
          "/bin",
          "/usr/sbin",
          "/sbin",
        ].joined(separator: ":"),
        "LC_ALL": "C",
        "LANG": "C",
        "DYLD_LIBRARY_PATH": bundle.appendingPathComponent(
          "Frameworks/Python.framework/Versions/Current/lib"
        ).path,
        "DYLD_FRAMEWORK_PATH": bundle.appendingPathComponent(
          "Frameworks"
        ).path,
        "SSL_CERT_FILE": bundle.appendingPathComponent(
          "Frameworks/Python.framework/Versions/Current/etc/openssl/cert.pem"
        ).path,
        "OMARCHY_ENGINE_MODE": "install",
        "OMARCHY_ENGINE_JOURNAL": journal.path,
        "OMARCHY_ENGINE_REQUEST": package.requestURL.path,
        "OMARCHY_ENGINE_IDENTITY": package.identityURL.path,
        "OMARCHY_ENGINE_METADATA": package.metadataURL.path,
        "OMARCHY_ENGINE_PAYLOAD": package.payloadURL.path,
        "OMARCHY_ENGINE_BINDING_DIGEST": package.bindingDigest,
        "OMARCHY_ENGINE_PLAN_DIGEST": package.planDigest,
      ]
    }

    private func validateArchive(_ archive: URL) throws {
      let descriptor = Darwin.open(
        archive.path,
        O_RDONLY | O_CLOEXEC | O_NOFOLLOW
      )
      guard descriptor >= 0 else {
        throw PinnedAsahiEngineExecutionError.unsafeArchive
      }
      defer { Darwin.close(descriptor) }

      var status = stat()
      guard fstat(descriptor, &status) == 0,
        (status.st_mode & S_IFMT) == S_IFREG,
        status.st_mode & 0o022 == 0,
        status.st_size > 0,
        status.st_size <= Self.maximumArchiveBytes
      else {
        throw PinnedAsahiEngineExecutionError.unsafeArchive
      }
    }

    private func validateArchiveEntries(_ archive: URL) throws {
      let output = Pipe()
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
      process.arguments = ["-tzf", archive.path]
      process.environment = Self.systemEnvironment
      process.standardInput = FileHandle.nullDevice
      process.standardOutput = output
      process.standardError = FileHandle.nullDevice
      do {
        try process.run()
      } catch {
        throw PinnedAsahiEngineExecutionError.launchFailed
      }
      let listing = try output.fileHandleForReading.readToEnd() ?? Data()
      process.waitUntilExit()
      guard process.terminationReason == .exit,
        process.terminationStatus == 0,
        !listing.isEmpty,
        listing.count <= 8_388_608,
        let names = String(data: listing, encoding: .utf8)
      else {
        throw PinnedAsahiEngineExecutionError.unsafeArchiveEntry
      }

      for name in names.split(
        separator: "\n",
        omittingEmptySubsequences: true
      ) {
        guard !name.isEmpty,
          name.utf8.count <= 1_024,
          !name.hasPrefix("/")
        else {
          throw PinnedAsahiEngineExecutionError.unsafeArchiveEntry
        }
        let components = name.split(
          separator: "/",
          omittingEmptySubsequences: false
        )
        guard !components.contains("..") else {
          throw PinnedAsahiEngineExecutionError.unsafeArchiveEntry
        }
      }
    }

    private func extract(_ archive: URL, into bundle: URL) throws {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
      process.arguments = [
        "-xzf", archive.path, "-C", bundle.path, "--no-same-owner",
      ]
      process.environment = Self.systemEnvironment
      process.currentDirectoryURL = bundle
      process.standardInput = FileHandle.nullDevice
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      do {
        try process.run()
        process.waitUntilExit()
      } catch {
        throw PinnedAsahiEngineExecutionError.launchFailed
      }
      guard process.terminationReason == .exit,
        process.terminationStatus == 0
      else {
        throw PinnedAsahiEngineExecutionError.extractionFailed(
          process.terminationStatus
        )
      }
    }

    private func validateExtractedBundle(_ bundle: URL) throws {
      guard let enumerator = FileManager.default.enumerator(
        at: bundle,
        includingPropertiesForKeys: nil,
        options: [],
        errorHandler: { _, _ in false }
      ) else {
        throw PinnedAsahiEngineExecutionError.invalidBundle
      }

      while let url = enumerator.nextObject() as? URL {
        var status = stat()
        guard lstat(url.path, &status) == 0 else {
          throw PinnedAsahiEngineExecutionError.invalidBundle
        }
        let kind = status.st_mode & S_IFMT
        if kind == S_IFREG || kind == S_IFDIR {
          guard status.st_mode & 0o022 == 0 else {
            throw PinnedAsahiEngineExecutionError.invalidBundle
          }
        } else if kind == S_IFLNK {
          try validateSymlink(url, beneath: bundle)
        } else {
          throw PinnedAsahiEngineExecutionError.invalidBundle
        }
      }

      try requireRegularFile(
        bundle.appendingPathComponent("main.py"),
        executable: false
      )
      try requireRegularFile(Self.pythonURL(in: bundle), executable: true)
    }

    private func validateSymlink(_ url: URL, beneath bundle: URL) throws {
      let target = try FileManager.default.destinationOfSymbolicLink(
        atPath: url.path
      )
      guard !target.isEmpty, !target.hasPrefix("/") else {
        throw PinnedAsahiEngineExecutionError.invalidBundle
      }
      var depth = url.deletingLastPathComponent().pathComponents.count
        - bundle.pathComponents.count
      for component in target.split(
        separator: "/",
        omittingEmptySubsequences: false
      ) {
        if component == ".." {
          depth -= 1
          guard depth >= 0 else {
            throw PinnedAsahiEngineExecutionError.invalidBundle
          }
        } else if component != "." && !component.isEmpty {
          depth += 1
        }
      }
    }

    private func requireRegularFile(
      _ url: URL,
      executable: Bool
    ) throws {
      var status = stat()
      guard lstat(url.path, &status) == 0,
        (status.st_mode & S_IFMT) == S_IFREG,
        status.st_mode & 0o022 == 0,
        !executable || status.st_mode & 0o111 != 0
      else {
        throw PinnedAsahiEngineExecutionError.invalidBundle
      }
    }

    private func preparePersistentJournal(
      for package: ImportedEngineHandoffPackage
    ) throws -> URL {
      guard package.bindingDigest.hasPrefix("sha256:") else {
        throw PinnedAsahiEngineExecutionError.unsafeTranscript
      }
      let identifier = String(package.bindingDigest.dropFirst(7))
      guard identifier.count == 64,
        identifier.allSatisfy({
          $0.isNumber || ("a"..."f").contains($0)
        })
      else {
        throw PinnedAsahiEngineExecutionError.unsafeTranscript
      }

      let directory = package.packageURL
        .deletingLastPathComponent()
        .appendingPathComponent("execution-journals", isDirectory: true)
      if !FileManager.default.fileExists(atPath: directory.path) {
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: false,
          attributes: [.posixPermissions: 0o700]
        )
      }
      try validateJournalDirectory(directory)

      let journal = directory.appendingPathComponent("\(identifier).jsonl")
      let descriptor = Darwin.open(
        journal.path,
        O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
        S_IRUSR | S_IWUSR
      )
      guard descriptor >= 0 else {
        throw PinnedAsahiEngineExecutionError.unsafeTranscript
      }
      var status = stat()
      guard fstat(descriptor, &status) == 0,
        (status.st_mode & S_IFMT) == S_IFREG,
        status.st_mode & 0o077 == 0,
        status.st_uid == expectedFileOwnerID(),
        status.st_size <= Self.maximumTranscriptBytes
      else {
        Darwin.close(descriptor)
        throw PinnedAsahiEngineExecutionError.unsafeTranscript
      }
      Darwin.close(descriptor)
      return journal
    }

    private func validateJournalDirectory(_ directory: URL) throws {
      var status = stat()
      guard lstat(directory.path, &status) == 0,
        (status.st_mode & S_IFMT) == S_IFDIR,
        status.st_mode & 0o077 == 0,
        status.st_uid == expectedFileOwnerID()
      else {
        throw PinnedAsahiEngineExecutionError.unsafeTranscript
      }
    }

    private func readTranscript(_ journal: URL) throws -> Data {
      let descriptor = Darwin.open(
        journal.path,
        O_RDONLY | O_CLOEXEC | O_NOFOLLOW
      )
      guard descriptor >= 0 else {
        throw PinnedAsahiEngineExecutionError.unsafeTranscript
      }
      defer { Darwin.close(descriptor) }

      var status = stat()
      guard fstat(descriptor, &status) == 0,
        (status.st_mode & S_IFMT) == S_IFREG,
        status.st_mode & 0o077 == 0,
        status.st_size > 0,
        status.st_size <= Self.maximumTranscriptBytes
      else {
        throw PinnedAsahiEngineExecutionError.unsafeTranscript
      }
      let handle = FileHandle(
        fileDescriptor: descriptor,
        closeOnDealloc: false
      )
      guard let data = try handle.readToEnd(),
        data.count == Int(status.st_size),
        data.last == 0x0A
      else {
        throw PinnedAsahiEngineExecutionError.unsafeTranscript
      }
      return data
    }

    private static func pythonURL(in bundle: URL) -> URL {
      bundle.appendingPathComponent(
        "Frameworks/Python.framework/Versions/3.13/bin/python3.13"
      )
    }

    private static let systemEnvironment = [
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
      "LC_ALL": "C",
      "LANG": "C",
    ]
  }
#endif
