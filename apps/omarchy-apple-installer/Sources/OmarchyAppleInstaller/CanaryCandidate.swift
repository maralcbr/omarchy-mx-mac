import CryptoKit
import Darwin
import Foundation

public enum CandidateKind: String, Codable, Equatable, Sendable {
  case canary
  case release
}

public struct CanaryPreparation: Equatable, Sendable {
  public static let canary = CanaryPreparation()
  public let kind = CandidateKind.canary
}

public struct ReleasePreparation: Equatable, Sendable {
  public static let release = ReleasePreparation()
  public let kind = CandidateKind.release
}

public enum CandidatePreparation {
  public static let canary = CanaryPreparation()
  public static let release = ReleasePreparation()
}

public struct CanaryArtifact: Codable, Equatable, Sendable {
  public var relativePath: String
  public var digest: String
  public var sizeBytes: UInt64

  public init(relativePath: String, digest: String, sizeBytes: UInt64) {
    self.relativePath = relativePath
    self.digest = digest
    self.sizeBytes = sizeBytes
  }
}

public struct CanaryPayloadIdentity: Codable, Equatable, Sendable {
  public var digest: String
  public var sizeBytes: UInt64

  public init(digest: String, sizeBytes: UInt64) {
    self.digest = digest
    self.sizeBytes = sizeBytes
  }
}

public struct CanaryEnrollment: Codable, Equatable, Sendable {
  public var hardwareModel: String
  public var deviceIdentifier: String
  public var enrolledDeviceIdentityDigest: String
  public var diskIdentifier: String
  public var layoutDigest: String
  public var partitionIdentifiers: [String]

  public init(
    hardwareModel: String,
    deviceIdentifier: String,
    enrolledDeviceIdentityDigest: String,
    diskIdentifier: String,
    layoutDigest: String,
    partitionIdentifiers: [String]
  ) {
    self.hardwareModel = hardwareModel
    self.deviceIdentifier = deviceIdentifier
    self.enrolledDeviceIdentityDigest = enrolledDeviceIdentityDigest
    self.diskIdentifier = diskIdentifier
    self.layoutDigest = layoutDigest
    self.partitionIdentifiers = partitionIdentifiers
  }
}

public struct CanaryChangeSet: Codable, Sendable {
  public var sequence: UInt64
  public var expiresAt: Date
  public var sourceTreeDigest: String
  public var operation: String
  public var enrollment: CanaryEnrollment
  public var payload: CanaryPayloadIdentity
  public var repairManifest: CanaryArtifact
  public var changedArtifacts: [CanaryArtifact]

  public init(
    sequence: UInt64,
    expiresAt: Date,
    sourceTreeDigest: String,
    operation: String,
    enrollment: CanaryEnrollment,
    payload: CanaryPayloadIdentity,
    repairManifest: CanaryArtifact,
    changedArtifacts: [CanaryArtifact]
  ) {
    self.sequence = sequence
    self.expiresAt = expiresAt
    self.sourceTreeDigest = sourceTreeDigest
    self.operation = operation
    self.enrollment = enrollment
    self.payload = payload
    self.repairManifest = repairManifest
    self.changedArtifacts = changedArtifacts
  }
}

public enum CandidateError: Error, Equatable, Sendable {
  case invalidTrustRoot
  case invalidIdentity
  case unsafeOperation
  case expired
  case expiryTooLong
  case unsafeArtifact
  case duplicateArtifact
  case invalidSignature
  case nonReleaseCandidate
  case incompletePayloadReceipt
  case payloadReceiptMismatch
  case unsafePayloadCache
  case stalePayloadReceipt
  case sequenceRollback
  case enrollmentMismatch
}

public struct CanaryCandidate: Sendable {
  public let kind = CandidateKind.canary
  public let marker = "CANARY — NOT FOR RELEASE"
  public let operation: String
  public let payload: CanaryPayloadIdentity
  public let repairManifest: CanaryArtifact
  public let changedArtifacts: [CanaryArtifact]
  public let manifest: Data
  public let signature: Data
  public let publicKey: Data

  public var identityDigest: String {
    SHA256Digest(hashing: manifest).rawValue
  }

