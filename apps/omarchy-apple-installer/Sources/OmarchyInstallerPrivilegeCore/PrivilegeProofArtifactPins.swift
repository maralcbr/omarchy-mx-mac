import CryptoKit
import Foundation

/// Fixed artifact identity for a developer qualification run, separate from signer trust.
public struct PrivilegeProofArtifactPins: Sendable {
  public let workerCDHash: Data
  private let files: [String: String]

  public init(appSHA256: String, workerSHA256: String, infoSHA256: String, workerCDHash: String)
    throws
  {
    let values = [appSHA256, workerSHA256, infoSHA256]
    guard values.allSatisfy({ Self.isHex($0, count: 64) }),
      Self.isHex(workerCDHash, count: 40)
    else { throw PrivilegeProofError.untrustedBundle }
    var bytes = Data()
    var index = workerCDHash.startIndex
    while index < workerCDHash.endIndex {
      let next = workerCDHash.index(index, offsetBy: 2)
      guard let byte = UInt8(workerCDHash[index..<next], radix: 16) else {
        throw PrivilegeProofError.untrustedBundle
      }
      bytes.append(byte)
      index = next
    }
    self.workerCDHash = bytes
    files = [
      "Contents/MacOS/OmarchyPrivilegeProofApp": appSHA256,
      "Contents/Helpers/OmarchyPrivilegeProofWorker": workerSHA256,
      "Contents/Info.plist": infoSHA256,
    ]
  }

  public func validate(_ bundle: URL) throws {
    for (relative, expected) in files {
      let data = try Data(contentsOf: bundle.appendingPathComponent(relative))
      let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      guard actual == expected else { throw PrivilegeProofError.untrustedBundle }
    }
  }

  private static func isHex(_ value: String, count: Int) -> Bool {
    value.utf8.count == count
      && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}
