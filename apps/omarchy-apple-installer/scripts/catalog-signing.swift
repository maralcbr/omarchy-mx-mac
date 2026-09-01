import CryptoKit
import Foundation

enum SigningToolError: Error {
    case usage
    case invalidKey
    case invalidSignature
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    throw SigningToolError.usage
}

switch arguments[1] {
case "generate":
    guard arguments.count == 4 else {
        throw SigningToolError.usage
    }
    let key = Curve25519.Signing.PrivateKey()
    try key.rawRepresentation.write(to: URL(fileURLWithPath: arguments[2]), options: .atomic)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: arguments[2]
    )
    try key.publicKey.rawRepresentation.write(
        to: URL(fileURLWithPath: arguments[3]),
        options: .atomic
    )

case "sign":
    guard arguments.count == 5 else {
        throw SigningToolError.usage
    }
    let rawKey = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
    guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: rawKey) else {
        throw SigningToolError.invalidKey
    }
    let message = try Data(contentsOf: URL(fileURLWithPath: arguments[3]))
    let signature = try key.signature(for: message)
    try signature.write(to: URL(fileURLWithPath: arguments[4]), options: .atomic)

case "verify":
    guard arguments.count == 5 else {
        throw SigningToolError.usage
    }
    let rawPublicKey = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
    guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawPublicKey) else {
        throw SigningToolError.invalidKey
    }
    let message = try Data(contentsOf: URL(fileURLWithPath: arguments[3]))
    let signature = try Data(contentsOf: URL(fileURLWithPath: arguments[4]))
    guard publicKey.isValidSignature(signature, for: message) else {
        throw SigningToolError.invalidSignature
    }
    print("catalog_signature=passed")

default:
    throw SigningToolError.usage
}