  public var transferSizeBytes: UInt64 {
    changedArtifacts.reduce(
      UInt64(manifest.count + signature.count + publicKey.count)
        + repairManifest.sizeBytes
    ) {
      $0 + $1.sizeBytes
    }
  }

  public var bundleFiles: [URL] {
    [URL(fileURLWithPath: "canary-candidate.json"), URL(fileURLWithPath: "canary-candidate.sig")]
      + [URL(fileURLWithPath: repairManifest.relativePath)]
      + changedArtifacts.map { URL(fileURLWithPath: $0.relativePath) }
  }

  public func verifySignature() throws -> Bool {
    guard
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
      key.isValidSignature(signature, for: manifest)
    else {
      throw CandidateError.invalidSignature
    }
    return true
  }
}

public struct ReleaseCandidate: Sendable {
  public let kind = CandidateKind.release

  public init() {}
}

public struct CandidateBuilder: Sendable {
  private let signer: Curve25519.Signing.PrivateKey
  private let trustRootFingerprint: String
  private let now: @Sendable () -> Date

  public init(
    canaryPrivateKey: Data,
    expectedTrustRootFingerprint: String,
    now: @escaping @Sendable () -> Date = Date.init
  ) throws {
    guard
      let signer = try? Curve25519.Signing.PrivateKey(
        rawRepresentation: canaryPrivateKey
      ),
      SHA256Digest(rawValue: expectedTrustRootFingerprint) != nil,
      SHA256Digest(hashing: signer.publicKey.rawRepresentation).rawValue
        == expectedTrustRootFingerprint
    else {
      throw CandidateError.invalidTrustRoot
    }
    self.signer = signer
    trustRootFingerprint = expectedTrustRootFingerprint
    self.now = now
  }

  public func prepare(
    _ mode: CanaryPreparation,
    _ changeSet: CanaryChangeSet
  ) throws -> CanaryCandidate {
    let issuedAt = now()
    guard changeSet.operation == "repair-installed-system" else {
      throw CandidateError.unsafeOperation
    }
    guard issuedAt < changeSet.expiresAt else {
      throw CandidateError.expired
    }
    guard changeSet.expiresAt.timeIntervalSince(issuedAt) <= 3_600 else {
      throw CandidateError.expiryTooLong
    }
    guard changeSet.sequence > 0,
      isDigest(changeSet.sourceTreeDigest),
      isDigest(changeSet.payload.digest),
      changeSet.payload.sizeBytes > 0,
      changeSet.enrollment.hardwareModel == "MacBookPro18,3",
      changeSet.enrollment.deviceIdentifier == "apple,j314s",
      isDigest(changeSet.enrollment.enrolledDeviceIdentityDigest),
      changeSet.enrollment.diskIdentifier == "disk0",
      isDigest(changeSet.enrollment.layoutDigest),
      changeSet.enrollment.partitionIdentifiers
        == ["disk0s3", "disk0s4", "disk0s5", "disk0s6"]
    else {
      throw CandidateError.invalidIdentity
    }
    let allArtifacts = [changeSet.repairManifest] + changeSet.changedArtifacts
    guard
      isSafeArtifact(
        changeSet.repairManifest,
        maximumBytes: 1_048_576
      ),
      changeSet.changedArtifacts.allSatisfy({
        isSafeArtifact($0, maximumBytes: 134_217_728)
      })
    else {
      throw CandidateError.unsafeArtifact
    }
    guard Set(allArtifacts.map(\.relativePath)).count == allArtifacts.count else {
      throw CandidateError.duplicateArtifact
    }

    let envelope = CanaryEnvelope(
      format: 1,
      candidateKind: mode.kind,
      marker: "CANARY — NOT FOR RELEASE",
      operation: changeSet.operation,
      sequence: changeSet.sequence,
      issuedAt: issuedAt,
      expiresAt: changeSet.expiresAt,
      trustRootFingerprint: trustRootFingerprint,
      sourceTreeDigest: changeSet.sourceTreeDigest,
      enrollment: changeSet.enrollment,
      payload: changeSet.payload,
      repairManifest: changeSet.repairManifest,
      changedArtifacts: changeSet.changedArtifacts
    )
    let manifest = try encodeCanonical(envelope)
    return CanaryCandidate(
      operation: changeSet.operation,
      payload: changeSet.payload,
      repairManifest: changeSet.repairManifest,
      changedArtifacts: changeSet.changedArtifacts,
      manifest: manifest,
      signature: try signer.signature(for: manifest),
      publicKey: signer.publicKey.rawRepresentation
    )
  }

