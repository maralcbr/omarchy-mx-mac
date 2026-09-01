import Foundation
import Testing

@testable import OmarchyAppleInstallerTrustCore

struct SHA256DigestTests {
  @Test func acceptsExactLowercasePrefixedDigest() throws {
    let value = "sha256:" + String(repeating: "0a", count: 32)
    let digest = try #require(SHA256Digest(rawValue: value))
    #expect(digest.rawValue == value)
    #expect(SHA256Digest(hexadecimal: digest.hexadecimal) == digest)
  }

  @Test func rejectsWrongPrefixLengthAndAlphabet() {
    #expect(SHA256Digest(rawValue: String(repeating: "0", count: 64)) == nil)
    #expect(SHA256Digest(rawValue: "sha256:" + String(repeating: "0", count: 63)) == nil)
    #expect(SHA256Digest(rawValue: "sha256:" + String(repeating: "A", count: 64)) == nil)
    #expect(SHA256Digest(rawValue: "sha256:" + String(repeating: "g", count: 64)) == nil)
  }

  @Test func hashesAndCodableRoundTripsAsOneString() throws {
    let digest = SHA256Digest(hashing: Data("omarchy".utf8))
    let encoded = try JSONEncoder().encode(digest)
    #expect(try JSONDecoder().decode(SHA256Digest.self, from: encoded) == digest)
    #expect(String(decoding: encoded, as: UTF8.self) == "\"\(digest.rawValue)\"")
  }

  @Test func lengthPrefixedHashSeparatesFieldBoundaries() {
    #expect(
      InstallerDigest.lengthPrefixedSHA256(["ab", "c"])
        != InstallerDigest.lengthPrefixedSHA256(["a", "bc"])
    )
  }
}
