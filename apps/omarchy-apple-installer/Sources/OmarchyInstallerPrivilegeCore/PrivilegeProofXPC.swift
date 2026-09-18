import Foundation
import Security

/// Deliberately excludes the installation/removal protocol and every disk operation.
@objc public protocol PrivilegeProofXPCService {
  func probe(nonce: String, finishing: Bool, reply: @escaping @Sendable (Data?) -> Void)
}

public typealias PrivilegeProofSigning = InstallerCodeSigning

struct PrivilegeProofXPCClient: Sendable {
  let requirement: String

  func request(_ launch: PrivilegeProofLaunch, finishing: Bool) async throws -> Data {
    guard InstallerCodeSigningRequirement.isValid(requirement) else {
      throw PrivilegeProofError.untrustedBundle
    }
    let connection = NSXPCConnection(machServiceName: launch.label, options: .privileged)
    connection.remoteObjectInterface = NSXPCInterface(with: PrivilegeProofXPCService.self)
    connection.setCodeSigningRequirement(requirement)
    let handle = ProofConnection(connection)
    return try await withCheckedThrowingContinuation { continuation in
      let gate = ProofReplyGate(continuation)
      let timeout = Task {
        try await Task.sleep(for: .seconds(4))
        gate.resolve(.failure(PrivilegeProofError.connectionFailed))
        handle.invalidate()
      }
      connection.interruptionHandler = {
        gate.resolve(.failure(PrivilegeProofError.connectionFailed))
        timeout.cancel()
        handle.invalidate()
      }
      connection.invalidationHandler = {
        gate.resolve(.failure(PrivilegeProofError.connectionFailed))
        timeout.cancel()
      }
      connection.activate()
      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
          gate.resolve(.failure(PrivilegeProofError.connectionFailed))
          timeout.cancel()
          handle.invalidate()
        }) as? PrivilegeProofXPCService
      else {
        gate.resolve(.failure(PrivilegeProofError.connectionFailed))
        timeout.cancel()
        handle.invalidate()
        return
      }
      proxy.probe(nonce: launch.id.uuidString, finishing: finishing) { data in
        if let data {
          gate.resolve(.success(data))
        } else {
          gate.resolve(.failure(PrivilegeProofError.invalidReply))
        }
        timeout.cancel()
        handle.invalidate()
      }
    }
  }
}

/// A qualification client can only send this harmless nonce-bound proof request.
public enum PrivilegeProofPeerCheck {
  public static func request(_ launch: PrivilegeProofLaunch, rejectWorker: Bool = false)
    async throws
    -> PrivilegeProofReply
  {
    var requirement = try PrivilegeProofIdentity.requirement(
      identifier: PrivilegeProofIdentity.worker, team: "T2C384FJBD")
    if rejectWorker { requirement += " and identifier \"com.omarchy.mx.installer.rejected\"" }
    let data = try await PrivilegeProofXPCClient(requirement: requirement).request(
      launch, finishing: false)
    let reply = try JSONDecoder().decode(PrivilegeProofReply.self, from: data)
    try reply.validate(for: launch)
    return reply
  }
}

private final class ProofConnection: @unchecked Sendable {
  private let connection: NSXPCConnection
  init(_ connection: NSXPCConnection) { self.connection = connection }
  func invalidate() { connection.invalidate() }
}

private final class ProofReplyGate: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Data, any Error>?
  init(_ continuation: CheckedContinuation<Data, any Error>) { self.continuation = continuation }
  func resolve(_ result: Result<Data, any Error>) {
    lock.lock()
    let pending = continuation
    continuation = nil
    lock.unlock()
    pending?.resume(with: result)
  }
}
