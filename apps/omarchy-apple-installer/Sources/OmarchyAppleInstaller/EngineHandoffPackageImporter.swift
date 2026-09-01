#if os(macOS)
  import CryptoKit
  import Darwin
  import Foundation

  public struct ImportedEngineHandoffPackage: Sendable {
    public let packageURL: URL
    public let manifestURL: URL
    public let requestURL: URL
    public let identityURL: URL
    public let engineURL: URL
    public let metadataURL: URL
    public let payloadURL: URL
    public let repairManifestURL: URL?
    public let bindingDigest: String
    public let planDigest: String
    public let deviceIdentifier: String
    public let storeIdentifier: String

    public init(
      packageURL: URL,
      manifestURL: URL,
      requestURL: URL,
      identityURL: URL,
      engineURL: URL,
      metadataURL: URL,
      payloadURL: URL,
      repairManifestURL: URL? = nil,
      bindingDigest: String,
      planDigest: String,
      deviceIdentifier: String,
      storeIdentifier: String
    ) {
      self.packageURL = packageURL
      self.manifestURL = manifestURL
      self.requestURL = requestURL
      self.identityURL = identityURL
      self.engineURL = engineURL
      self.metadataURL = metadataURL
      self.payloadURL = payloadURL
      self.repairManifestURL = repairManifestURL
      self.bindingDigest = bindingDigest
      self.planDigest = planDigest
      self.deviceIdentifier = deviceIdentifier
      self.storeIdentifier = storeIdentifier
    }
  }

  public enum EngineHandoffImportError: Error, Equatable, Sendable {
    case unsafeSourceDirectory
    case unsafeDestinationDirectory
    case invalidManifest
    case invalidRequest
    case invalidIdentity
    case bindingMismatch
    case unsafeFile(String)
    case sizeMismatch(String)
    case digestMismatch(String)
  }

  public struct EngineHandoffPackageImporter: Sendable {
    private static let maximumControlFileBytes = 65_536

    public init() {}

    public func prepare(
      from packageDirectory: FileHandle,
      in destinationDirectory: URL
    ) throws -> ImportedEngineHandoffPackage {
      let sourceDescriptor = packageDirectory.fileDescriptor
      try validateSourceDirectory(sourceDescriptor)
      try validateDestinationDirectory(destinationDirectory)

      let manifestData = try readControlFile(
        "manifest.json",
        from: sourceDescriptor
      )
      let requestData = try readControlFile(
        "request.json",
        from: sourceDescriptor
      )
      let identityData = try readControlFile(
        "identity.json",
        from: sourceDescriptor
      )
      let manifest = try decodeManifest(manifestData)
      let request = try decodeRequest(requestData)
      let identity = try decodeIdentity(identityData)
      try validateBindings(
        manifest: manifest,
        request: request,
        identity: identity
      )

      let identifier = UUID().uuidString.lowercased()
      let package = destinationDirectory.appendingPathComponent(
        "imported-handoff-\(identifier)",
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: package,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      var keepPackage = false
      defer {
        if !keepPackage {
          try? FileManager.default.removeItem(at: package)
        }
      }

      let manifestURL = package.appendingPathComponent("manifest.json")
      let requestURL = package.appendingPathComponent("request.json")
      let identityURL = package.appendingPathComponent("identity.json")
      try writePrivate(manifestData, to: manifestURL)
      try writePrivate(requestData, to: requestURL)
      try writePrivate(identityData, to: identityURL)

      let engineURL = package.appendingPathComponent(manifest.engine.fileName)
      let metadataURL = package.appendingPathComponent(
        manifest.metadata.fileName
      )
      let payloadURL = package.appendingPathComponent(manifest.payload.fileName)
      let repairManifestURL = manifest.repairManifest.map {
        package.appendingPathComponent($0.fileName)
      }
      try copyArtifact(
        manifest.engine,
        role: "engine",
        from: sourceDescriptor,
        to: engineURL
      )
      try copyArtifact(
        manifest.metadata,
        role: "metadata",
        from: sourceDescriptor,
        to: metadataURL
      )
      try copyArtifact(
        manifest.payload,
        role: "payload",
        from: sourceDescriptor,
        to: payloadURL
      )
      if let repairManifest = manifest.repairManifest,
        let repairManifestURL
      {
        try copyArtifact(
          repairManifest,
          role: "repair-manifest",
          from: sourceDescriptor,
          to: repairManifestURL
        )
      }

      keepPackage = true
      return ImportedEngineHandoffPackage(
        packageURL: package,
        manifestURL: manifestURL,
        requestURL: requestURL,
        identityURL: identityURL,
        engineURL: engineURL,
        metadataURL: metadataURL,
        payloadURL: payloadURL,
        repairManifestURL: repairManifestURL,
        bindingDigest: identity.bindingDigest,
        planDigest: request.planDigest,
        deviceIdentifier: request.deviceIdentifier,
        storeIdentifier: request.storeIdentifier
      )
    }

    private func validateSourceDirectory(_ descriptor: Int32) throws {
      var status = stat()
      guard fstat(descriptor, &status) == 0,
        (status.st_mode & S_IFMT) == S_IFDIR,
        status.st_mode & 0o077 == 0
      else {
        throw EngineHandoffImportError.unsafeSourceDirectory
      }
    }

    private func validateDestinationDirectory(_ directory: URL) throws {
      var status = stat()
      guard lstat(directory.path, &status) == 0,
        (status.st_mode & S_IFMT) == S_IFDIR,
        status.st_mode & 0o077 == 0
      else {
        throw EngineHandoffImportError.unsafeDestinationDirectory
      }
    }

    private func readControlFile(
      _ name: String,
      from directoryDescriptor: Int32
    ) throws -> Data {
      let descriptor = openat(
        directoryDescriptor,
        name,
        O_RDONLY | O_CLOEXEC | O_NOFOLLOW
      )
      guard descriptor >= 0 else {
        throw EngineHandoffImportError.unsafeFile(name)
      }
      defer { Darwin.close(descriptor) }

      var status = stat()
      guard fstat(descriptor, &status) == 0,
        (status.st_mode & S_IFMT) == S_IFREG,
        status.st_mode & 0o022 == 0,
        status.st_size > 0,
        status.st_size <= Self.maximumControlFileBytes
      else {
        throw EngineHandoffImportError.unsafeFile(name)
      }
      let handle = FileHandle(
        fileDescriptor: descriptor,
        closeOnDealloc: false
      )
      guard let data = try handle.readToEnd(),
        data.count == Int(status.st_size)
      else {
        throw EngineHandoffImportError.unsafeFile(name)
      }
      return data
    }

    private func copyArtifact(
      _ artifact: ImportedArtifactRecord,
      role: String,
      from directoryDescriptor: Int32,
      to destination: URL
    ) throws {
      let source = openat(
        directoryDescriptor,
        artifact.fileName,
        O_RDONLY | O_CLOEXEC | O_NOFOLLOW
      )
      guard source >= 0 else {
        throw EngineHandoffImportError.unsafeFile(role)
      }
      defer { Darwin.close(source) }

      var status = stat()
      guard fstat(source, &status) == 0,
        (status.st_mode & S_IFMT) == S_IFREG,
        status.st_mode & 0o022 == 0,
        status.st_size > 0
      else {
        throw EngineHandoffImportError.unsafeFile(role)
      }
      guard UInt64(status.st_size) == artifact.sizeBytes else {
        throw EngineHandoffImportError.sizeMismatch(role)
      }

      let target = Darwin.open(
        destination.path,
        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
        S_IRUSR
      )
      guard target >= 0 else {
        throw EngineHandoffImportError.unsafeFile(role)
      }
      var targetOpen = true
      defer {
        if targetOpen {
          Darwin.close(target)
        }
      }

      let sourceHandle = FileHandle(
        fileDescriptor: source,
        closeOnDealloc: false
      )
      let targetHandle = FileHandle(
        fileDescriptor: target,
        closeOnDealloc: false
      )
      var hasher = SHA256()
      var size: UInt64 = 0
      while let chunk = try sourceHandle.read(upToCount: 1_048_576),
        !chunk.isEmpty
      {
        try targetHandle.write(contentsOf: chunk)
        hasher.update(data: chunk)
        let (updatedSize, overflow) = size.addingReportingOverflow(
          UInt64(chunk.count)
        )
        guard !overflow else {
          throw EngineHandoffImportError.sizeMismatch(role)
        }
        size = updatedSize
      }
      try targetHandle.synchronize()
      try targetHandle.close()
      targetOpen = false

      guard size == artifact.sizeBytes else {
        throw EngineHandoffImportError.sizeMismatch(role)
      }
      let digest = SHA256Digest.prefixedHex(hasher.finalize())
      guard digest == artifact.digest else {
        throw EngineHandoffImportError.digestMismatch(role)
      }
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
      try data.write(to: url, options: .withoutOverwriting)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o400],
        ofItemAtPath: url.path
      )
    }

    private func decodeManifest(_ data: Data) throws -> ImportedManifest {
      do {
        guard
          let rawObject = try JSONSerialization.jsonObject(with: data)
            as? [String: Any]
        else {
          throw EngineHandoffImportError.invalidManifest
        }
        var manifestKeys: Set<String> = [
          "format", "binding_digest", "request_file", "identity_file",
          "engine", "metadata", "payload",
        ]
        if rawObject["repair_manifest"] != nil {
          manifestKeys.insert("repair_manifest")
        }
        let object = try exactObject(
          data,
          keys: manifestKeys,
          error: .invalidManifest
        )
        for key in ["engine", "metadata", "payload", "repair_manifest"]
        where object[key] != nil {
          guard let artifact = object[key] as? [String: Any],
            Set(artifact.keys) == ["file_name", "digest", "size_bytes"]
          else {
            throw EngineHandoffImportError.invalidManifest
          }
        }
        let manifest = try JSONDecoder().decode(
          ImportedManifest.self,
          from: data
        )
        let fileNames =
          [
            manifest.engine.fileName,
            manifest.metadata.fileName,
            manifest.payload.fileName,
          ] + (manifest.repairManifest.map { [$0.fileName] } ?? [])
        guard manifest.format == 1,
          manifest.requestFile == "request.json",
          manifest.identityFile == "identity.json",
          Set(fileNames).count == fileNames.count,
          Set(fileNames).isDisjoint(
            with: ["manifest.json", "request.json", "identity.json"]
          ),
          ([manifest.engine, manifest.metadata, manifest.payload]
            + (manifest.repairManifest.map { [$0] } ?? []))
            .allSatisfy(validArtifact)
        else {
          throw EngineHandoffImportError.invalidManifest
        }
        return manifest
      } catch let error as EngineHandoffImportError {
        throw error
      } catch {
        throw EngineHandoffImportError.invalidManifest
      }
    }

    private func decodeRequest(_ data: Data) throws -> ImportedRequest {
      do {
        _ = try exactObject(
          data,
          keys: [
            "format", "operation", "plan_digest", "device_identifier",
            "store_identifier", "layout_digest", "candidate_kind",
            "source_identifier", "offset_bytes", "length_bytes",
            "engine_version", "required_human_steps",
          ],
          error: .invalidRequest
        )
        let request = try JSONDecoder().decode(ImportedRequest.self, from: data)
        guard request.format == 1,
          (request.operation == "install"
            && ["free", "resize", "replace"].contains(request.candidateKind))
            || (request.operation == "repair-installed-system"
              && request.candidateKind == "repair"),
          isHexDigest(request.planDigest),
          request.deviceIdentifier.range(
            of: #"^apple,[a-z0-9]+$"#,
            options: .regularExpression
          ) != nil,
          request.storeIdentifier.range(
            of: #"^disk[0-9]+$"#,
            options: .regularExpression
          ) != nil,
          isSHA256Digest(request.layoutDigest),
          request.sourceIdentifier.range(
            of: #"^disk[0-9]+(?:s[0-9]+)?$"#,
            options: .regularExpression
          ) != nil,
          request.lengthBytes > 0,
          !request.engineVersion.isEmpty,
          request.engineVersion.utf8.count <= 128,
          !request.offsetBytes.addingReportingOverflow(
            request.lengthBytes
          ).overflow,
          !request.requiredHumanSteps.isEmpty,
          request.requiredHumanSteps.allSatisfy({
            !$0.isEmpty && $0.utf8.count <= 128
          })
        else {
          throw EngineHandoffImportError.invalidRequest
        }
        return request
      } catch let error as EngineHandoffImportError {
        throw error
      } catch {
        throw EngineHandoffImportError.invalidRequest
      }
    }

    private func decodeIdentity(_ data: Data) throws -> ImportedIdentity {
      do {
        guard
          let rawObject = try JSONSerialization.jsonObject(with: data)
            as? [String: Any]
        else {
          throw EngineHandoffImportError.invalidIdentity
        }
        var identityKeys: Set<String> = [
          "format", "binding_digest", "trust_root_fingerprint",
          "catalog_sequence", "catalog_payload_digest", "plan_digest",
          "engine_digest", "metadata_digest", "payload_digest",
        ]
        if rawObject["repair_manifest_digest"] != nil {
          identityKeys.insert("repair_manifest_digest")
        }
        _ = try exactObject(
          data,
          keys: identityKeys,
          error: .invalidIdentity
        )
        let identity = try JSONDecoder().decode(
          ImportedIdentity.self,
          from: data
        )
        guard identity.format == 1,
          isSHA256Digest(identity.bindingDigest),
          isSHA256Digest(identity.trustRootFingerprint),
          identity.catalogSequence > 0,
          isSHA256Digest(identity.catalogPayloadDigest),
          isHexDigest(identity.planDigest),
          isSHA256Digest(identity.engineDigest),
          isSHA256Digest(identity.metadataDigest),
          isSHA256Digest(identity.payloadDigest)
            && (identity.repairManifestDigest == nil
              || isSHA256Digest(identity.repairManifestDigest!))
        else {
          throw EngineHandoffImportError.invalidIdentity
        }
        return identity
      } catch let error as EngineHandoffImportError {
        throw error
      } catch {
        throw EngineHandoffImportError.invalidIdentity
      }
    }

    private func validateBindings(
      manifest: ImportedManifest,
      request: ImportedRequest,
      identity: ImportedIdentity
    ) throws {
      var planFields = [
        request.deviceIdentifier,
        request.storeIdentifier,
        request.layoutDigest,
        request.candidateKind,
        request.sourceIdentifier,
        String(request.offsetBytes),
        String(request.lengthBytes),
        request.engineVersion,
        identity.engineDigest,
        identity.metadataDigest,
        identity.payloadDigest,
      ]
      if let repairManifestDigest = identity.repairManifestDigest {
        planFields.append(repairManifestDigest)
      }
      planFields.append(request.requiredHumanSteps.joined(separator: ","))
      guard manifest.bindingDigest == identity.bindingDigest,
        request.planDigest == identity.planDigest,
        request.planDigest == lengthPrefixedDigest(planFields),
        manifest.engine.digest == identity.engineDigest,
        manifest.metadata.digest == identity.metadataDigest,
        manifest.payload.digest == identity.payloadDigest,
        manifest.repairManifest?.digest == identity.repairManifestDigest,
        (request.operation == "repair-installed-system"
          && identity.repairManifestDigest != nil)
          || (request.operation == "install"
            && identity.repairManifestDigest == nil)
      else {
        throw EngineHandoffImportError.bindingMismatch
      }
    }

    private func exactObject(
      _ data: Data,
      keys: Set<String>,
      error: EngineHandoffImportError
    ) throws -> [String: Any] {
      guard
        let object = try JSONSerialization.jsonObject(with: data)
          as? [String: Any],
        Set(object.keys) == keys
      else {
        throw error
      }
      return object
    }

    private func validArtifact(_ artifact: ImportedArtifactRecord) -> Bool {
      isSafeFileName(artifact.fileName)
        && isSHA256Digest(artifact.digest)
        && artifact.sizeBytes > 0
    }

    private func isSafeFileName(_ value: String) -> Bool {
      !value.isEmpty
        && value != "."
        && value != ".."
        && value.utf8.count <= 255
        && !value.utf8.contains(0)
        && !value.contains("/")
        && !value.contains("\\")
        && (value as NSString).lastPathComponent == value
    }

    private func isSHA256Digest(_ value: String) -> Bool {
      SHA256Digest(rawValue: value) != nil
    }

    private func isHexDigest(_ value: String) -> Bool {
      SHA256Digest(hexadecimal: value) != nil
    }

    private func lengthPrefixedDigest(_ fields: [String]) -> String {
      InstallerDigest.lengthPrefixedSHA256(fields).hexadecimal
    }
  }

  private struct ImportedManifest: Decodable {
    let format: Int
    let bindingDigest: String
    let requestFile: String
    let identityFile: String
    let engine: ImportedArtifactRecord
    let metadata: ImportedArtifactRecord
    let payload: ImportedArtifactRecord
    let repairManifest: ImportedArtifactRecord?

    enum CodingKeys: String, CodingKey {
      case format
      case bindingDigest = "binding_digest"
      case requestFile = "request_file"
      case identityFile = "identity_file"
      case engine
      case metadata
      case payload
      case repairManifest = "repair_manifest"
    }
  }

  private struct ImportedArtifactRecord: Decodable {
    let fileName: String
    let digest: String
    let sizeBytes: UInt64

    enum CodingKeys: String, CodingKey {
      case fileName = "file_name"
      case digest
      case sizeBytes = "size_bytes"
    }
  }

  private struct ImportedRequest: Decodable {
    let format: Int
    let operation: String
    let planDigest: String
    let deviceIdentifier: String
    let storeIdentifier: String
    let layoutDigest: String
    let candidateKind: String
    let sourceIdentifier: String
    let offsetBytes: UInt64
    let lengthBytes: UInt64
    let engineVersion: String
    let requiredHumanSteps: [String]

    enum CodingKeys: String, CodingKey {
      case format
      case operation
      case planDigest = "plan_digest"
      case deviceIdentifier = "device_identifier"
      case storeIdentifier = "store_identifier"
      case layoutDigest = "layout_digest"
      case candidateKind = "candidate_kind"
      case sourceIdentifier = "source_identifier"
      case offsetBytes = "offset_bytes"
      case lengthBytes = "length_bytes"
      case engineVersion = "engine_version"
      case requiredHumanSteps = "required_human_steps"
    }
  }

  private struct ImportedIdentity: Decodable {
    let format: Int
    let bindingDigest: String
    let trustRootFingerprint: String
    let catalogSequence: UInt64
    let catalogPayloadDigest: String
    let planDigest: String
    let engineDigest: String
    let metadataDigest: String
    let payloadDigest: String
    let repairManifestDigest: String?

    enum CodingKeys: String, CodingKey {
      case format
      case bindingDigest = "binding_digest"
      case trustRootFingerprint = "trust_root_fingerprint"
      case catalogSequence = "catalog_sequence"
      case catalogPayloadDigest = "catalog_payload_digest"
      case planDigest = "plan_digest"
      case engineDigest = "engine_digest"
      case metadataDigest = "metadata_digest"
      case payloadDigest = "payload_digest"
      case repairManifestDigest = "repair_manifest_digest"
    }
  }
#endif
