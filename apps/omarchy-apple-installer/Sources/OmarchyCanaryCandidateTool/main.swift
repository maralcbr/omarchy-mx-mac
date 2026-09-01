import CryptoKit
import Darwin
import Foundation
import OmarchyAppleInstallerTrustCore

private enum ToolError: Error, CustomStringConvertible {
  case usage
  case unsafePath(String)
  case invalidSpecification

  var description: String {
    switch self {
    case .usage:
      return
        "usage: OmarchyCanaryCandidateTool generate-key <private-key> <public-key> | sign-receipt <receipt.json> <private-key> <signed-receipt.json> | prepare <spec.json> <private-key> <output-directory>"
    case .unsafePath(let role):
      return "unsafe \(role)"
    case .invalidSpecification:
      return "invalid canary specification"
    }
  }
}

private struct ArtifactSource: Codable {
  let artifact: CanaryArtifact
  let sourcePath: String
}

private struct PreparationSpecification: Codable {
  let changeSet: CanaryChangeSet
  let repairManifestSourcePath: String
  let changedArtifactSources: [ArtifactSource]
  let expectedTrustRootFingerprint: String
}

@main
private enum OmarchyCanaryCandidateTool {
  static func main() {
    do {
      try run(Array(CommandLine.arguments.dropFirst()))
    } catch {
      fputs("Omarchy canary candidate tool failed: \(error)\n", stderr)
      exit(1)
    }
  }

  private static func run(_ arguments: [String]) throws {
    guard let command = arguments.first else {
      throw ToolError.usage
    }
    switch command {
    case "generate-key":
      guard arguments.count == 3 else { throw ToolError.usage }
      try generateKey(
        privateKeyURL: fileURL(arguments[1]),
        publicKeyURL: fileURL(arguments[2])
      )
    case "prepare":
      guard arguments.count == 4 else { throw ToolError.usage }
      try prepare(
        specificationURL: fileURL(arguments[1]),
        privateKeyURL: fileURL(arguments[2]),
        outputURL: fileURL(arguments[3])
      )
    case "sign-receipt":
      guard arguments.count == 4 else { throw ToolError.usage }
      try signReceipt(
        receiptURL: fileURL(arguments[1]),
        privateKeyURL: fileURL(arguments[2]),
        outputURL: fileURL(arguments[3])
      )
    default:
      throw ToolError.usage
    }
  }

  private static func signReceipt(
    receiptURL: URL,
    privateKeyURL: URL,
    outputURL: URL
  ) throws {
    try requireNewRegularFilePath(outputURL, role: "signed receipt path")
    let receiptData = try readSmallRegularFile(
      receiptURL,
      role: "payload receipt",
      maximumBytes: 65_536,
      requirePrivateMode: false
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard
      let receipt = try? decoder.decode(
        CanaryPayloadCacheReceipt.self,
        from: receiptData
      )
    else {
      throw ToolError.invalidSpecification
    }
    let privateKeyData = try readSmallRegularFile(
      privateKeyURL,
      role: "private key",
      maximumBytes: 32,
      requirePrivateMode: true
    )
    guard privateKeyData.count == 32,
      let signer = try? Curve25519.Signing.PrivateKey(
        rawRepresentation: privateKeyData
      )
    else {
      throw ToolError.unsafePath("private key")
    }
    let signed = SignedCanaryPayloadReceipt(
      receipt: receipt,
      signature: try signer.signature(for: receipt.canonicalData()),
      publicKey: signer.publicKey.rawRepresentation
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let signedData = try encoder.encode(signed)
    try signedData.write(to: outputURL, options: .withoutOverwriting)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o400],
      ofItemAtPath: outputURL.path
    )
    print("CANARY — NOT FOR RELEASE")
    print("signed_payload_receipt=\(outputURL.path)")
    print("signed_payload_receipt_digest=\(SHA256Digest(hashing: signedData))")
  }

