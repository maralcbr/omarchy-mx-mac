import Darwin
import Foundation
import OmarchyInstallerPrivilegeCore
import OmarchyInstallerSystem
import Security
import ServiceManagement

public enum TemporaryInstallerWorkerError: Error, Equatable, Sendable {
  case authorizationCancelled
  case authorizationFailed(Int32)
  case legacyHelperActive
  case untrustedApp
  case startupCleanupFailed(String)
  case startupFailed
  case incompatibleWorker
}

public struct InstallerWorkerHandshake: Codable, Equatable, Sendable {
  public let version: Int
  public let session: UUID
  public let processID: Int32
  public let effectiveUserID: UInt32

  public init(session: UUID) {
    version = 1
    self.session = session
    processID = getpid()
    effectiveUserID = geteuid()
  }

  func validate(session: UUID, processID: Int32?) throws {
    guard version == 1, self.session == session, self.processID > 1,
      effectiveUserID == 0, processID == nil || self.processID == processID
    else { throw TemporaryInstallerWorkerError.incompatibleWorker }
  }
}

/// Owns one temporary job for this app process. Native authorization happens
/// only when an existing operation needs it, never during initial inspection.
public actor TemporaryInstallerWorker {
  public static let shared = TemporaryInstallerWorker()
  public static let appIdentifier = "com.omarchy.mx.installer"
  public static let embeddedWorkerPath = "Contents/Resources/omarchy-apple-installer-helper"

  private struct Active {
    let session: UUID
    let service: String
    let requirement: String
    let pid: Int32
    let leaseID = UUID()
  }
  private var pendingStartup: (service: String, pid: Int32?)?
  private var active: Active?
  private var starting = false
  private var retiring = false

  public init() {}

  public static func serviceName(_ session: UUID) -> String {
    InstallerProductIdentity.helperIdentifier + ".session." + session.uuidString.lowercased()
  }

  public func ready(
    journalProgress: (@Sendable (Data) -> Void)? = nil
  ) async throws -> AuthenticatedEngineXPCSubmitter {
    guard !starting else { throw ClosedEngineHelperError.busy }
    if retiring {
      guard let active, !Self.jobExists(active.service), Self.processAbsent(active.pid) else {
        throw ClosedEngineHelperError.busy
      }
      self.active = nil
      retiring = false
    }
    starting = true
    defer { starting = false }
    try Self.requireNoLegacyHelper()
    if let pendingStartup {
      guard !Self.jobExists(pendingStartup.service), let pid = pendingStartup.pid,
        Self.processAbsent(pid)
      else {
        throw TemporaryInstallerWorkerError.startupCleanupFailed(
          "A previous startup has not been confirmed retired")
      }
      self.pendingStartup = nil
    }
    if let active {
      if Self.jobExists(active.service) {
        let refreshed = Active(
          session: active.session, service: active.service, requirement: active.requirement,
          pid: active.pid)
        let client = try client(refreshed, journalProgress: journalProgress)
        try await client.ping()
        self.active = refreshed
        return client
      }
      self.active = nil
    }
    let bundle = Bundle.main.bundleURL
    let worker = bundle.appendingPathComponent(Self.embeddedWorkerPath)
    let team: String
    let appRequirement: String
    let helperRequirement: String
    let hash: Data
    let appHash: Data
    do {
      team = try InstallerCodeSigning.currentTeam(expectedIdentifier: Self.appIdentifier)
      appRequirement = try InstallerCodeSigningRequirement.requirement(
        identifier: Self.appIdentifier, team: team)
      helperRequirement = try InstallerCodeSigningRequirement.requirement(
        identifier: InstallerProductIdentity.helperIdentifier, team: team)
      try InstallerCodeSigning.validateFile(bundle, requirement: appRequirement)
      try InstallerCodeSigning.validateFile(worker, requirement: helperRequirement)
      hash = try Self.codeHash(worker)
      appHash = try Self.codeHash(bundle)
    } catch { throw TemporaryInstallerWorkerError.untrustedApp }
    var authorization: AuthorizationRef?
    let created = AuthorizationCreate(nil, nil, [], &authorization)
    guard created == errAuthorizationSuccess, let authorization else {
      throw TemporaryInstallerWorkerError.authorizationFailed(created)
    }
    defer { AuthorizationFree(authorization, []) }
    let result = kSMRightModifySystemDaemons.withCString { name in
      var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
      return withUnsafeMutablePointer(to: &item) { pointer in
        var rights = AuthorizationRights(count: 1, items: pointer)
        return AuthorizationCopyRights(
          authorization, &rights, nil,
          [.interactionAllowed, .extendRights, .preAuthorize], nil)
      }
    }
    if result == errAuthorizationCanceled {
      throw TemporaryInstallerWorkerError.authorizationCancelled
    }
    guard result == errAuthorizationSuccess else {
      throw TemporaryInstallerWorkerError.authorizationFailed(result)
    }
    // No path handed to launchd can change identity during the human delay.
    do {
      try InstallerCodeSigning.validateFile(bundle, requirement: appRequirement)
      try InstallerCodeSigning.validateFile(worker, requirement: helperRequirement)
      guard try Self.codeHash(worker) == hash, try Self.codeHash(bundle) == appHash else {
        throw TemporaryInstallerWorkerError.untrustedApp
      }
    } catch { throw TemporaryInstallerWorkerError.untrustedApp }
    try Self.requireNoLegacyHelper()
    let session = UUID()
    let service = Self.serviceName(session)
    let ownerStart = Self.processStart(getpid())
    guard ownerStart > 0 else { throw TemporaryInstallerWorkerError.startupFailed }
    let descriptor: [String: Any] = [
      "Label": service,
      "ProgramArguments": [
        worker.path, "--temporary", session.uuidString, String(getpid()), String(ownerStart),
      ],
      "MachServices": [service: true],
      "SpawnConstraint": [
        "team-identifier": team, "signing-identifier": InstallerProductIdentity.helperIdentifier,
        "cdhash": hash,
      ],
      "RunAtLoad": true, "LaunchOnlyOnce": true, "ProcessType": "Interactive",
      "AbandonProcessGroup": false,
    ]
    var submissionError: Unmanaged<CFError>?
    guard
      SMJobSubmit(
        kSMDomainSystemLaunchd, descriptor as CFDictionary, authorization, &submissionError)
    else {
      _ = submissionError?.takeRetainedValue()
      throw TemporaryInstallerWorkerError.startupFailed
    }
    pendingStartup = (service, nil)
    var observedPID: Int32?
    do {
      let deadline = ContinuousClock.now.advanced(by: .seconds(5))
      while ContinuousClock.now < deadline {
        if let raw = SMJobCopyDictionary(kSMDomainSystemLaunchd, service as CFString) {
          let job = raw.takeRetainedValue() as NSDictionary
          if let pid = job["PID"] as? NSNumber, pid.int64Value > 1,
            pid.int64Value <= Int64(Int32.max)
          {
            observedPID = pid.int32Value
            pendingStartup = (service, pid.int32Value)
            let candidate = Active(
              session: session, service: service, requirement: helperRequirement,
              pid: pid.int32Value)
            let client = try client(candidate, journalProgress: journalProgress)
            try await client.ping()
            active = candidate
            pendingStartup = nil
            return client
          }
        }
        try await Task.sleep(for: .milliseconds(100))
      }
      throw TemporaryInstallerWorkerError.startupFailed
    } catch {
      if !Self.jobExists(service), let observedPID, Self.processAbsent(observedPID) {
        pendingStartup = nil
        throw TemporaryInstallerWorkerError.startupFailed
      }
      // This job has received only a handshake, never credentials or disk work.
      // Removal is confined to the internally generated job submitted above.
      var cleanupError: Unmanaged<CFError>?
      let removed = SMJobRemove(
        kSMDomainSystemLaunchd, service as CFString, authorization, false, &cleanupError)
      let detail =
        cleanupError.map { String(describing: $0.takeRetainedValue()) }
        ?? "No Service Management detail"
      guard removed else { throw TemporaryInstallerWorkerError.startupCleanupFailed(detail) }
      let deadline = ContinuousClock.now.advanced(by: .seconds(5))
      while ContinuousClock.now < deadline {
        if !Self.jobExists(service), let observedPID, Self.processAbsent(observedPID) {
          pendingStartup = nil
          throw TemporaryInstallerWorkerError.startupFailed
        }
        do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
      }
      throw TemporaryInstallerWorkerError.startupCleanupFailed(
        "Exact worker retirement was not observed")
    }
  }

  #if DEBUG
    /// Private automation entry: handshake and retirement only, never an engine request.
    public func validateAuthorizationOnly() async throws -> String {
      let owner = try await ready()
      guard let started = active else { throw TemporaryInstallerWorkerError.startupFailed }
      await finish(owner)
      guard active == nil, !Self.jobExists(started.service), Self.processAbsent(started.pid) else {
        throw TemporaryInstallerWorkerError.startupCleanupFailed(
          "Authorization check retirement was not confirmed")
      }
      let result: [String: Any] = [
        "session": started.session.uuidString, "workerPID": started.pid,
        "authenticatedRootReply": true, "jobAndProcessRetired": true,
      ]
      return String(
        decoding: try JSONSerialization.data(withJSONObject: result, options: .sortedKeys),
        as: UTF8.self)
    }
  #endif

  public func finish(_ owner: AuthenticatedEngineXPCSubmitter) async {
    guard !starting, !retiring, let active, active.leaseID == owner.workerLeaseID else { return }
    retiring = true
    // Failure leaves the worker to its independent idle expiry. Never force
    // removal of a job that may already have admitted disk work.
    try? await client(active, journalProgress: nil).retireTemporarySession()
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while ContinuousClock.now < deadline, self.active?.session == active.session {
      if !Self.jobExists(active.service), Self.processAbsent(active.pid) {
        self.active = nil
        retiring = false
        return
      }
      do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
    }
  }

  private func client(_ value: Active, journalProgress: (@Sendable (Data) -> Void)?) throws
    -> AuthenticatedEngineXPCSubmitter
  {
    try AuthenticatedEngineXPCSubmitter(
      machServiceName: value.service,
      helperCodeSigningRequirement: value.requirement, journalProgress: journalProgress,
      temporarySession: value.session, expectedWorkerPID: value.pid, workerLeaseID: value.leaseID)
  }

  public static func processStart(_ pid: Int32) -> UInt64 { omarchy_installer_process_start(pid) }

  public static func requireNoLegacyHelper() throws {
    guard !jobExists(InstallerProductIdentity.helperMachServiceName),
      !FileManager.default.fileExists(atPath: InstallerProductIdentity.systemLaunchDaemonPath)
    else { throw TemporaryInstallerWorkerError.legacyHelperActive }
  }

  private static func processAbsent(_ pid: Int32) -> Bool {
    kill(pid, 0) != 0 && errno == ESRCH
  }

  private static func jobExists(_ service: String) -> Bool {
    guard let job = SMJobCopyDictionary(kSMDomainSystemLaunchd, service as CFString) else {
      return false
    }
    _ = job.takeRetainedValue()
    return true
  }

  private static func codeHash(_ file: URL) throws -> Data {
    var code: SecStaticCode?
    var info: CFDictionary?
    guard SecStaticCodeCreateWithPath(file as CFURL, [], &code) == errSecSuccess, let code,
      SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        == errSecSuccess,
      let fields = info as? [String: Any], let hash = fields[kSecCodeInfoUnique as String] as? Data,
      hash.count == 20
    else { throw TemporaryInstallerWorkerError.untrustedApp }
    return hash
  }
}
