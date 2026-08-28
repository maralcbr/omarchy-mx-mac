#if os(macOS)
  import Darwin
  import Foundation
  import Security

  @objc public protocol ClosedEngineXPCService {
    func submit(
      packageDirectory: FileHandle,
      reply: @escaping @Sendable (Data?, NSError?) -> Void
    )
  }

  public enum EngineXPCSubmissionError: Error, Equatable, Sendable {
    case invalidMachServiceName
    case invalidCodeSigningRequirement
    case unsafeHandoffPackage
    case connectionFailed
    case helperRejected(domain: String, code: Int)
    case emptyResponse
  }

  public struct AuthenticatedEngineXPCSubmitter:
    EngineHandoffSubmitting, Sendable
  {
    private let machServiceName: String
    private let helperCodeSigningRequirement: String

    public init(
      machServiceName: String,
      helperCodeSigningRequirement: String
    ) throws {
      guard Self.isMachServiceName(machServiceName) else {
        throw EngineXPCSubmissionError.invalidMachServiceName
      }
      guard
        EngineCodeSigningRequirement.isValid(
          helperCodeSigningRequirement
        )
      else {
        throw EngineXPCSubmissionError.invalidCodeSigningRequirement
      }
      self.machServiceName = machServiceName
      self.helperCodeSigningRequirement = helperCodeSigningRequirement
    }

    public func submit(_ handoff: PreparedEngineHandoff) async throws -> Data {
      let descriptor = Darwin.open(
        handoff.packageURL.path,
        O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
      )
      guard descriptor >= 0 else {
        throw EngineXPCSubmissionError.unsafeHandoffPackage
      }

      var status = stat()
      guard fstat(descriptor, &status) == 0,
        (status.st_mode & S_IFMT) == S_IFDIR,
        status.st_mode & 0o077 == 0
      else {
        Darwin.close(descriptor)
        throw EngineXPCSubmissionError.unsafeHandoffPackage
      }

      let directoryHandle = FileHandle(
        fileDescriptor: descriptor,
        closeOnDealloc: true
      )
      let connection = NSXPCConnection(
        machServiceName: machServiceName,
        options: .privileged
      )
      let connectionHandle = SendableXPCConnection(connection)
      connection.remoteObjectInterface = NSXPCInterface(
        with: ClosedEngineXPCService.self
      )
      connection.setCodeSigningRequirement(helperCodeSigningRequirement)

      return try await withCheckedThrowingContinuation { continuation in
        let gate = EngineXPCReplyGate(continuation: continuation)
        connection.interruptionHandler = {
          gate.resume(
            throwing: EngineXPCSubmissionError.connectionFailed
          )
        }
        connection.invalidationHandler = {
          gate.resume(
            throwing: EngineXPCSubmissionError.connectionFailed
          )
        }
        connection.activate()

        guard
          let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
            gate.resume(
              throwing: EngineXPCSubmissionError.connectionFailed
            )
            connectionHandle.invalidate()
          }) as? ClosedEngineXPCService
        else {
          gate.resume(
            throwing: EngineXPCSubmissionError.connectionFailed
          )
          connectionHandle.invalidate()
          return
        }

        proxy.submit(packageDirectory: directoryHandle) { response, error in
          defer { connectionHandle.invalidate() }
          if let error {
            gate.resume(
              throwing: EngineXPCSubmissionError.helperRejected(
                domain: error.domain,
                code: error.code
              )
            )
          } else if let response, !response.isEmpty {
            gate.resume(returning: response)
          } else {
            gate.resume(
              throwing: EngineXPCSubmissionError.emptyResponse
            )
          }
        }
      }
    }

    static func isMachServiceName(_ value: String) -> Bool {
      guard (3...255).contains(value.utf8.count),
        value.contains("."),
        value.first != ".",
        value.last != "."
      else {
        return false
      }
      return value.utf8.allSatisfy { byte in
        (byte >= 48 && byte <= 57)
          || (byte >= 65 && byte <= 90)
          || (byte >= 97 && byte <= 122)
          || byte == 45
          || byte == 46
      }
    }
  }

  enum EngineCodeSigningRequirement {
    static func isValid(_ value: String) -> Bool {
      guard !value.isEmpty, value.utf8.count <= 4_096 else {
        return false
      }
      var requirement: SecRequirement?
      let status = SecRequirementCreateWithString(
        value as CFString,
        SecCSFlags(),
        &requirement
      )
      return status == errSecSuccess && requirement != nil
    }
  }

  private final class SendableXPCConnection: @unchecked Sendable {
    private let connection: NSXPCConnection

    init(_ connection: NSXPCConnection) {
      self.connection = connection
    }

    func invalidate() {
      connection.invalidate()
    }
  }

  private final class EngineXPCReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, any Error>?

    init(continuation: CheckedContinuation<Data, any Error>) {
      self.continuation = continuation
    }

    func resume(returning data: Data) {
      takeContinuation()?.resume(returning: data)
    }

    func resume(throwing error: any Error) {
      takeContinuation()?.resume(throwing: error)
    }

    private func takeContinuation() -> CheckedContinuation<Data, any Error>? {
      lock.lock()
      defer { lock.unlock() }
      let candidate = continuation
      continuation = nil
      return candidate
    }
  }
#endif
