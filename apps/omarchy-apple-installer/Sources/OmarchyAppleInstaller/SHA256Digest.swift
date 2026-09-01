import CryptoKit
import Foundation

public struct SHA256Digest:
  Codable, CustomStringConvertible, Equatable, Hashable, RawRepresentable,
  Sendable
{
  public let rawValue: String

  public init?(rawValue: String) {
    let bytes = Array(rawValue.utf8)
    guard bytes.count == 71,
      bytes.starts(with: Array("sha256:".utf8)),
      bytes.dropFirst(7).allSatisfy({ byte in
        (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
      })
    else {
      return nil
    }
    self.rawValue = rawValue
  }

  public init?(hexadecimal: String) {
    self.init(rawValue: "sha256:" + hexadecimal)
  }

  public init(hashing data: Data) {
    rawValue = Self.prefixedHex(SHA256.hash(data: data))
  }

  public var description: String {
    rawValue
  }

  public var hexadecimal: String {
    String(rawValue.dropFirst(7))
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    guard let digest = Self(rawValue: value) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Expected a lowercase sha256 digest"
      )
    }
    self = digest
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  static func prefixedHex<S: Sequence>(_ bytes: S) -> String
  where S.Element == UInt8 {
    "sha256:" + bytes.map { String(format: "%02x", $0) }.joined()
  }
}

enum InstallerDigest {
  static func lengthPrefixedSHA256(_ fields: [String]) -> SHA256Digest {
    let canonical =
      fields
      .map { "\($0.utf8.count):\($0)" }
      .joined(separator: "|")
    return SHA256Digest(hashing: Data(canonical.utf8))
  }
}