  private func isSafeArtifact(
    _ artifact: CanaryArtifact,
    maximumBytes: UInt64
  ) -> Bool {
    !artifact.relativePath.isEmpty && !artifact.relativePath.hasPrefix("/")
      && !artifact.relativePath.split(separator: "/").contains("..")
      && isDigest(artifact.digest) && artifact.sizeBytes > 0
      && artifact.sizeBytes <= maximumBytes
  }
}

public struct CanaryReplayGuard: Equatable, Sendable {
  public private(set) var lastAcceptedSequence: UInt64

  public init(lastAcceptedSequence: UInt64 = 0) {
    self.lastAcceptedSequence = lastAcceptedSequence
  }

  mutating func accept(_ sequence: UInt64) throws {
    guard sequence > lastAcceptedSequence else {
      throw CandidateError.sequenceRollback
    }
    lastAcceptedSequence = sequence
  }
}

public struct CanaryCandidateVerifier: Sendable {
  private let publicKey: Curve25519.Signing.PublicKey
  private let trustRootFingerprint: String
  private let now: @Sendable () -> Date

  public init(
    publicKey: Data,
    expectedTrustRootFingerprint: String,
    now: @escaping @Sendable () -> Date = Date.init
  ) throws {
    guard
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
      SHA256Digest(hashing: key.rawRepresentation).rawValue
        == expectedTrustRootFingerprint
    else {
      throw CandidateError.invalidTrustRoot
    }
    self.publicKey = key
    trustRootFingerprint = expectedTrustRootFingerprint
    self.now = now
  }

  public func verify(
    _ candidate: CanaryCandidate,
    replayGuard: inout CanaryReplayGuard
  ) throws -> AdmittedCanaryCandidate {
    guard candidate.publicKey == publicKey.rawRepresentation,
      publicKey.isValidSignature(candidate.signature, for: candidate.manifest)
    else {
      throw CandidateError.invalidSignature
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard
      let envelope = try? decoder.decode(
        CanaryEnvelope.self,
        from: candidate.manifest
      )
    else {
      throw CandidateError.invalidIdentity
    }
    guard envelope.format == 1,
      envelope.candidateKind == .canary,
      envelope.marker == "CANARY — NOT FOR RELEASE",
      envelope.operation == "repair-installed-system",
      envelope.trustRootFingerprint == trustRootFingerprint,
      envelope.operation == candidate.operation,
      envelope.payload == candidate.payload,
      envelope.repairManifest == candidate.repairManifest,
      envelope.changedArtifacts == candidate.changedArtifacts
    else {
      throw CandidateError.invalidIdentity
    }
    let current = now()
    guard envelope.issuedAt <= current, current < envelope.expiresAt,
      envelope.expiresAt.timeIntervalSince(envelope.issuedAt) <= 3_600
    else {
      throw CandidateError.expired
    }
    try replayGuard.accept(envelope.sequence)
    return AdmittedCanaryCandidate(
      marker: envelope.marker,
      operation: envelope.operation,
      sequence: envelope.sequence,
      identityDigest: candidate.identityDigest,
      enrollment: envelope.enrollment,
      payload: envelope.payload,
      repairManifest: envelope.repairManifest
    )
  }
}

public struct AdmittedCanaryCandidate: Equatable, Sendable {
  public let marker: String
  public let operation: String
  public let sequence: UInt64
  public let identityDigest: String
  public let enrollment: CanaryEnrollment
  public let payload: CanaryPayloadIdentity
  public let repairManifest: CanaryArtifact
}

public struct CanaryAdmissionAdapter: Sendable {
  private let candidateVerifier: CanaryCandidateVerifier
  private let cacheVerifier: CanaryPayloadCacheVerifier

  public init(
    publicKey: Data,
    expectedTrustRootFingerprint: String,
    now: @escaping @Sendable () -> Date = Date.init
  ) throws {
    candidateVerifier = try CanaryCandidateVerifier(
      publicKey: publicKey,
      expectedTrustRootFingerprint: expectedTrustRootFingerprint,
      now: now
    )
    cacheVerifier = try CanaryPayloadCacheVerifier(
      publicKey: publicKey,
      expectedTrustRootFingerprint: expectedTrustRootFingerprint,
      now: now
    )
  }

