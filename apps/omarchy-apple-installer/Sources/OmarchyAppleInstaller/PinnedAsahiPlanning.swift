import Foundation

public enum PinnedAsahiPlanningError: Error, Equatable, Sendable {
  case candidateNotInInventory
  case invalidRequestedLength
  case invalidEngineIdentity
}

public struct PinnedAsahiPlanRequest: Equatable, Sendable, Encodable {
  public static let allocationUnitBytes: UInt64 = 1_048_576

  public let schemaVersion = 1
  public let layoutDigest: String
  public let candidateKind: String
  public let sourceIdentifier: String
  public let requestedLengthBytes: UInt64

  public init(
    inventory: ValidatedEngineInventory,
    candidate: ValidatedEngineCandidate,
    requestedLengthBytes: UInt64
  ) throws {
    guard inventory.candidates.contains(candidate) else {
      throw PinnedAsahiPlanningError.candidateNotInInventory
    }
    let maximum: UInt64
    if candidate.kind == "free" {
      maximum = candidate.lengthBytes
    } else if candidate.kind == "repair" || candidate.kind == "replace" {
      maximum = candidate.lengthBytes
    } else if candidate.kind == "resize",
      candidate.lengthBytes > candidate.minimumContainerBytes
    {
      maximum = candidate.lengthBytes - candidate.minimumContainerBytes
    } else {
      throw PinnedAsahiPlanningError.invalidRequestedLength
    }
    guard requestedLengthBytes >= candidate.minimumInstallBytes,
      requestedLengthBytes <= maximum,
      requestedLengthBytes % Self.allocationUnitBytes == 0,
      !["repair", "replace"].contains(candidate.kind)
        || requestedLengthBytes == candidate.lengthBytes
    else {
      throw PinnedAsahiPlanningError.invalidRequestedLength
    }

    layoutDigest = inventory.layoutDigest
    candidateKind = candidate.kind
    sourceIdentifier = candidate.sourceIdentifier
    self.requestedLengthBytes = requestedLengthBytes
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case layoutDigest = "layout_digest"
    case candidateKind = "candidate_kind"
    case sourceIdentifier = "source_identifier"
    case requestedLengthBytes = "requested_length_bytes"
  }
}

public struct PinnedAsahiPlanIdentity: Equatable, Sendable, Encodable {
  public let schemaVersion = 1
  public let engineVersion: String
  public let engineDigest: String
  public let metadataDigest: String
  public let payloadDigest: String
  public let repairManifestDigest: String?

  public init(
    engineVersion: String,
    engineDigest: String,
    metadataDigest: String,
    payloadDigest: String,
    repairManifestDigest: String? = nil
  ) throws {
    guard !engineVersion.isEmpty,
      engineVersion.utf8.count <= 128,
      SHA256Digest(rawValue: engineDigest) != nil,
      SHA256Digest(rawValue: metadataDigest) != nil,
      SHA256Digest(rawValue: payloadDigest) != nil,
      repairManifestDigest == nil
        || SHA256Digest(rawValue: repairManifestDigest!) != nil
    else {
      throw PinnedAsahiPlanningError.invalidEngineIdentity
    }
    self.engineVersion = engineVersion
    self.engineDigest = engineDigest
    self.metadataDigest = metadataDigest
    self.payloadDigest = payloadDigest
    self.repairManifestDigest = repairManifestDigest
  }

  public init(
    engineVersion: String,
    installer: PinnedInstallerRecord
  ) throws {
    try self.init(
      engineVersion: engineVersion,
      engineDigest: installer.engineDigest,
      metadataDigest: installer.metadataDigest,
      payloadDigest: installer.payloadDigest,
      repairManifestDigest: installer.repairManifestDigest
    )
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case engineVersion = "engine_version"
    case engineDigest = "engine_digest"
    case metadataDigest = "metadata_digest"
    case payloadDigest = "payload_digest"
    case repairManifestDigest = "repair_manifest_digest"
  }

}
