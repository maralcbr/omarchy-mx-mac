import CryptoKit
import Foundation

public struct PinnedInstallerRecord: Equatable, Sendable {
  public let deviceIdentifier: String
  public let asahiInstallerTag: String
  public let asahiInstallerRevision: String
  public let asahiInstallerDataRevision: String
  public let downstreamRevision: String
  public let engineDigest: String
  public let metadataDigest: String
  public let payloadDigest: String
  public let evidenceRevision: String
}

struct SupportCatalog: Equatable, Sendable {
  static let empty = SupportCatalog(sequence: 0, records: [:])

  let sequence: UInt64
  private let records: [String: PinnedInstallerRecord]

  init(sequence: UInt64, records: [String: PinnedInstallerRecord]) {
    self.sequence = sequence
    self.records = records
  }

  func record(for deviceIdentifier: String) -> PinnedInstallerRecord? {
    records[deviceIdentifier]
  }
}

struct CatalogSupportPolicy: Sendable {
  let catalog: SupportCatalog
  let disabledDeviceIdentifiers: Set<String>

  func record(for deviceIdentifier: String) -> PinnedInstallerRecord? {
    guard !disabledDeviceIdentifiers.contains(deviceIdentifier) else {
      return nil
    }

    return catalog.record(for: deviceIdentifier)
  }
}

public enum SupportCatalogError: Error, Equatable, Sendable {
  case invalidPublicKey
  case invalidSignature
  case invalidPayload
  case unsupportedSchema(Int)
  case invalidSequence
  case duplicateDeviceIdentifier(String)
  case invalidField(String)
  case notYetValid
  case expired
}

struct SignedSupportCatalogVerifier: Sendable {
  func verify(
    payload: Data,
    signature: Data,
    publicKey: Data,
    now: Date
  ) throws -> SupportCatalog {
    let trustRoot: Curve25519.Signing.PublicKey

    do {
      trustRoot = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    } catch {
      throw SupportCatalogError.invalidPublicKey
    }

    guard trustRoot.isValidSignature(signature, for: payload) else {
      throw SupportCatalogError.invalidSignature
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let manifest: Manifest
    do {
      manifest = try decoder.decode(Manifest.self, from: payload)
    } catch {
      throw SupportCatalogError.invalidPayload
    }

    guard manifest.schemaVersion == 1 else {
      throw SupportCatalogError.unsupportedSchema(manifest.schemaVersion)
    }
    guard manifest.sequence > 0 else {
      throw SupportCatalogError.invalidSequence
    }
    guard manifest.issuedAt < manifest.expiresAt else {
      throw SupportCatalogError.invalidField("expiresAt")
    }
    guard manifest.issuedAt <= now else {
      throw SupportCatalogError.notYetValid
    }
    guard now < manifest.expiresAt else {
      throw SupportCatalogError.expired
    }

    var seenDeviceIdentifiers = Set<String>()
    var records = [String: PinnedInstallerRecord]()

    for (index, model) in manifest.models.enumerated() {
      guard seenDeviceIdentifiers.insert(model.deviceIdentifier).inserted else {
        throw SupportCatalogError.duplicateDeviceIdentifier(model.deviceIdentifier)
      }
      guard isDeviceIdentifier(model.deviceIdentifier) else {
        throw SupportCatalogError.invalidField("models[\(index)].deviceIdentifier")
      }
      guard isSemanticVersionTag(model.asahiInstallerTag) else {
        throw SupportCatalogError.invalidField("models[\(index)].asahiInstallerTag")
      }
      guard isSHA256Digest(model.engineDigest) else {
        throw SupportCatalogError.invalidField("models[\(index)].engineDigest")
      }
      guard isSHA256Digest(model.metadataDigest) else {
        throw SupportCatalogError.invalidField("models[\(index)].metadataDigest")
      }
      guard isSHA256Digest(model.payloadDigest) else {
        throw SupportCatalogError.invalidField("models[\(index)].payloadDigest")
      }
      guard isGitRevision(model.asahiInstallerRevision) else {
        throw SupportCatalogError.invalidField(
          "models[\(index)].asahiInstallerRevision"
        )
      }
      guard isGitRevision(model.asahiInstallerDataRevision) else {
        throw SupportCatalogError.invalidField(
          "models[\(index)].asahiInstallerDataRevision"
        )
      }
      guard isGitRevision(model.downstreamRevision) else {
        throw SupportCatalogError.invalidField(
          "models[\(index)].downstreamRevision"
        )
      }
      guard isEvidenceRevision(model.evidenceRevision) else {
        throw SupportCatalogError.invalidField(
          "models[\(index)].evidenceRevision"
        )
      }

      guard model.status == .enabled else {
        continue
      }

      records[model.deviceIdentifier] = PinnedInstallerRecord(
        deviceIdentifier: model.deviceIdentifier,
        asahiInstallerTag: model.asahiInstallerTag,
        asahiInstallerRevision: model.asahiInstallerRevision,
        asahiInstallerDataRevision: model.asahiInstallerDataRevision,
        downstreamRevision: model.downstreamRevision,
        engineDigest: model.engineDigest,
        metadataDigest: model.metadataDigest,
        payloadDigest: model.payloadDigest,
        evidenceRevision: model.evidenceRevision
      )
    }

    return SupportCatalog(sequence: manifest.sequence, records: records)
  }

  private func isSHA256Digest(_ value: String) -> Bool {
    guard value.hasPrefix("sha256:") else {
      return false
    }

    let hexadecimal = value.dropFirst(7)
    return isLowercaseHex(String(hexadecimal), count: 64)
  }

  private func isGitRevision(_ value: String) -> Bool {
    isLowercaseHex(value, count: 40)
  }

  private func isDeviceIdentifier(_ value: String) -> Bool {
    guard value.hasPrefix("apple,") else {
      return false
    }

    let product = value.dropFirst(6)
    return !product.isEmpty
      && product.utf8.allSatisfy { byte in
        (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 122)
      }
  }

  private func isSemanticVersionTag(_ value: String) -> Bool {
    guard value.hasPrefix("v") else {
      return false
    }

    let components = value.dropFirst().split(
      separator: ".",
      omittingEmptySubsequences: false
    )
    return components.count == 3
      && components.allSatisfy { component in
        !component.isEmpty && component.allSatisfy(\.isNumber)
      }
  }

  private func isEvidenceRevision(_ value: String) -> Bool {
    (1...128).contains(value.utf8.count)
      && value.utf8.allSatisfy { byte in
        (byte >= 48 && byte <= 57)
          || (byte >= 97 && byte <= 122)
          || byte == 45
          || byte == 46
      }
  }

  private func isLowercaseHex(_ value: String, count: Int) -> Bool {
    value.count == count
      && value.allSatisfy { character in
        character.isNumber || ("a"..."f").contains(character)
      }
  }
}

private struct Manifest: Decodable {
  let schemaVersion: Int
  let sequence: UInt64
  let issuedAt: Date
  let expiresAt: Date
  let models: [ModelRecord]
}

private struct ModelRecord: Decodable {
  let deviceIdentifier: String
  let status: ModelStatus
  let asahiInstallerTag: String
  let asahiInstallerRevision: String
  let asahiInstallerDataRevision: String
  let downstreamRevision: String
  let engineDigest: String
  let metadataDigest: String
  let payloadDigest: String
  let evidenceRevision: String
}

private enum ModelStatus: String, Decodable {
  case enabled
  case disabled
}
