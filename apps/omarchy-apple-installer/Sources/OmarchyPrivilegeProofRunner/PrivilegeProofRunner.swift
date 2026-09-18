import Darwin
import Foundation
import OmarchyInstallerPrivilegeCore

/// Developer tooling only. No installer engine or shipping UI dependency.
@main
struct PrivilegeProofRunner {
  private static func candidatePins() throws -> PrivilegeProofArtifactPins {
    try PrivilegeProofArtifactPins(
      appSHA256: "1839a41e1d2dcb9e2c1c8255d7373847571ec515af38ed465d18a444784e8fa9",
      workerSHA256: "84a77bd4b2723174b067b1d61bab1b403ca05218adde8d8eaacce78d4564d1d6",
      infoSHA256: "28ecce0ded6d70b977687c575e07520dd2a5bb70b171d3ad1a70db6a117ea782",
      workerCDHash: "1c1d0d1c7ee1f1608cb61c15956f40f21fe06684")
  }

  @MainActor
  static func main() async {
    if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "untrusted-peer",
      let id = UUID(uuidString: CommandLine.arguments[2]), geteuid() != 0
    {
      do {
        _ = try await PrivilegeProofPeerCheck.request(PrivilegeProofLaunch(id: id))
        emit(["event": "peer-observation", "replyReceived": "true", "nonce": id.uuidString])
        exit(EX_SOFTWARE)
      } catch {
        emit([
          "event": "peer-observation", "replyReceived": "false", "nonce": id.uuidString,
          "error": error.localizedDescription,
        ])
        return
      }
    }
    guard CommandLine.arguments.count == 3,
      ["check", "run", "negative", "startup"].contains(CommandLine.arguments[1]),
      CommandLine.arguments[2].hasPrefix("/"), geteuid() != 0
    else {
      emit([
        "event": "usage",
        "message":
          "OmarchyPrivilegeProofRunner check|run|negative|startup /absolute/candidate.app (as a normal user)",
      ])
      exit(EX_USAGE)
    }
    let bundle = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    var backend: ServiceManagementProofBackend?
    do {
      let runnerBackend = ServiceManagementProofBackend(
        bundleURL: bundle, allowsAuthorization: true, retainsBatchAuthorization: true,
        artifactPins: try candidatePins())
      backend = runnerBackend
      try validateCandidate(bundle)
      emit([
        "event": "candidate-verified", "uid": "\(geteuid())",
        "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
      ])
      if CommandLine.arguments[1] == "check" { return }
      // Bounds the entire qualification process, including an unattended prompt.
      // Each worker has its own independent 12-second bound after this process exits.
      DispatchQueue.global().asyncAfter(deadline: .now() + 120) { exit(EX_TEMPFAIL) }
      let session = PrivilegeProofSession(backend: runnerBackend)
      let modes: [PrivilegeProofMode] =
        CommandLine.arguments[1] == "run" ? [.roundTrip, .idleExpiry] : [.roundTrip]
      for mode in modes {
        try validateCandidate(bundle)
        emit(["event": "started", "check": mode.rawValue])
        await session.run(mode)
        emit([
          "event": "result", "check": mode.rawValue,
          "passed": session.passed ? "true" : "false",
          "status": session.status, "evidence": session.evidence.joined(separator: "\n"),
        ])
        if !session.passed {
          await backend?.endQualificationBatch()
          exit(EX_SOFTWARE)
        }
      }
      if CommandLine.arguments[1] == "startup" {
        try await failedLaunchCheck(backend: runnerBackend, startupFailure: true)
        await backend?.endQualificationBatch()
        emit(["event": "complete", "passed": "pending-system-evidence"])
        return
      }
      if CommandLine.arguments[1] == "negative" {
        try await negativeChecks(backend: runnerBackend)
        await backend?.endQualificationBatch()
        emit(["event": "complete", "passed": "pending-system-evidence"])
        return
      }
      await backend?.endQualificationBatch()
      emit(["event": "complete", "passed": "true"])
    } catch {
      await backend?.endQualificationBatch()
      emit(["event": "failed", "message": error.localizedDescription])
      exit(EX_SOFTWARE)
    }
  }

  private static func validateCandidate(_ bundle: URL) throws {
    try candidatePins().validate(bundle)
    let appRequirement = try PrivilegeProofIdentity.requirement(
      identifier: PrivilegeProofIdentity.app, team: "T2C384FJBD")
    let workerRequirement = try PrivilegeProofIdentity.requirement(
      identifier: PrivilegeProofIdentity.worker, team: "T2C384FJBD")
    try PrivilegeProofSigning.validateFile(bundle, requirement: appRequirement)
    try PrivilegeProofSigning.validateFile(
      bundle.appendingPathComponent("Contents/Helpers/OmarchyPrivilegeProofWorker"),
      requirement: workerRequirement)
  }

  static func emit(_ fields: [String: String]) {
    var fields = fields
    fields["at"] = ISO8601DateFormatter().string(from: Date())
    guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
  }
}
