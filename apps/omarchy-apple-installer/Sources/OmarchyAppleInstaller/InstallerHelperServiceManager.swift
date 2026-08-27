#if os(macOS)
  import Foundation
  import ServiceManagement

  public enum InstallerHelperServiceStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unknown
  }

  public protocol InstallerHelperServiceControlling: Sendable {
    var status: InstallerHelperServiceStatus { get }
    func register() throws
  }

  public struct InstallerHelperServiceManager: Sendable {
    private let controller: any InstallerHelperServiceControlling

    public init(controller: any InstallerHelperServiceControlling) {
      self.controller = controller
    }

    public static func bundledDaemon() -> Self {
      Self(
        controller: SMAppServiceController(
          service: .daemon(
            plistName: InstallerProductIdentity.helperDaemonPlistName
          )
        )
      )
    }

    public var status: InstallerHelperServiceStatus {
      controller.status
    }

    public func registerAfterOwnerAuthorization() throws {
      try controller.register()
    }
  }

  private final class SMAppServiceController:
    InstallerHelperServiceControlling,
    @unchecked Sendable
  {
    private let service: SMAppService

    init(service: SMAppService) {
      self.service = service
    }

    var status: InstallerHelperServiceStatus {
      switch service.status {
      case .notRegistered:
        .notRegistered
      case .enabled:
        .enabled
      case .requiresApproval:
        .requiresApproval
      case .notFound:
        .notFound
      @unknown default:
        .unknown
      }
    }

    func register() throws {
      try service.register()
    }
  }
#endif
