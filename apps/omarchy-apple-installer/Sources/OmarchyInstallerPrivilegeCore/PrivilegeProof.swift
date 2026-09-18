import Foundation
import Observation
import Security

public enum InstallerCodeSigningRequirement {
  public static func requirement(identifier: String, team: String) throws -> String {
    guard (3...255).contains(identifier.utf8.count), identifier.contains("."),
      identifier.utf8.allSatisfy({
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 46
          || $0 == 45
      }),
      team.utf8.count == 10,
      team.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) })
    else { throw PrivilegeProofError.untrustedBundle }
    return
      "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
  }

  public static func isValid(_ value: String) -> Bool {
    guard !value.isEmpty, value.utf8.count <= 4_096 else { return false }
    var requirement: SecRequirement?
    let status = SecRequirementCreateWithString(value as CFString, SecCSFlags(), &requirement)
    return status == errSecSuccess && requirement != nil
  }
}

public enum PrivilegeProofIdentity {
  public static let app = "com.omarchy.mx.installer.privilege-proof"
  public static let worker = "com.omarchy.mx.installer.privilege-proof.worker"
  public static let protocolVersion = 1
  public static let lifetime: TimeInterval = 12

  public static func requirement(identifier: String, team: String) throws -> String {
    guard [app, worker].contains(identifier),
      team.utf8.count == 10,
      team.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) })
    else { throw PrivilegeProofError.untrustedBundle }
    return
      "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
  }
}

public enum PrivilegeProofMode: String, Sendable { case roundTrip, idleExpiry }

public struct PrivilegeProofLaunch: Sendable {
  public let id: UUID
  public var label: String { "\(PrivilegeProofIdentity.worker).\(id.uuidString.lowercased())" }
  public init(id: UUID = UUID()) { self.id = id }
}

public struct PrivilegeProofReply: Codable, Equatable, Sendable {
  public let version: Int
  public let nonce: UUID
  public let label: String
  public let effectiveUserID: UInt32
  public let processID: Int32

  public init(launch: PrivilegeProofLaunch, effectiveUserID: UInt32, processID: Int32) {
    version = PrivilegeProofIdentity.protocolVersion
    nonce = launch.id
    label = launch.label
    self.effectiveUserID = effectiveUserID
    self.processID = processID
  }

  public func validate(for launch: PrivilegeProofLaunch) throws {
    guard version == PrivilegeProofIdentity.protocolVersion, nonce == launch.id,
      label == launch.label, effectiveUserID == 0, processID > 1
    else { throw PrivilegeProofError.invalidReply }
  }
}

public enum PrivilegeProofError: Error, Equatable, LocalizedError {
  case previewOnly, untrustedBundle, authorizationCancelled
  case authorizationFailed(Int32)
  case submissionFailed(String)
  case removalFailed(String)
  case connectionFailed, invalidReply, retirementUnverified, workerExitedEarly
  case alreadyRunning

  public var errorDescription: String? {
    switch self {
    case .previewOnly:
      "This review build cannot request administrator access. Build and verify a signed qualification candidate first."
    case .untrustedBundle:
      "The proof app or worker does not match its required signing identity or qualification artifact."
    case .authorizationCancelled:
      "Administrator authorization was cancelled. No worker was submitted."
    case .authorizationFailed(let status):
      "Administrator authorization failed (\(status)). No worker was submitted."
    case .submissionFailed(let detail): "The temporary worker could not start: \(detail)"
    case .removalFailed(let detail): "The temporary job removal failed: \(detail)"
    case .connectionFailed: "The temporary worker did not return an authenticated reply."
    case .invalidReply: "The worker reply did not match this proof session and root identity."
    case .retirementUnverified: "Worker retirement could not be verified. This run is not a pass."
    case .workerExitedEarly: "The unused worker exited too early to prove its lifetime limit."
    case .alreadyRunning: "A proof is already running."
    }
  }
}

public protocol PrivilegeProofBackend: Sendable {
  func start(_ launch: PrivilegeProofLaunch) async throws
  func probe(_ launch: PrivilegeProofLaunch) async throws -> PrivilegeProofReply
  func finish(_ launch: PrivilegeProofLaunch) async throws
  func waitForExit(_ launch: PrivilegeProofLaunch, mode: PrivilegeProofMode) async throws
  func remove(_ launch: PrivilegeProofLaunch) async throws
}

@MainActor @Observable
public final class PrivilegeProofSession {
  public private(set) var isRunning = false
  public private(set) var passed = false
  public private(set) var status = "Ready for a harmless privilege check."
  public private(set) var evidence: [String] = []
  private let backend: any PrivilegeProofBackend

  public init(backend: any PrivilegeProofBackend) { self.backend = backend }

  public func run(_ mode: PrivilegeProofMode) async {
    guard !isRunning else { return }
    isRunning = true
    passed = false
    evidence = []
    defer { isRunning = false }
    let launch = PrivilegeProofLaunch()
    var submitted = false
    do {
      status = "Verifying the bundle and requesting administrator authorization…"
      try await backend.start(launch)
      submitted = true
      evidence.append("Temporary job: \(launch.label)")
      if mode == .roundTrip {
        status = "Waiting for an authenticated root reply…"
        let reply = try await backend.probe(launch)
        try reply.validate(for: launch)
        evidence.append(
          "Protocol \(reply.version); effective UID \(reply.effectiveUserID); PID \(reply.processID)"
        )
        try await backend.finish(launch)
      } else {
        evidence.append("No XPC request sent; checking the worker's independent lifetime limit.")
      }
      status = "Verifying worker and temporary job retirement…"
      try await backend.waitForExit(launch, mode: mode)
      evidence.append("Observed worker exit and absence of this temporary job.")
      status =
        mode == .roundTrip
        ? "Authenticated request and retirement passed." : "Unused worker expiry passed."
      passed = true
    } catch {
      let original = error.localizedDescription
      if submitted {
        do {
          try await backend.remove(launch)
          evidence.append(
            "Verified this run's temporary job and worker are no longer active after failure.")
          status = original
        } catch {
          status = "\(original) Cleanup also failed: \(error.localizedDescription)"
        }
      } else {
        status = original
      }
    }
  }
}
