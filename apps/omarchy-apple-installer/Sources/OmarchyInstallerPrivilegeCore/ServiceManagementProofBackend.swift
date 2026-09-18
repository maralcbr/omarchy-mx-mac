import Darwin
import Foundation
import Security
import ServiceManagement

public enum PrivilegeProofLaunchFault: Sendable, Equatable {
  case mismatchedSigningIdentifier, invalidArgumentCount
}

/// The deprecated API is confined to this proof adapter. No disk engine is linked here.
public actor ServiceManagementProofBackend: PrivilegeProofBackend {
  private let bundleURL: URL
  private let allowsAuthorization: Bool
  private let retainsBatchAuthorization: Bool
  private let artifactPins: PrivilegeProofArtifactPins?
  private var authorization: AuthorizationRef?
  private var active: PrivilegeProofLaunch?
  private var observedPID: Int32?
  private var observedJob = false
  private var observationEpoch = ContinuousClock.now
  private var retirement = PrivilegeProofRetirement()
  private var helperRequirement = ""

  public init(
    bundleURL: URL, allowsAuthorization: Bool, retainsBatchAuthorization: Bool = false,
    artifactPins: PrivilegeProofArtifactPins? = nil
  ) {
    self.bundleURL = bundleURL
    self.allowsAuthorization = allowsAuthorization
    self.retainsBatchAuthorization = retainsBatchAuthorization
    self.artifactPins = artifactPins
  }

  public func start(_ launch: PrivilegeProofLaunch) async throws {
    try await submit(launch, fault: nil)
  }

  /// Fixed negative cases; never accepts an executable, command, or arbitrary descriptor.
  public func startForQualification(
    _ launch: PrivilegeProofLaunch, fault: PrivilegeProofLaunchFault
  )
    async throws
  {
    guard artifactPins != nil else { throw PrivilegeProofError.untrustedBundle }
    try await submit(launch, fault: fault)
  }

  private func submit(_ launch: PrivilegeProofLaunch, fault: PrivilegeProofLaunchFault?)
    async throws
  {
    guard active == nil else { throw PrivilegeProofError.alreadyRunning }
    guard allowsAuthorization else { throw PrivilegeProofError.previewOnly }
    guard geteuid() != 0 else { throw PrivilegeProofError.untrustedBundle }
    try artifactPins?.validate(bundleURL)
    let team = try PrivilegeProofSigning.currentTeam(expectedIdentifier: PrivilegeProofIdentity.app)
    let appRequirement = try PrivilegeProofIdentity.requirement(
      identifier: PrivilegeProofIdentity.app, team: team)
    helperRequirement = try PrivilegeProofIdentity.requirement(
      identifier: PrivilegeProofIdentity.worker, team: team)
    let worker = bundleURL.appendingPathComponent("Contents/Helpers/OmarchyPrivilegeProofWorker")
    try PrivilegeProofSigning.validateFile(bundleURL, requirement: appRequirement)
    try PrivilegeProofSigning.validateFile(worker, requirement: helperRequirement)
    guard try job(launch) == nil else { throw PrivilegeProofError.alreadyRunning }

    var reference = authorization
    let alreadyOwned = reference != nil
    let creation =
      alreadyOwned ? errAuthorizationSuccess : AuthorizationCreate(nil, nil, [], &reference)
    guard creation == errAuthorizationSuccess, let reference else {
      throw PrivilegeProofError.authorizationFailed(creation)
    }
    var keepAuthorization = false
    defer { if !keepAuthorization && !alreadyOwned { AuthorizationFree(reference, []) } }
    let result =
      alreadyOwned
      ? errAuthorizationSuccess
      : kSMRightModifySystemDaemons.withCString { name in
        var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
        return withUnsafeMutablePointer(to: &item) { pointer in
          var rights = AuthorizationRights(count: 1, items: pointer)
          return AuthorizationCopyRights(
            reference, &rights, nil, [.interactionAllowed, .extendRights, .preAuthorize], nil)
        }
      }
    if result == errAuthorizationCanceled { throw PrivilegeProofError.authorizationCancelled }
    guard result == errAuthorizationSuccess else {
      throw PrivilegeProofError.authorizationFailed(result)
    }
    // Revalidate after the human authorization delay before handing the path to launchd.
    try artifactPins?.validate(bundleURL)
    try PrivilegeProofSigning.validateFile(bundleURL, requirement: appRequirement)
    try PrivilegeProofSigning.validateFile(worker, requirement: helperRequirement)
    var constraint: [String: Any] = [
      "team-identifier": team,
      "signing-identifier": PrivilegeProofIdentity.worker,
    ]
    if let artifactPins { constraint["cdhash"] = artifactPins.workerCDHash }
    if fault == .mismatchedSigningIdentifier {
      constraint["signing-identifier"] = PrivilegeProofIdentity.worker + ".rejected"
    }
    var arguments = [worker.path, launch.id.uuidString]
    if fault == .invalidArgumentCount { arguments.append("invalid-qualification-argument") }
    let description: [String: Any] = [
      "Label": launch.label,
      "ProgramArguments": arguments,
      "MachServices": [launch.label: true],
      "SpawnConstraint": constraint,
      "RunAtLoad": true,
      "LaunchOnlyOnce": true,
      "ProcessType": "Interactive",
    ]
    var error: Unmanaged<CFError>?
    guard SMJobSubmit(kSMDomainSystemLaunchd, description as CFDictionary, reference, &error) else {
      throw PrivilegeProofError.submissionFailed(Self.description(error))
    }
    authorization = reference
    active = launch
    observedPID = nil
    observedJob = false
    observationEpoch = .now
    retirement = PrivilegeProofRetirement()
    keepAuthorization = true
  }

  public func probe(_ launch: PrivilegeProofLaunch) async throws -> PrivilegeProofReply {
    try requireActive(launch)
    try await observeRunningJob(launch)
    let data = try await PrivilegeProofXPCClient(requirement: helperRequirement).request(
      launch, finishing: false)
    let reply = try JSONDecoder().decode(PrivilegeProofReply.self, from: data)
    try reply.validate(for: launch)
    guard reply.processID == observedPID else { throw PrivilegeProofError.invalidReply }
    return reply
  }

  public func finish(_ launch: PrivilegeProofLaunch) async throws {
    try requireActive(launch)
    let data = try await PrivilegeProofXPCClient(requirement: helperRequirement).request(
      launch, finishing: true)
    let reply = try JSONDecoder().decode(PrivilegeProofReply.self, from: data)
    try reply.validate(for: launch)
    guard reply.processID == observedPID else { throw PrivilegeProofError.invalidReply }
  }

  public func waitForExit(_ launch: PrivilegeProofLaunch, mode: PrivilegeProofMode) async throws {
    try requireActive(launch)
    if !observedJob { try await observeRunningJob(launch) }
    let deadline = ContinuousClock.now.advanced(by: .seconds(18))
    while ContinuousClock.now < deadline {
      if try retirement.observe(
        jobPresent: job(launch) != nil, processPresent: !processAbsent(),
        elapsed: observationEpoch.duration(to: .now), mode: mode)
      {
        releaseAuthorization()
        return
      }
      try await Task.sleep(for: .milliseconds(150))
    }
    throw PrivilegeProofError.retirementUnverified
  }

  public func remove(_ launch: PrivilegeProofLaunch) async throws {
    try requireActive(launch)
    if observedJob, observedPID != nil,
      try retirement.observe(
        jobPresent: job(launch) != nil, processPresent: !processAbsent(),
        elapsed: observationEpoch.duration(to: .now), mode: .roundTrip)
    {
      releaseAuthorization()
      return
    }
    // Only the UUID submitted by this adapter may ever be removed.
    var error: Unmanaged<CFError>?
    let removed = SMJobRemove(
      kSMDomainSystemLaunchd, launch.label as CFString, authorization, false, &error)
    if !removed {
      // Even concurrent worker expiry must not hide authorization or IPC failure.
      // Preserve every failed removal result for the qualification record.
      throw PrivilegeProofError.removalFailed(Self.description(error))
    }
    // Without an observed PID, absence alone is not a successful retirement proof.
    guard observedJob, observedPID != nil else {
      releaseAuthorization()
      throw PrivilegeProofError.retirementUnverified
    }
    try await waitForExit(launch, mode: .roundTrip)
  }

  private func observeRunningJob(_ launch: PrivilegeProofLaunch) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(4))
    while ContinuousClock.now < deadline {
      if let dictionary = try job(launch) {
        observedJob = true
        if let pid = dictionary["PID"] as? NSNumber,
          pid.int64Value > 1, pid.int64Value <= Int64(Int32.max)
        {
          observedPID = pid.int32Value
          if try !processAbsent() {
            _ = try retirement.observe(
              jobPresent: true, processPresent: true,
              elapsed: observationEpoch.duration(to: .now), mode: .roundTrip)
            return
          }
        }
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    throw PrivilegeProofError.connectionFailed
  }

  private func requireActive(_ launch: PrivilegeProofLaunch) throws {
    guard active?.id == launch.id else { throw PrivilegeProofError.invalidReply }
  }

  private func job(_ launch: PrivilegeProofLaunch) throws -> [String: Any]? {
    guard let value = SMJobCopyDictionary(kSMDomainSystemLaunchd, launch.label as CFString) else {
      return nil
    }
    guard let dictionary = value.takeRetainedValue() as? [String: Any] else {
      throw PrivilegeProofError.retirementUnverified
    }
    return dictionary
  }

  private func processAbsent() throws -> Bool {
    guard let pid = observedPID, observedJob else { throw PrivilegeProofError.retirementUnverified }
    if kill(pid, 0) == 0 { return false }
    if errno == EPERM { return false }
    guard errno == ESRCH else { throw PrivilegeProofError.retirementUnverified }
    return true
  }

  private func releaseAuthorization() {
    if !retainsBatchAuthorization { freeAuthorization() }
    active = nil
    observedPID = nil
    observedJob = false
  }

  /// The developer runner calls this even when a check fails. It does not remove
  /// jobs: each submitted UUID retains the existing scoped cleanup path.
  public func endQualificationBatch() {
    freeAuthorization()
  }

  private func freeAuthorization() {
    if let authorization { AuthorizationFree(authorization, []) }
    authorization = nil
  }

  private static func description(_ error: Unmanaged<CFError>?) -> String {
    guard let error else { return "Service Management returned no error detail." }
    let value = error.takeRetainedValue()
    return
      "\(CFErrorGetDomain(value) as String) (\(CFErrorGetCode(value))): \(CFErrorCopyDescription(value) as String)"
  }
}