  public func admit(
    _ candidate: CanaryCandidate,
    observedEnrollment: CanaryEnrollment,
    payloadReceipt: SignedCanaryPayloadReceipt,
    replayGuard: inout CanaryReplayGuard
  ) throws -> AdmittedCanaryCandidate {
    var proposedGuard = replayGuard
    let admitted = try candidateVerifier.verify(
      candidate,
      replayGuard: &proposedGuard
    )
    guard admitted.enrollment == observedEnrollment else {
      throw CandidateError.enrollmentMismatch
    }
    try cacheVerifier.verify(payloadReceipt, expected: admitted.payload)
    replayGuard = proposedGuard
    return admitted
  }
}

public struct CanaryBundlePhase: Codable, Equatable, Sendable {
  public let name: String
  public let elapsedMilliseconds: UInt64
  public let bytesWritten: UInt64
}

public struct CanaryBundleReport: Codable, Equatable, Sendable {
  public let marker: String
  public let candidateIdentityDigest: String
  public let bundleBytes: UInt64
  public let reusedPayloadBytes: UInt64
  public let copiedPayloadBytes: UInt64
  public let cacheDecision: String
  public let fileCount: Int
  public let phases: [CanaryBundlePhase]
}

public struct CanaryCandidateBundleWriter: Sendable {
  public init() {}

  public func write(
    _ candidate: CanaryCandidate,
    sources: [String: URL],
    to output: URL
  ) throws -> CanaryBundleReport {
    let manager = FileManager.default
    guard output.isFileURL, !manager.fileExists(atPath: output.path) else {
      throw CandidateError.unsafeArtifact
    }
    try manager.createDirectory(
      at: output,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )

    var phaseStarted = Date()
    let artifacts = [candidate.repairManifest] + candidate.changedArtifacts
    var bundleBytes = UInt64(
      candidate.manifest.count + candidate.signature.count
        + candidate.publicKey.count
    )
    for artifact in artifacts {
      guard let source = sources[artifact.relativePath], source.isFileURL,
        let values = try? source.resourceValues(forKeys: [
          .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ]),
        values.isRegularFile == true, values.isSymbolicLink != true,
        values.fileSize == Int(artifact.sizeBytes),
        let data = try? Data(contentsOf: source),
        UInt64(data.count) == artifact.sizeBytes,
        SHA256Digest(hashing: data).rawValue == artifact.digest
      else {
        throw CandidateError.unsafeArtifact
      }
      let destination = output.appendingPathComponent(artifact.relativePath)
      try manager.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try data.write(to: destination, options: .withoutOverwriting)
      try manager.setAttributes(
        [.posixPermissions: 0o400],
        ofItemAtPath: destination.path
      )
      bundleBytes += artifact.sizeBytes
    }
    let artifactBytes = artifacts.reduce(UInt64(0)) { $0 + $1.sizeBytes }
    let artifactPhase = CanaryBundlePhase(
      name: "stage-declared-artifacts",
      elapsedMilliseconds: elapsedMilliseconds(since: phaseStarted),
      bytesWritten: artifactBytes
    )

    phaseStarted = Date()
    let fixedFiles: [(String, Data)] = [
      ("canary-candidate.json", candidate.manifest),
      ("canary-candidate.sig", candidate.signature),
      ("canary-trust-root.pub", candidate.publicKey),
    ]
    for (name, data) in fixedFiles {
      let destination = output.appendingPathComponent(name)
      try data.write(to: destination, options: .withoutOverwriting)
      try manager.setAttributes(
        [.posixPermissions: 0o400],
        ofItemAtPath: destination.path
      )
    }
    let metadataBytes = fixedFiles.reduce(UInt64(0)) {
      $0 + UInt64($1.1.count)
    }
    let metadataPhase = CanaryBundlePhase(
      name: "write-signed-metadata",
      elapsedMilliseconds: elapsedMilliseconds(since: phaseStarted),
      bytesWritten: metadataBytes
    )
    phaseStarted = Date()
    let report = CanaryBundleReport(
      marker: candidate.marker,
      candidateIdentityDigest: candidate.identityDigest,
      bundleBytes: bundleBytes,
      reusedPayloadBytes: candidate.payload.sizeBytes,
      copiedPayloadBytes: 0,
      cacheDecision: "reuse-verified-content-addressed-payload",
      fileCount: artifacts.count + fixedFiles.count + 1,
      phases: [
        artifactPhase,
        metadataPhase,
        CanaryBundlePhase(
          name: "record-cache-decision",
          elapsedMilliseconds: elapsedMilliseconds(since: phaseStarted),
          bytesWritten: 0
        ),
      ]
    )
    let reportURL = output.appendingPathComponent("canary-report.json")
    try encodeCanonical(report).write(
      to: reportURL,
      options: .withoutOverwriting
    )
    try manager.setAttributes(
      [.posixPermissions: 0o400],
      ofItemAtPath: reportURL.path
    )
    return report
  }

