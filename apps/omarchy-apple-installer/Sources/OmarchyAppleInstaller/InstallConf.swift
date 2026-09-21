import Foundation

public enum InstallConfError: Error, Equatable, Sendable {
  case invalidLane
  case invalidDocument
}

/// First-boot handover written to `omarchy/install.conf` on the target ESP
/// after the engine finishes. The signed payload zip is never modified.
public struct InstallConf: Equatable, Sendable {
  public static let relativePath = "omarchy/install.conf"
  public static let directoryName = "omarchy"
  public static let fileName = "install.conf"
  public static let allowedLanes: Set<String> = ["stable", "rc"]

  public let encrypt: Bool
  public let lane: String

  public init(encrypt: Bool, lane: String) throws {
    guard Self.allowedLanes.contains(lane) else {
      throw InstallConfError.invalidLane
    }
    self.encrypt = encrypt
    self.lane = lane
  }

  public var serialized: String {
    """
    format=1
    encrypt=\(encrypt ? "1" : "0")
    lane=\(lane)

    """
  }

  public var serializedData: Data {
    Data(serialized.utf8)
  }

  public static func parse(_ text: String) throws -> InstallConf {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
    let body = lines.last == "" ? Array(lines.dropLast()) : lines
    guard body.count == 3 else {
      throw InstallConfError.invalidDocument
    }
    guard body[0] == "format=1" else {
      throw InstallConfError.invalidDocument
    }
    let encrypt: Bool
    switch body[1] {
    case "encrypt=1":
      encrypt = true
    case "encrypt=0":
      encrypt = false
    default:
      throw InstallConfError.invalidDocument
    }
    guard body[2].hasPrefix("lane=") else {
      throw InstallConfError.invalidDocument
    }
    let lane = String(body[2].dropFirst("lane=".count))
    return try InstallConf(encrypt: encrypt, lane: lane)
  }

  public static func parse(_ data: Data) throws -> InstallConf {
    guard let text = String(data: data, encoding: .utf8) else {
      throw InstallConfError.invalidDocument
    }
    return try parse(text)
  }
}
