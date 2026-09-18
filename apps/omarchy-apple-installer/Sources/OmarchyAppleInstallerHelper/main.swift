import Darwin
import Foundation
import OmarchyAppleInstallerTrustCore
import OmarchyInstallerPrivilegeCore

private enum HelperBootstrapError: Error {
  case rootRequired
  case missingClientRequirement
  case unsafeWorkingDirectory
}

private func prepareWorkingDirectory() throws -> URL {
  let path = InstallerProductIdentity.helperWorkingDirectory
  var status = stat()
  if lstat(path, &status) == 0 {
    guard (status.st_mode & S_IFMT) == S_IFDIR,
      status.st_uid == 0,
      status.st_mode & 0o077 == 0
    else {
      throw HelperBootstrapError.unsafeWorkingDirectory
    }
    return URL(fileURLWithPath: path, isDirectory: true)
  }
  guard errno == ENOENT,
    mkdir(path, S_IRWXU) == 0,
    lstat(path, &status) == 0,
    (status.st_mode & S_IFMT) == S_IFDIR,
    status.st_uid == 0,
    status.st_mode & 0o077 == 0
  else {
    throw HelperBootstrapError.unsafeWorkingDirectory
  }
  return URL(fileURLWithPath: path, isDirectory: true)
}

private func terminate(_ error: any Error) -> Never {
  let message = "Omarchy installer helper failed: \(error)\n"
  try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
  exit(EX_CONFIG)
}

umask(0o077)

do {
  guard geteuid() == 0 else {
    throw HelperBootstrapError.rootRequired
  }
  let session: UUID?
  let clientPID: Int32?
  let clientStart: UInt64?
  let clientRequirement: String
  if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--temporary",
    let requested = UUID(uuidString: CommandLine.arguments[2]),
    let pid = Int32(CommandLine.arguments[3]), pid > 1,
    let start = UInt64(CommandLine.arguments[4]), start > 0,
    TemporaryInstallerWorker.processStart(pid) == start
  {
    session = requested
    clientPID = pid
    clientStart = start
    let team = try InstallerCodeSigning.currentTeam(
      expectedIdentifier: InstallerProductIdentity.helperIdentifier)
    clientRequirement = try InstallerCodeSigningRequirement.requirement(
      identifier: TemporaryInstallerWorker.appIdentifier, team: team)
  } else if CommandLine.arguments.count == 1,
    let requirement = ProcessInfo.processInfo.environment[
      InstallerProductIdentity.clientRequirementEnvironmentVariable],
    !requirement.isEmpty
  {
    session = nil
    clientPID = nil
    clientStart = nil
    clientRequirement = requirement
  } else {
    throw HelperBootstrapError.missingClientRequirement
  }
  let workingDirectory = try prepareWorkingDirectory()
  let executionLease = try InstallerExecutionLease.acquire()
  let server = ClosedEngineHelperServer(
    workingDirectory: workingDirectory,
    executor: PinnedAsahiEngineExecutor(),
    executionAdmission: {
      if session != nil { try TemporaryInstallerWorker.requireNoLegacyHelper() }
      try executionLease.requireIdleGroup()
    },
    temporarySession: session
  )
  let delegate = try AuthenticatedEngineXPCListenerDelegate(
    clientCodeSigningRequirement: clientRequirement,
    server: server, clientProcessID: clientPID, clientProcessStart: clientStart
  )
  let listener = NSXPCListener(
    machServiceName: session.map(TemporaryInstallerWorker.serviceName)
      ?? InstallerProductIdentity.helperMachServiceName
  )
  listener.delegate = delegate
  listener.resume()
  if let clientPID, let clientStart, session != nil {
    Task {
      while true {
        try? await Task.sleep(for: .seconds(1))
        if TemporaryInstallerWorker.processStart(clientPID) != clientStart {
          await server.requestRetirement()
        }
        if await server.shouldRetire() { exit(EX_OK) }
      }
    }
  }
  withExtendedLifetime((delegate, executionLease)) {
    RunLoop.current.run()
  }
} catch {
  terminate(error)
}