  private func elapsedMilliseconds(since start: Date) -> UInt64 {
    UInt64(max(0, Date().timeIntervalSince(start) * 1_000))
  }
}

public struct CanaryCandidateBundleReader: Sendable {
  public init() {}

  public func read(from bundle: URL) throws -> CanaryCandidate {
    guard bundle.isFileURL else { throw CandidateError.unsafeArtifact }
    var bundleStatus = stat()
    guard lstat(bundle.path, &bundleStatus) == 0,
      (bundleStatus.st_mode & S_IFMT) == S_IFDIR,
      bundleStatus.st_mode & 0o022 == 0
    else {
      throw CandidateError.unsafeArtifact
    }

    let manifest = try readRegularFile(
      bundle.appendingPathComponent("canary-candidate.json"),
      maximumBytes: 1_048_576
    )
    let signature = try readRegularFile(
      bundle.appendingPathComponent("canary-candidate.sig"),
      maximumBytes: 64
    )
    let publicKey = try readRegularFile(
      bundle.appendingPathComponent("canary-trust-root.pub"),
      maximumBytes: 32
    )
    guard signature.count == 64, publicKey.count == 32 else {
      throw CandidateError.invalidSignature
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard let envelope = try? decoder.decode(CanaryEnvelope.self, from: manifest)
    else {
      throw CandidateError.invalidIdentity
    }
    let candidate = CanaryCandidate(
      operation: envelope.operation,
      payload: envelope.payload,
      repairManifest: envelope.repairManifest,
      changedArtifacts: envelope.changedArtifacts,
      manifest: manifest,
      signature: signature,
      publicKey: publicKey
    )
    _ = try candidate.verifySignature()

    for artifact in [candidate.repairManifest] + candidate.changedArtifacts {
      let maximum: UInt64 =
        artifact == candidate.repairManifest ? 1_048_576 : 134_217_728
      guard artifact.sizeBytes <= maximum else {
        throw CandidateError.unsafeArtifact
      }
      let data = try readRegularFile(
        bundle.appendingPathComponent(artifact.relativePath),
        maximumBytes: Int(maximum)
      )
      guard UInt64(data.count) == artifact.sizeBytes,
        SHA256Digest(hashing: data).rawValue == artifact.digest
      else {
        throw CandidateError.unsafeArtifact
      }
    }
    return candidate
  }

  private func readRegularFile(
    _ url: URL,
    maximumBytes: Int
  ) throws -> Data {
    var status = stat()
    guard lstat(url.path, &status) == 0,
      (status.st_mode & S_IFMT) == S_IFREG,
      status.st_mode & 0o022 == 0,
      status.st_size > 0,
      status.st_size <= maximumBytes
    else {
      throw CandidateError.unsafeArtifact
    }
    let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    guard descriptor >= 0 else { throw CandidateError.unsafeArtifact }
    defer { Darwin.close(descriptor) }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
    guard let data = try handle.readToEnd(), data.count == Int(status.st_size)
    else {
      throw CandidateError.unsafeArtifact
    }
    return data
  }
}

public struct ReleaseCandidateVerifier: Sendable {
  public init() {}

