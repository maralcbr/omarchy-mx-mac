#if os(macOS)
  import Foundation

  public protocol ImportedEngineHandoffExecuting: Sendable {
    func execute(
      _ package: ImportedEngineHandoffPackage
    ) async throws -> Data
  }

  public enum ClosedEngineHelperError: Error, Equatable, Sendable {
    case busy
    case invalidClientRequirement
    case unsupportedDevice(String)
    case transcriptDeviceMismatch
    case transcriptIncomplete
    case transcriptPlanMismatch
  }

  public actor ClosedEngineHelperServer {
    private static let explicitlyUnsupportedDevices = ["apple,j614s"]

    private let workingDirectory: URL
    private let executor: any ImportedEngineHandoffExecuting
    private let importer: EngineHandoffPackageImporter
    private var isExecuting = false

    public init(
      workingDirectory: URL,
      executor: any ImportedEngineHandoffExecuting
    ) {
      self.workingDirectory = workingDirectory
      self.executor = executor
      importer = EngineHandoffPackageImporter()
    }

    public func submit(
      packageDirectory: FileHandle
    ) async throws -> Data {
      guard !isExecuting else {
        throw ClosedEngineHelperError.busy
      }
      isExecuting = true
      defer { isExecuting = false }

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

      let result = try await executor.execute(package)
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
      reply: @escaping @Sendable (Data?, NSError?) -> Void
    ) {
      let server = server
      Task {
        do {
          let response = try await server.submit(
            packageDirectory: packageDirectory
          )
          reply(response, nil)
        } catch {
          reply(nil, error as NSError)
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
      connection.exportedInterface = NSXPCInterface(
        with: ClosedEngineXPCService.self
      )
      connection.exportedObject = endpoint
      connection.activate()
      return true
    }
  }
#endif
