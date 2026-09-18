import Darwin
import Foundation
import OmarchyInstallerPrivilegeCore

private final class ProbeEndpoint: NSObject, PrivilegeProofXPCService {
  let launch: PrivilegeProofLaunch
  init(launch: PrivilegeProofLaunch) { self.launch = launch }

  func probe(nonce: String, finishing: Bool, reply: @escaping @Sendable (Data?) -> Void) {
    guard UUID(uuidString: nonce) == launch.id else {
      reply(nil)
      return
    }
    let response = PrivilegeProofReply(
      launch: launch, effectiveUserID: geteuid(), processID: getpid())
    reply(try? JSONEncoder().encode(response))
    if finishing {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { exit(EX_OK) }
    }
  }
}

private final class ProbeListener: NSObject, NSXPCListenerDelegate {
  let requirement: String
  let endpoint: ProbeEndpoint
  init(requirement: String, launch: PrivilegeProofLaunch) {
    self.requirement = requirement
    endpoint = ProbeEndpoint(launch: launch)
  }

  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
    -> Bool
  {
    connection.setCodeSigningRequirement(requirement)
    connection.exportedInterface = NSXPCInterface(with: PrivilegeProofXPCService.self)
    connection.exportedObject = endpoint
    connection.activate()
    return true
  }
}

// Hard lifetime is independent of any client, authentication failure or connection state.
DispatchQueue.main.asyncAfter(deadline: .now() + PrivilegeProofIdentity.lifetime) { exit(EX_OK) }
do {
  guard geteuid() == 0, CommandLine.arguments.count == 2,
    let id = UUID(uuidString: CommandLine.arguments[1])
  else { exit(EX_USAGE) }
  let team = try PrivilegeProofSigning.currentTeam(
    expectedIdentifier: PrivilegeProofIdentity.worker)
  let requirement = try PrivilegeProofIdentity.requirement(
    identifier: PrivilegeProofIdentity.app, team: team)
  guard InstallerCodeSigningRequirement.isValid(requirement) else { exit(EX_CONFIG) }
  let launch = PrivilegeProofLaunch(id: id)
  let delegate = ProbeListener(requirement: requirement, launch: launch)
  let listener = NSXPCListener(machServiceName: launch.label)
  listener.delegate = delegate
  listener.resume()
  withExtendedLifetime((listener, delegate)) { RunLoop.current.run() }
} catch {
  exit(EX_CONFIG)
}