  public func verify(_ manifest: Data) throws {
    let object = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any]
    guard object?["candidate_kind"] as? String == CandidateKind.release.rawValue else {
      throw CandidateError.nonReleaseCandidate
    }
  }
}

public struct CanaryPayloadCacheReceipt: Codable, Equatable, Sendable {
  public var format: Int
  public var completed: Bool
  public var digest: String
  public var sizeBytes: UInt64
  public var path: String
  public var ownerID: UInt32
  public var mode: UInt16
  public var verifiedAt: Date
  public var expiresAt: Date

  private enum CodingKeys: String, CodingKey {
    case format
    case completed
    case digest
    case sizeBytes = "size_bytes"
    case path
    case ownerID = "owner_id"
    case mode
    case verifiedAt = "verified_at"
    case expiresAt = "expires_at"
  }

  public init(
    format: Int,
    completed: Bool,
    digest: String,
    sizeBytes: UInt64,
    path: String,
    ownerID: UInt32,
    mode: UInt16,
    verifiedAt: Date,
    expiresAt: Date
  ) {
    self.format = format
    self.completed = completed
    self.digest = digest
    self.sizeBytes = sizeBytes
    self.path = path
    self.ownerID = ownerID
    self.mode = mode
    self.verifiedAt = verifiedAt
    self.expiresAt = expiresAt
  }

  public func canonicalData() throws -> Data {
    try encodeCanonical(self)
  }
}

public struct SignedCanaryPayloadReceipt: Codable, Sendable {
  public let receipt: CanaryPayloadCacheReceipt
  public let signature: Data
  public let publicKey: Data

  public init(
    receipt: CanaryPayloadCacheReceipt,
    signature: Data,
    publicKey: Data
  ) {
    self.receipt = receipt
    self.signature = signature
    self.publicKey = publicKey
  }
}

public struct CanaryPayloadCacheVerifier: Sendable {
  private let publicKey: Curve25519.Signing.PublicKey
  private let now: @Sendable () -> Date

  public init(
    publicKey: Data,
    expectedTrustRootFingerprint: String,
    now: @escaping @Sendable () -> Date = Date.init
  ) throws {
    guard
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
      SHA256Digest(hashing: key.rawRepresentation).rawValue
        == expectedTrustRootFingerprint
    else {
      throw CandidateError.invalidTrustRoot
    }
    self.publicKey = key
    self.now = now
  }

  public func verify(
    _ signed: SignedCanaryPayloadReceipt,
    expected: CanaryPayloadIdentity
  ) throws {
    guard signed.publicKey == publicKey.rawRepresentation,
      publicKey.isValidSignature(
        signed.signature,
        for: try signed.receipt.canonicalData()
      )
    else {
      throw CandidateError.invalidSignature
    }
    let receipt = signed.receipt
    guard receipt.format == 1, receipt.completed else {
      throw CandidateError.incompletePayloadReceipt
    }
    guard receipt.digest == expected.digest,
      receipt.sizeBytes == expected.sizeBytes
    else {
      throw CandidateError.payloadReceiptMismatch
    }
    guard let expectedDigest = SHA256Digest(rawValue: expected.digest),
      receipt.path
        == "/var/cache/omarchy/cas/sha256/\(expectedDigest.hexadecimal)",
      receipt.ownerID == 0,
      receipt.mode == 0o400
    else {
      throw CandidateError.unsafePayloadCache
    }
    let current = now()
    guard receipt.verifiedAt <= current, current < receipt.expiresAt,
      receipt.expiresAt.timeIntervalSince(receipt.verifiedAt) <= 3_600
    else {
      throw CandidateError.stalePayloadReceipt
    }
  }
}

private struct CanaryEnvelope: Codable {
  let format: Int
  let candidateKind: CandidateKind
  let marker: String
  let operation: String
  let sequence: UInt64
  let issuedAt: Date
  let expiresAt: Date
  let trustRootFingerprint: String
  let sourceTreeDigest: String
  let enrollment: CanaryEnrollment
  let payload: CanaryPayloadIdentity
  let repairManifest: CanaryArtifact
  let changedArtifacts: [CanaryArtifact]
}

private func encodeCanonical<T: Encodable>(_ value: T) throws -> Data {
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  encoder.keyEncodingStrategy = .convertToSnakeCase
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  return try encoder.encode(value)
}

private func isDigest(_ value: String) -> Bool {
  SHA256Digest(rawValue: value) != nil
}
