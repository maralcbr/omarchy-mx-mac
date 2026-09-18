import Foundation
import Security

public enum InstallerCodeSigning {
  public static func currentTeam(expectedIdentifier: String) throws -> String {
    var code: SecCode?
    var staticCode: SecStaticCode?
    var information: CFDictionary?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
      SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
      SecCodeCopySigningInformation(
        staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        == errSecSuccess,
      let values = information as? [String: Any],
      values[kSecCodeInfoIdentifier as String] as? String == expectedIdentifier,
      let team = values[kSecCodeInfoTeamIdentifier as String] as? String
    else { throw PrivilegeProofError.untrustedBundle }
    let requirement = try parsed(
      InstallerCodeSigningRequirement.requirement(identifier: expectedIdentifier, team: team))
    guard SecCodeCheckValidity(code, [], requirement) == errSecSuccess else {
      throw PrivilegeProofError.untrustedBundle
    }
    return team
  }

  public static func validateFile(_ url: URL, requirement: String) throws {
    var code: SecStaticCode?
    let required = try parsed(requirement)
    guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
      SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), required)
        == errSecSuccess
    else { throw PrivilegeProofError.untrustedBundle }
  }

  private static func parsed(_ text: String) throws -> SecRequirement {
    var result: SecRequirement?
    guard InstallerCodeSigningRequirement.isValid(text),
      SecRequirementCreateWithString(text as CFString, [], &result) == errSecSuccess,
      let result
    else { throw PrivilegeProofError.untrustedBundle }
    return result
  }
}
