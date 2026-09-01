#if os(macOS)
  import Foundation

  public enum EngineHandoffOperation: String, Equatable, Sendable {
    case install
    case retryRecoveryAuthorization = "retry-recovery-authorization"
  }

  public protocol ImportedEngineHandoffExecuting: Sendable {
    func execute(
      _ package: ImportedEngineHandoffPackage,
      authorization: MachineOwnerAuthorization,
      operation: EngineHandoffOperation
    ) async throws -> Data
  }

  public enum ClosedEngineHelperError: Error, Equatable, Sendable {
    case busy
    case invalidOperation
    case invalidMachineOwnerCredentials
    case invalidClientRequirement
    case unsupportedDevice(String)
    case transcriptDeviceMismatch
    case transcriptIncomplete
    case transcriptPlanMismatch
  }

  public actor ClosedEngineHelperServer {
    private static let explicitlyUnsupportedDevices = ["apple,j614s"]

    private let workingDirectory: URL
    private let credentialValidator: any MachineOwnerCredentialValidating
    private let executor: any ImportedEngineHandoffExecuting
    private let importer: EngineHandoffPackageImporter
    private var isExecuting = false

    public init(
      workingDirectory: URL,
      executor: any ImportedEngineHandoffExecuting,
      credentialValidator: any MachineOwnerCredentialValidating =
        OpenDirectoryMachineOwnerCredentialValidator()
    ) {
      self.workingDirectory = workingDirectory
      self.executor = executor
      self.credentialValidator = credentialValidator
      importer = EngineHandoffPackageImporter()
    }

    /// `progress` is optional and advisory: when a connected app exports the
    /// journal callback, the helper tails the run's journal and forwards whole
    /// lines. Passing nil reproduces the previous behavior exactly.
    public func submit(
      packageDirectory: FileHandle,
      authorization: MachineOwnerAuthorization,
      operation: EngineHandoffOperation = .install,
      progress: (any EngineJournalProgressSink)? = nil
    ) async throws -> Data {
      guard !isExecuting else {
        throw ClosedEngineHelperError.busy
      }
      isExecuting = true
      defer { isExecuting = false }

      do {
        try credentialValidator.validate(authorization)
      } catch {
        throw ClosedEngineHelperError.invalidMachineOwnerCredentials
      }

      let package = try importer.prepare(
        from: packageDirectory,
        in: workingDirectory
      )
      defer { try? FileManager.default.removeItem(at: package.packageURL) }

      guard
        !Self.explicitlyUnsupportedDevices.contains(
          package.deviceIdentifier
        )
      else {
        throw ClosedEngineHelperError.unsupportedDevice(
          package.deviceIdentifier
        )
      }

      var tailer: EngineJournalTailer?
      if let progress,
        let journalURL = EngineJournalLocator.journalURL(
          workingDirectory: workingDirectory,
          bindingDigest: package.bindingDigest
        )
      {
        let started = EngineJournalTailer(
          journalURL: journalURL,
          expectedOwner: geteuid(),
          sink: progress
        )
        await started.start()
        tailer = started
      }

      let result: Data
      do {
        result = try await executor.execute(
          package,
          authorization: authorization,
          operation: operation
        )
      } catch {
        await tailer?.stop()
        throw error
      }
      await tailer?.stop()

      let transcript = try AppleInstallerTrustCore()
        .validateEngineTranscript(result)
      guard transcript.support == .supported else {
        throw ClosedEngineHelperError.unsupportedDevice(
          package.deviceIdentifier
        )
      }
      guard transcript.deviceIdentifier == package.deviceIdentifier,
        transcript.plan?.deviceIdentifier == package.deviceIdentifier
      else {
        throw ClosedEngineHelperError.transcriptDeviceMismatch
      }
      guard transcript.plan?.planDigest == package.planDigest else {
        throw ClosedEngineHelperError.transcriptPlanMismatch
      }
      guard transcript.completion != nil else {
        throw ClosedEngineHelperError.transcriptIncomplete
      }
      return result
    }
  }

  public final class ClosedEngineXPCServiceEndpoint:
    NSObject, ClosedEngineXPCService
  {
    private let server: ClosedEngineHelperServer

    public init(server: ClosedEngineHelperServer) {
      self.server = server
    }

    public func submit(
      packageDirectory: FileHandle,
      operation: String,
      machineOwner: String,
      password: Data,
      reply: @escaping @Sendable (Data?, NSError?) -> Void
    ) {
      // NSXPCConnection.current() is only valid synchronously inside the
      // exported method, so the client proxy is captured before the Task.
      let client =
        NSXPCConnection.current()?
        .remoteObjectProxyWithErrorHandler { _ in
          // The peer exports no progress client: streaming stays off and the
          // authoritative reply path is untouched.
        } as? ClosedEngineProgressClient
      let sink = client.map(XPCJournalProgressSink.init(client:))
      let server = server
      Task {
        do {
          guard let operation = EngineHandoffOperation(rawValue: operation)
          else {
            throw ClosedEngineHelperError.invalidOperation
          }
          let authorization = try MachineOwnerAuthorization(
            username: machineOwner,
            password: password
          )
          let response = try await server.submit(
            packageDirectory: packageDirectory,
            authorization: authorization,
            operation: operation,
            progress: sink
          )
          reply(response, nil)
        } catch {
          reply(nil, EngineXPCErrorBridge.serviceError(for: error))
        }
      }
    }
  }

  public final class AuthenticatedEngineXPCListenerDelegate:
    NSObject, NSXPCListenerDelegate
  {
    private let clientCodeSigningRequirement: String
    private let endpoint: ClosedEngineXPCServiceEndpoint

    public init(
      clientCodeSigningRequirement: String,
      server: ClosedEngineHelperServer
    ) throws {
      guard
        EngineCodeSigningRequirement.isValid(
          clientCodeSigningRequirement
        )
      else {
        throw ClosedEngineHelperError.invalidClientRequirement
      }
      self.clientCodeSigningRequirement = clientCodeSigningRequirement
      endpoint = ClosedEngineXPCServiceEndpoint(server: server)
    }

    public func listener(
      _ listener: NSXPCListener,
      shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
      connection.setCodeSigningRequirement(clientCodeSigningRequirement)
      connection.remoteObjectInterface = NSXPCInterface(
        with: ClosedEngineProgressClient.self
      )
      connection.exportedInterface = NSXPCInterface(
        with: ClosedEngineXPCService.self
      )
      connection.exportedObject = endpoint
      connection.activate()
      return true
    }
  }
#endif
