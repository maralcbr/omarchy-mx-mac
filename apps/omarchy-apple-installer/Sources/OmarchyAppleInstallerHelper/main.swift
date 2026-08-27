import Darwin
import Foundation
import OmarchyAppleInstallerTrustCore

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
  guard
    let clientRequirement = ProcessInfo.processInfo.environment[
      InstallerProductIdentity.clientRequirementEnvironmentVariable
    ], !clientRequirement.isEmpty
  else {
    throw HelperBootstrapError.missingClientRequirement
  }
  let workingDirectory = try prepareWorkingDirectory()
  let server = ClosedEngineHelperServer(
    workingDirectory: workingDirectory,
    executor: PinnedAsahiEngineExecutor()
  )
  let delegate = try AuthenticatedEngineXPCListenerDelegate(
    clientCodeSigningRequirement: clientRequirement,
    server: server
  )
  let listener = NSXPCListener(
    machServiceName: InstallerProductIdentity.helperMachServiceName
  )
  listener.delegate = delegate
  listener.resume()
  withExtendedLifetime(delegate) {
    RunLoop.current.run()
  }
} catch {
  terminate(error)
}
