#if os(macOS)
  import Foundation
  import OpenDirectory

  public enum MachineOwnerAuthorizationError:
    Error, Equatable, Sendable
  {
    case invalidUsername
    case invalidPassword
  }

  public struct MachineOwnerAuthorization: Equatable, Sendable {
    public let username: String
    let password: Data

    public init(username: String, password: Data) throws {
      guard Self.isValidUsername(username) else {
        throw MachineOwnerAuthorizationError.invalidUsername
      }
      guard Self.isValidPassword(password) else {
        throw MachineOwnerAuthorizationError.invalidPassword
      }
      self.username = username
      self.password = password
    }

    private static func isValidUsername(_ value: String) -> Bool {
      guard (1...255).contains(value.utf8.count) else {
        return false
      }
      return value.utf8.allSatisfy { byte in
        (byte >= 48 && byte <= 57)
          || (byte >= 65 && byte <= 90)
          || (byte >= 97 && byte <= 122)
          || byte == 45
          || byte == 46
          || byte == 95
      }
    }

    private static func isValidPassword(_ value: Data) -> Bool {
      guard (1...1_024).contains(value.count) else {
        return false
      }
      return !value.contains(0)
        && !value.contains(10)
        && !value.contains(13)
        && String(data: value, encoding: .utf8) != nil
    }

    func passwordString() throws -> String {
      guard let value = String(data: password, encoding: .utf8) else {
        throw MachineOwnerAuthorizationError.invalidPassword
      }
      return value
    }
  }

  public protocol MachineOwnerCredentialValidating: Sendable {
    func validate(_ authorization: MachineOwnerAuthorization) throws
  }

  public enum MachineOwnerCredentialValidationError:
    Error, Equatable, Sendable
  {
    case rejected
  }

  public struct OpenDirectoryMachineOwnerCredentialValidator:
    MachineOwnerCredentialValidating
  {
    public init() {}

    public func validate(
      _ authorization: MachineOwnerAuthorization
    ) throws {
      do {
        let node = try ODNode(
          session: ODSession.default(),
          type: ODNodeType(kODNodeTypeLocalNodes)
        )
        let record = try node.record(
          withRecordType: kODRecordTypeUsers,
          name: authorization.username,
          attributes: nil
        )
        try record.verifyPassword(authorization.passwordString())
      } catch {
        throw MachineOwnerCredentialValidationError.rejected
      }
    }
  }
#endif
