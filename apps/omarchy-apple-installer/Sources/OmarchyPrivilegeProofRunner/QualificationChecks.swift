import Foundation
import OmarchyInstallerPrivilegeCore

extension PrivilegeProofRunner {
  @MainActor
  static func negativeChecks(backend: ServiceManagementProofBackend) async throws {
    let missing = PrivilegeProofLaunch()
    var missingReplied = false
    do {
      _ = try await PrivilegeProofPeerCheck.request(missing)
      missingReplied = true
    } catch {
      emit([
        "event": "expected-failure", "check": "missing-service",
        "error": error.localizedDescription,
      ])
    }
    guard !missingReplied else { throw PrivilegeProofError.invalidReply }

    let launch = PrivilegeProofLaunch()
    try await backend.start(launch)
    emit(["event": "submitted", "check": "peer-rejection", "label": launch.label])
    do {
      let before = try await backend.probe(launch)
      let peer = Bundle.main.bundleURL.appendingPathComponent(
        "Contents/Helpers/OmarchyUntrustedProofPeer")
      try PrivilegeProofSigning.validateFile(
        peer,
        requirement:
          "anchor apple generic and identifier \"com.omarchy.mx.installer.privilege-proof.untrusted-peer\" and certificate leaf[subject.OU] = \"T2C384FJBD\""
      )
      let child = Process()
      let output = Pipe()
      child.executableURL = peer
      child.arguments = ["untrusted-peer", launch.id.uuidString]
      child.standardOutput = output
      child.standardError = FileHandle.nullDevice
      try child.run()
      child.waitUntilExit()
      let data = output.fileHandleForReading.readDataToEndOfFile()
      guard child.terminationReason == .exit, child.terminationStatus == 0,
        let observation = try JSONSerialization.jsonObject(with: data) as? [String: String],
        observation["event"] == "peer-observation",
        observation["replyReceived"] == "false",
        observation["nonce"] == launch.id.uuidString
      else { throw PrivilegeProofError.invalidReply }
      let afterClientCheck = try await backend.probe(launch)
      guard afterClientCheck.processID == before.processID else {
        throw PrivilegeProofError.invalidReply
      }
      emit([
        "event": "result", "check": "wrong-client-identifier", "passed": "true",
        "label": launch.label, "workerPID": "\(before.processID)",
        "clientPID": "\(child.processIdentifier)",
      ])

      var rejectedRequirementReplied = false
      do {
        _ = try await PrivilegeProofPeerCheck.request(launch, rejectWorker: true)
        rejectedRequirementReplied = true
      } catch {
        emit([
          "event": "expected-failure", "check": "wrong-worker-requirement",
          "error": error.localizedDescription,
        ])
      }
      guard !rejectedRequirementReplied else { throw PrivilegeProofError.invalidReply }
      let afterWorkerCheck = try await backend.probe(launch)
      guard afterWorkerCheck.processID == before.processID else {
        throw PrivilegeProofError.invalidReply
      }
      try await backend.finish(launch)
      try await backend.waitForExit(launch, mode: .roundTrip)
      emit([
        "event": "result", "check": "wrong-worker-requirement", "passed": "true",
        "label": launch.label, "retirement": "verified",
      ])
    } catch {
      let original = error
      do { try await backend.remove(launch) } catch {
        emit([
          "event": "cleanup-failed", "label": launch.label, "error": error.localizedDescription,
        ])
      }
      throw original
    }

    try await failedLaunchCheck(backend: backend, startupFailure: false)
  }

  @MainActor
  static func failedLaunchCheck(backend: ServiceManagementProofBackend, startupFailure: Bool)
    async throws
  {
    let check = startupFailure ? "startup-failure" : "spawn-constraint-mismatch"
    let rejectedLaunch = PrivilegeProofLaunch()
    emit(["event": "started", "check": check, "label": rejectedLaunch.label])
    try await backend.startForQualification(
      rejectedLaunch, fault: startupFailure ? .invalidArgumentCount : .mismatchedSigningIdentifier)
    emit([
      "event": "submitted", "check": check, "label": rejectedLaunch.label,
    ])
    var receivedReply = false
    do {
      _ = try await backend.probe(rejectedLaunch)
      receivedReply = true
      try await backend.finish(rejectedLaunch)
      try await backend.waitForExit(rejectedLaunch, mode: .roundTrip)
    } catch {
      emit([
        "event": "launch-observation", "label": rejectedLaunch.label,
        "error": error.localizedDescription,
      ])
      do { try await backend.remove(rejectedLaunch) } catch {
        emit([
          "event": "cleanup-observation", "label": rejectedLaunch.label,
          "error": error.localizedDescription,
        ])
      }
    }
    emit([
      "event": "failed-launch-observation", "check": check, "label": rejectedLaunch.label,
      "authenticatedReplyReceived": receivedReply ? "true" : "false",
      "verdict": receivedReply
        ? "failed"
        : (startupFailure
          ? "requires-EX_USAGE-and-job-absence" : "requires-AMFI-enforcement-and-job-absence"),
    ])
    guard !receivedReply else { throw PrivilegeProofError.invalidReply }
  }
}
