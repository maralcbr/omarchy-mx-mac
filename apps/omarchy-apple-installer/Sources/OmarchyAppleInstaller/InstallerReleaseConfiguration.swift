#if os(macOS)
  import Darwin
  import Foundation

  public enum InstallerReleaseConfigurationError:
    Error, Equatable, Sendable
  {
    case invalidDescriptor
    case unsupportedSchema(Int)
    case invalidURL(String)
    case invalidTrustRoot
    case invalidHelperIdentity
    case unexpectedHTTPStatus(Int)
    case oversizedDocument(String)
    case invalidCatalogSignature
    case releaseResourcesUnavailable
    case unsafeReleaseResource(String)
  }

  public struct InstallerReleaseConfiguration: Sendable {
    public let catalogURL: URL
    public let catalogSignatureURL: URL
    public let trustRoot: AppOwnedTrustRoot
    public let helperMachServiceName: String
    public let helperCodeSigningRequirement: String
    public let sealedCatalogDocuments: InstallerReleaseCatalogDocuments?

    public init(
      catalogURL: URL,
      catalogSignatureURL: URL,
      trustRoot: AppOwnedTrustRoot,
      helperMachServiceName: String,
      helperCodeSigningRequirement: String,
      sealedCatalogDocuments: InstallerReleaseCatalogDocuments? = nil
    ) {
      self.catalogURL = catalogURL
      self.catalogSignatureURL = catalogSignatureURL
      self.trustRoot = trustRoot
      self.helperMachServiceName = helperMachServiceName
      self.helperCodeSigningRequirement = helperCodeSigningRequirement
      self.sealedCatalogDocuments = sealedCatalogDocuments
    }
  }

  public struct InstallerReleaseConfigurationLoader: Sendable {
    public static let maximumDescriptorBytes = 65_536

    public init() {}

    public func load(
      descriptor: Data,
      trustRootPublicKey: Data
    ) throws -> InstallerReleaseConfiguration {
      guard !descriptor.isEmpty,
        descriptor.count <= Self.maximumDescriptorBytes,
        trustRootPublicKey.count == 32,
        let object = try? JSONSerialization.jsonObject(with: descriptor),
        let dictionary = object as? [String: Any],
        Set(dictionary.keys) == Set(ReleaseDescriptor.CodingKeys.allCases.map(\.rawValue))
      else {
        throw InstallerReleaseConfigurationError.invalidDescriptor
      }

      let decoded: ReleaseDescriptor
      do {
        decoded = try JSONDecoder().decode(
          ReleaseDescriptor.self,
          from: descriptor
        )
      } catch {
        throw InstallerReleaseConfigurationError.invalidDescriptor
      }
      guard decoded.schemaVersion == 1 else {
        throw InstallerReleaseConfigurationError.unsupportedSchema(
          decoded.schemaVersion
        )
      }
      try validateURL(decoded.catalogURL, field: "catalog_url")
      try validateURL(
        decoded.catalogSignatureURL,
        field: "catalog_signature_url"
      )

      let trustRoot: AppOwnedTrustRoot
      do {
        trustRoot = try AppOwnedTrustRoot(
          rawRepresentation: trustRootPublicKey,
          expectedFingerprint: decoded.trustRootFingerprint
        )
      } catch {
        throw InstallerReleaseConfigurationError.invalidTrustRoot
      }
      guard
        AuthenticatedEngineXPCSubmitter.isMachServiceName(
          decoded.helperMachServiceName
        ),
        decoded.helperMachServiceName
          == InstallerProductIdentity.helperMachServiceName,
        EngineCodeSigningRequirement.isValid(
          decoded.helperCodeSigningRequirement
        )
      else {
        throw InstallerReleaseConfigurationError.invalidHelperIdentity
      }

      return InstallerReleaseConfiguration(
        catalogURL: decoded.catalogURL,
        catalogSignatureURL: decoded.catalogSignatureURL,
        trustRoot: trustRoot,
        helperMachServiceName: decoded.helperMachServiceName,
        helperCodeSigningRequirement: decoded.helperCodeSigningRequirement,
        sealedCatalogDocuments: nil
      )
    }

    private func validateURL(_ url: URL, field: String) throws {
      guard url.scheme == "https",
        url.host?.isEmpty == false,
        url.user == nil,
        url.password == nil,
        url.fragment == nil
      else {
        throw InstallerReleaseConfigurationError.invalidURL(field)
      }
    }
  }

  public struct InstallerReleaseConfigurationLocator: Sendable {
    public static let descriptorFileName = "release.json"
    public static let trustRootFileName = "trust-root.ed25519.pub"
    public static let sealedCatalogFileName = "catalog.json"
    public static let sealedCatalogSignatureFileName = "catalog.json.sig"

    public init() {}

    public func loadFromMainBundle() throws
      -> InstallerReleaseConfiguration
    {
      guard let resources = Bundle.main.resourceURL else {
        throw InstallerReleaseConfigurationError.releaseResourcesUnavailable
      }
      return try load(
        from: resources.appendingPathComponent(
          "Release",
          isDirectory: true
        )
      )
    }

    func load(from releaseDirectory: URL) throws
      -> InstallerReleaseConfiguration
    {
      try validateDirectory(releaseDirectory)
      let descriptor = try readRegularFile(
        releaseDirectory.appendingPathComponent(Self.descriptorFileName),
        maximumBytes: InstallerReleaseConfigurationLoader.maximumDescriptorBytes,
        role: "release-descriptor"
      )
      let trustRoot = try readRegularFile(
        releaseDirectory.appendingPathComponent(Self.trustRootFileName),
        maximumBytes: 32,
        role: "trust-root"
      )
      let configuration = try InstallerReleaseConfigurationLoader().load(
        descriptor: descriptor,
        trustRootPublicKey: trustRoot
      )
      let sealedCatalogDocuments = try loadSealedCatalogDocuments(
        from: releaseDirectory
      )
      return InstallerReleaseConfiguration(
        catalogURL: configuration.catalogURL,
        catalogSignatureURL: configuration.catalogSignatureURL,
        trustRoot: configuration.trustRoot,
        helperMachServiceName: configuration.helperMachServiceName,
        helperCodeSigningRequirement:
          configuration.helperCodeSigningRequirement,
        sealedCatalogDocuments: sealedCatalogDocuments
      )
    }

    private func loadSealedCatalogDocuments(
      from releaseDirectory: URL
    ) throws -> InstallerReleaseCatalogDocuments? {
      let payloadURL = releaseDirectory.appendingPathComponent(
        Self.sealedCatalogFileName
      )
      let signatureURL = releaseDirectory.appendingPathComponent(
        Self.sealedCatalogSignatureFileName
      )
      let hasPayload = try resourceExists(
        payloadURL,
        role: "sealed-catalog"
      )
      let hasSignature = try resourceExists(
        signatureURL,
        role: "sealed-catalog-signature"
      )
      guard hasPayload || hasSignature else {
        return nil
      }
      guard hasPayload && hasSignature else {
        throw InstallerReleaseConfigurationError.unsafeReleaseResource(
          "sealed-catalog-pair"
        )
      }

      let payload = try readRegularFile(
        payloadURL,
        maximumBytes:
          InstallerReleaseCatalogFetcher.maximumCatalogBytes,
        role: "sealed-catalog"
      )
      let signature = try readRegularFile(
        signatureURL,
        maximumBytes: InstallerReleaseCatalogFetcher.signatureBytes,
        role: "sealed-catalog-signature"
      )
      guard signature.count == InstallerReleaseCatalogFetcher.signatureBytes
      else {
        throw InstallerReleaseConfigurationError.invalidCatalogSignature
      }
      return InstallerReleaseCatalogDocuments(
        payload: payload,
        signature: signature
      )
    }

    private func resourceExists(
      _ url: URL,
      role: String
    ) throws -> Bool {
      var status = stat()
      if lstat(url.path, &status) == 0 {
        return true
      }
      guard errno == ENOENT else {
        throw InstallerReleaseConfigurationError.unsafeReleaseResource(role)
      }
      return false
    }

    private func validateDirectory(_ directory: URL) throws {
      var status = stat()
      guard lstat(directory.path, &status) == 0,
        (status.st_mode & S_IFMT) == S_IFDIR,
        status.st_mode & 0o022 == 0
      else {
        throw InstallerReleaseConfigurationError.releaseResourcesUnavailable
      }
    }

    private func readRegularFile(
      _ url: URL,
      maximumBytes: Int,
      role: String
    ) throws -> Data {
      let descriptor = Darwin.open(
        url.path,
        O_RDONLY | O_CLOEXEC | O_NOFOLLOW
      )
      guard descriptor >= 0 else {
        throw InstallerReleaseConfigurationError.unsafeReleaseResource(role)
      }
      defer { Darwin.close(descriptor) }

      var status = stat()
      guard fstat(descriptor, &status) == 0,
        (status.st_mode & S_IFMT) == S_IFREG,
        status.st_mode & 0o022 == 0,
        status.st_size > 0,
        status.st_size <= maximumBytes
      else {
        throw InstallerReleaseConfigurationError.unsafeReleaseResource(role)
      }
      let handle = FileHandle(
        fileDescriptor: descriptor,
        closeOnDealloc: false
      )
      guard let data = try handle.readToEnd(),
        data.count == Int(status.st_size)
      else {
        throw InstallerReleaseConfigurationError.unsafeReleaseResource(role)
      }
      return data
    }
  }

  public struct InstallerReleaseCatalogDocuments: Sendable {
    public let payload: Data
    public let signature: Data
  }

  public struct InstallerReleaseCatalogFetcher: Sendable {
    public static let maximumCatalogBytes = 1_048_576
    public static let signatureBytes = 64

    private let downloader: any ReleaseDocumentDownloading

    public init() {
      downloader = URLSessionReleaseDocumentDownloader()
    }

    init(downloader: any ReleaseDocumentDownloading) {
      self.downloader = downloader
    }

    public func fetch(
      configuration: InstallerReleaseConfiguration
    ) async throws -> InstallerReleaseCatalogDocuments {
      if let sealed = configuration.sealedCatalogDocuments {
        guard !sealed.payload.isEmpty,
          sealed.payload.count <= Self.maximumCatalogBytes
        else {
          throw InstallerReleaseConfigurationError.oversizedDocument(
            "catalog"
          )
        }
        guard sealed.signature.count == Self.signatureBytes else {
          throw InstallerReleaseConfigurationError.invalidCatalogSignature
        }
        return sealed
      }

      async let payload = downloader.download(
        from: configuration.catalogURL,
        maximumBytes: Self.maximumCatalogBytes,
        role: "catalog"
      )
      async let signature = downloader.download(
        from: configuration.catalogSignatureURL,
        maximumBytes: Self.signatureBytes,
        role: "catalog-signature"
      )
      let documents = try await (payload, signature)
      guard documents.1.count == Self.signatureBytes else {
        throw InstallerReleaseConfigurationError.invalidCatalogSignature
      }
      return InstallerReleaseCatalogDocuments(
        payload: documents.0,
        signature: documents.1
      )
    }
  }

  protocol ReleaseDocumentDownloading: Sendable {
    func download(
      from url: URL,
      maximumBytes: Int,
      role: String
    ) async throws -> Data
  }

  struct URLSessionReleaseDocumentDownloader:
    ReleaseDocumentDownloading, Sendable
  {
    func download(
      from url: URL,
      maximumBytes: Int,
      role: String
    ) async throws -> Data {
      let (bytes, response) = try await URLSession.shared.bytes(from: url)
      guard let response = response as? HTTPURLResponse,
        (200...299).contains(response.statusCode)
      else {
        throw InstallerReleaseConfigurationError.unexpectedHTTPStatus(
          (response as? HTTPURLResponse)?.statusCode ?? 0
        )
      }
      guard let finalURL = response.url,
        finalURL.scheme == "https",
        finalURL.host?.isEmpty == false,
        finalURL.user == nil,
        finalURL.password == nil,
        finalURL.fragment == nil
      else {
        throw InstallerReleaseConfigurationError.invalidURL(role)
      }
      let expectedLength = response.expectedContentLength
      guard expectedLength <= Int64(maximumBytes) else {
        throw InstallerReleaseConfigurationError.oversizedDocument(role)
      }

      var data = Data()
      if expectedLength > 0 {
        data.reserveCapacity(Int(expectedLength))
      }
      for try await byte in bytes {
        guard data.count < maximumBytes else {
          throw InstallerReleaseConfigurationError.oversizedDocument(role)
        }
        data.append(byte)
      }
      guard !data.isEmpty else {
        throw InstallerReleaseConfigurationError.oversizedDocument(role)
      }
      return data
    }
  }

  private struct ReleaseDescriptor: Decodable {
    let schemaVersion: Int
    let catalogURL: URL
    let catalogSignatureURL: URL
    let trustRootFingerprint: String
    let helperMachServiceName: String
    let helperCodeSigningRequirement: String

    enum CodingKeys: String, CodingKey, CaseIterable {
      case schemaVersion = "schema_version"
      case catalogURL = "catalog_url"
      case catalogSignatureURL = "catalog_signature_url"
      case trustRootFingerprint = "trust_root_fingerprint"
      case helperMachServiceName = "helper_mach_service_name"
      case helperCodeSigningRequirement = "helper_code_signing_requirement"
    }
  }
#endif