  private static func generateKey(
    privateKeyURL: URL,
    publicKeyURL: URL
  ) throws {
    try requireNewRegularFilePath(privateKeyURL, role: "private-key path")
    try requireNewRegularFilePath(publicKeyURL, role: "public-key path")
    let key = Curve25519.Signing.PrivateKey()
    try key.rawRepresentation.write(
      to: privateKeyURL,
      options: .withoutOverwriting
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: privateKeyURL.path
    )
    try key.publicKey.rawRepresentation.write(
      to: publicKeyURL,
      options: .withoutOverwriting
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o444],
      ofItemAtPath: publicKeyURL.path
    )
    let fingerprint = SHA256Digest(
      hashing: key.publicKey.rawRepresentation
    ).rawValue
    print("CANARY — NOT FOR RELEASE")
    print("trust_root_fingerprint=\(fingerprint)")
    print("public_key=\(publicKeyURL.path)")
  }

  private static func prepare(
    specificationURL: URL,
    privateKeyURL: URL,
    outputURL: URL
  ) throws {
    guard outputURL.lastPathComponent.contains("canary-not-for-release") else {
      throw ToolError.unsafePath("output directory name")
    }
    let specificationData = try readSmallRegularFile(
      specificationURL,
      role: "specification",
      maximumBytes: 1_048_576,
      requirePrivateMode: false
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard
      let specification = try? decoder.decode(
        PreparationSpecification.self,
        from: specificationData
      )
    else {
      throw ToolError.invalidSpecification
    }
    let privateKey = try readSmallRegularFile(
      privateKeyURL,
      role: "private key",
      maximumBytes: 32,
      requirePrivateMode: true
    )
    guard privateKey.count == 32 else {
      throw ToolError.unsafePath("private key")
    }
    let builder = try CandidateBuilder(
      canaryPrivateKey: privateKey,
      expectedTrustRootFingerprint:
        specification.expectedTrustRootFingerprint
    )
    let candidate = try builder.prepare(.canary, specification.changeSet)
    var sources = Dictionary(
      uniqueKeysWithValues: specification.changedArtifactSources.map {
        ($0.artifact.relativePath, fileURL($0.sourcePath))
      }
    )
    guard
      specification.changedArtifactSources.map(\.artifact)
        == specification.changeSet.changedArtifacts
    else {
      throw ToolError.invalidSpecification
    }
    sources[specification.changeSet.repairManifest.relativePath] = fileURL(
      specification.repairManifestSourcePath
    )
    let report = try CanaryCandidateBundleWriter().write(
      candidate,
      sources: sources,
      to: outputURL
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(report), as: UTF8.self))
  }

  private static func readSmallRegularFile(
    _ url: URL,
    role: String,
    maximumBytes: Int,
    requirePrivateMode: Bool
  ) throws -> Data {
    let values = try url.resourceValues(forKeys: [
      .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
    ])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
      let size = values.fileSize, size > 0, size <= maximumBytes
    else {
      throw ToolError.unsafePath(role)
    }
    var details = stat()
    guard lstat(url.path, &details) == 0, (details.st_mode & S_IFMT) == S_IFREG else {
      throw ToolError.unsafePath(role)
    }
    if requirePrivateMode {
      guard details.st_uid == geteuid(), details.st_mode & 0o077 == 0 else {
        throw ToolError.unsafePath(role)
      }
    }
    let data = try Data(contentsOf: url)
    guard data.count == size else { throw ToolError.unsafePath(role) }
    return data
  }

  private static func requireNewRegularFilePath(
    _ url: URL,
    role: String
  ) throws {
    guard url.isFileURL,
      !FileManager.default.fileExists(atPath: url.path),
      FileManager.default.fileExists(
        atPath: url.deletingLastPathComponent().path
      )
    else {
      throw ToolError.unsafePath(role)
    }
  }

  private static func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: path).standardizedFileURL
  }
}
