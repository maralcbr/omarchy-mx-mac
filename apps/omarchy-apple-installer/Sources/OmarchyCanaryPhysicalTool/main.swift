import CryptoKit
import Darwin
import Foundation
import OmarchyAppleInstallerTrustCore

private enum PhysicalError: Error, CustomStringConvertible {
  case usage
  case privilegeRequired
  case unsafeInput(String)
  case admission(String)

  var description: String {
    switch self {
    case .usage:
      return
        "usage: OmarchyCanaryPhysicalTool execute <bundle> <signed-receipt.json> <observed-enrollment.json> <expected-trust-fingerprint> <state-directory> <machine-owner>"
    case .privilegeRequired:
      return "physical canary execution requires root"
    case .unsafeInput(let value), .admission(let value):
      return value
    }
  }
}

private struct ExecutionRequest: Encodable {
  let format = 1
  let operation = "repair-installed-system"
  let planDigest: String
  let deviceIdentifier: String
  let storeIdentifier: String
  let layoutDigest: String
  let candidateKind: String
  let sourceIdentifier: String
  let offsetBytes: UInt64
  let lengthBytes: UInt64
  let engineVersion: String
  let requiredHumanSteps: [String]

  enum CodingKeys: String, CodingKey {
    case format, operation
    case planDigest = "plan_digest"
    case deviceIdentifier = "device_identifier"
    case storeIdentifier = "store_identifier"
    case layoutDigest = "layout_digest"
    case candidateKind = "candidate_kind"
    case sourceIdentifier = "source_identifier"
    case offsetBytes = "offset_bytes"
    case lengthBytes = "length_bytes"
    case engineVersion = "engine_version"
    case requiredHumanSteps = "required_human_steps"
  }
}

private struct ExecutionIdentity: Encodable {
  let format = 1
  let bindingDigest: String
  let trustRootFingerprint: String
  let catalogSequence: UInt64
  let catalogPayloadDigest: String
  let planDigest: String
  let engineDigest: String
  let metadataDigest: String
  let payloadDigest: String
  let repairManifestDigest: String

  enum CodingKeys: String, CodingKey {
    case format
    case bindingDigest = "binding_digest"
    case trustRootFingerprint = "trust_root_fingerprint"
    case catalogSequence = "catalog_sequence"
    case catalogPayloadDigest = "catalog_payload_digest"
    case planDigest = "plan_digest"
    case engineDigest = "engine_digest"
    case metadataDigest = "metadata_digest"
    case payloadDigest = "payload_digest"
    case repairManifestDigest = "repair_manifest_digest"
  }
}

private struct SignedReceiptDocument: Decodable {
  let receipt: CanaryPayloadCacheReceipt
  let signature: Data
  let publicKey: Data

  enum CodingKeys: String, CodingKey {
    case receipt, signature
    case publicKey = "public_key"
  }
}

@main
private enum OmarchyCanaryPhysicalTool {
  static func main() async {
    do {
      try await run(Array(CommandLine.arguments.dropFirst()))
    } catch {
      fputs("Omarchy physical canary failed: \(error)\n", stderr)
      exit(1)
    }
  }

  private static func run(_ arguments: [String]) async throws {
    guard arguments.count == 7, arguments[0] == "execute" else {
      throw PhysicalError.usage
    }
    guard geteuid() == 0 else { throw PhysicalError.privilegeRequired }

    let bundle = URL(fileURLWithPath: arguments[1], isDirectory: true)
    let receiptURL = URL(fileURLWithPath: arguments[2])
    let enrollmentURL = URL(fileURLWithPath: arguments[3])
    let trustFingerprint = arguments[4]
    let stateDirectory = URL(fileURLWithPath: arguments[5], isDirectory: true)
    let machineOwner = arguments[6]

    let candidate = try CanaryCandidateBundleReader().read(from: bundle)
    guard SHA256Digest(hashing: candidate.publicKey).rawValue == trustFingerprint
    else {
      throw PhysicalError.admission("canary trust root mismatch")
    }
    let receiptDecoder = JSONDecoder()
    receiptDecoder.dateDecodingStrategy = .iso8601
    let receiptDocument = try receiptDecoder.decode(
      SignedReceiptDocument.self,
      from: readSmall(receiptURL, maximumBytes: 65_536)
    )
    let signedReceipt = SignedCanaryPayloadReceipt(
      receipt: receiptDocument.receipt,
      signature: receiptDocument.signature,
      publicKey: receiptDocument.publicKey
    )
    let enrollmentDecoder = JSONDecoder()
    enrollmentDecoder.keyDecodingStrategy = .convertFromSnakeCase
    let observedEnrollment = try enrollmentDecoder.decode(
      CanaryEnrollment.self,
      from: readSmall(enrollmentURL, maximumBytes: 65_536)
    )

    try ensurePrivateRootDirectory(stateDirectory)
    let sequenceURL = stateDirectory.appendingPathComponent("last-sequence")
    let previousSequence = try readSequence(sequenceURL)
    var replayGuard = CanaryReplayGuard(lastAcceptedSequence: previousSequence)
    let admission = try CanaryAdmissionAdapter(
      publicKey: candidate.publicKey,
      expectedTrustRootFingerprint: trustFingerprint
    )
    let admitted = try admission.admit(
      candidate,
      observedEnrollment: observedEnrollment,
      payloadReceipt: signedReceipt,
      replayGuard: &replayGuard
    )

    let engineArtifact = try exactlyOne(
      candidate.changedArtifacts,
      where: { $0.relativePath.hasPrefix("engine/") && $0.relativePath.hasSuffix(".tar.gz") },
      role: "engine"
    )
    let metadataArtifact = try exactlyOne(
      candidate.changedArtifacts,
      where: { $0.relativePath == "metadata/installer_data.json" },
      role: "metadata"
    )
    let physicalToolArtifact = try exactlyOne(
      candidate.changedArtifacts,
      where: { $0.relativePath == "tools/OmarchyCanaryPhysicalTool" },
      role: "physical tool"
    )
    guard candidate.changedArtifacts.count == 3 else {
      throw PhysicalError.admission("unexpected canary artifacts")
    }
    try verifyRunningTool(physicalToolArtifact)

    let payloadURL = URL(fileURLWithPath: signedReceipt.receipt.path)
    try verifyCachedPayload(payloadURL, receipt: signedReceipt.receipt)

    let executionParent = stateDirectory.appendingPathComponent(
      "sequence-\(admitted.sequence)-\(UUID().uuidString.lowercased())",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: executionParent,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    let securedBundle = executionParent.appendingPathComponent("candidate", isDirectory: true)
    try FileManager.default.createDirectory(
      at: securedBundle,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    let engineURL = try stage(
      engineArtifact,
      from: bundle,
      into: securedBundle
    )
    let metadataURL = try stage(
      metadataArtifact,
      from: bundle,
      into: securedBundle
    )
    let repairURL = try stage(
      candidate.repairManifest,
      from: bundle,
      into: securedBundle
    )

    let executor = PinnedAsahiEngineExecutor()
    let archive = try PinnedAsahiEngineArchive(
      fileURL: engineURL,
      expectedDigest: engineArtifact.digest,
      expectedSizeBytes: engineArtifact.sizeBytes
    )
    let inspectionData = try await executor.inspect(
      archive,
      repairManifestURL: repairURL,
      in: executionParent
    )
    let inspection = try AppleInstallerTrustCore().validateEngineTranscript(
      inspectionData
    )
    guard inspection.deviceIdentifier == admitted.enrollment.deviceIdentifier,
      inspection.support == .supported,
      let inventory = inspection.inventory,
      inventory.systemStoreIdentifier == admitted.enrollment.diskIdentifier,
      inventory.layoutDigest == admitted.enrollment.layoutDigest,
      inventory.candidates.count == 1,
      let repairCandidate = inventory.candidates.first,
      repairCandidate.kind == "repair"
    else {
      throw PhysicalError.admission("live repair inventory changed")
    }

    let engineVersion = "v0.9.0-omarchy.6-canary"
    let request = try PinnedAsahiPlanRequest(
      inventory: inventory,
      candidate: repairCandidate,
      requestedLengthBytes: repairCandidate.lengthBytes
    )
    let planIdentity = try PinnedAsahiPlanIdentity(
      engineVersion: engineVersion,
      engineDigest: engineArtifact.digest,
      metadataDigest: metadataArtifact.digest,
      payloadDigest: candidate.payload.digest,
      repairManifestDigest: candidate.repairManifest.digest
    )
    let planningData = try await executor.plan(
      archive,
      request: request,
      identity: planIdentity,
      repairManifestURL: repairURL,
      in: executionParent
    )
    let planning = try AppleInstallerTrustCore().validateEngineTranscript(planningData)
    guard let plan = planning.plan,
      plan.candidateKind == "repair",
      plan.repairManifestDigest == candidate.repairManifest.digest,
      plan.layoutDigest == admitted.enrollment.layoutDigest,
      plan.engineDigest == engineArtifact.digest,
      plan.metadataDigest == metadataArtifact.digest,
      plan.payloadDigest == candidate.payload.digest
    else {
      throw PhysicalError.admission("canary plan binding changed")
    }

    let bindingDigest = lengthPrefixedDigest([
      "omarchy.apple.candidate-bound-plan",
      "1",
      trustFingerprint,
      String(admitted.sequence),
      admitted.identityDigest,
      plan.planDigest,
      plan.deviceIdentifier,
      plan.storeIdentifier,
      plan.layoutDigest,
      plan.candidateKind,
      plan.sourceIdentifier,
      String(plan.offsetBytes),
      String(plan.lengthBytes),
      plan.engineDigest,
      plan.metadataDigest,
      plan.payloadDigest,
    ])
    let requestURL = securedBundle.appendingPathComponent("request.json")
    let identityURL = securedBundle.appendingPathComponent("identity.json")
    try writePrivate(
      ExecutionRequest(
        planDigest: plan.planDigest,
        deviceIdentifier: plan.deviceIdentifier,
        storeIdentifier: plan.storeIdentifier,
        layoutDigest: plan.layoutDigest,
        candidateKind: plan.candidateKind,
        sourceIdentifier: plan.sourceIdentifier,
        offsetBytes: plan.offsetBytes,
        lengthBytes: plan.lengthBytes,
        engineVersion: plan.engineVersion,
        requiredHumanSteps: plan.requiredHumanSteps
      ),
      to: requestURL
    )
    try writePrivate(
      ExecutionIdentity(
        bindingDigest: bindingDigest,
        trustRootFingerprint: trustFingerprint,
        catalogSequence: admitted.sequence,
        catalogPayloadDigest: admitted.identityDigest,
        planDigest: plan.planDigest,
        engineDigest: plan.engineDigest,
        metadataDigest: plan.metadataDigest,
        payloadDigest: plan.payloadDigest,
        repairManifestDigest: candidate.repairManifest.digest
      ),
      to: identityURL
    )

    print("CANARY — NOT FOR RELEASE")
    print("admitted_sequence=\(admitted.sequence)")
    print("candidate_identity=\(admitted.identityDigest)")
    print("plan_digest=sha256:\(plan.planDigest)")
    print("live_layout=\(inventory.layoutDigest)")
    print("READ-ONLY PREFLIGHT COMPLETE; OWNER PASSWORD REQUIRED BEFORE FIRST WRITE")

    let authorization = try readAndValidateAuthorization(username: machineOwner)
    try persistSequence(admitted.sequence, at: sequenceURL)
    let package = ImportedEngineHandoffPackage(
      packageURL: securedBundle,
      manifestURL: bundle.appendingPathComponent("canary-candidate.json"),
      requestURL: requestURL,
      identityURL: identityURL,
      engineURL: engineURL,
      metadataURL: metadataURL,
      payloadURL: payloadURL,
      repairManifestURL: repairURL,
      bindingDigest: bindingDigest,
      planDigest: plan.planDigest,
      deviceIdentifier: plan.deviceIdentifier,
      storeIdentifier: plan.storeIdentifier
    )
    let result = try await executor.execute(
      package,
      authorization: authorization,
      operation: .install
    )
    let completed = try AppleInstallerTrustCore().validateEngineTranscript(result)
    guard completed.plan == plan, completed.completion == .installed else {
      throw PhysicalError.admission("repair completion is unavailable")
    }
    print("CANARY REPAIR COMPLETED WITH EXHAUSTIVE READ-BACK")
    print(String(decoding: result, as: UTF8.self))
  }

  private static func exactlyOne(
    _ artifacts: [CanaryArtifact],
    where predicate: (CanaryArtifact) -> Bool,
    role: String
  ) throws -> CanaryArtifact {
    let matches = artifacts.filter(predicate)
    guard matches.count == 1 else {
      throw PhysicalError.admission("invalid \(role) artifact")
    }
    return matches[0]
  }

  private static func stage(
    _ artifact: CanaryArtifact,
    from bundle: URL,
    into destinationRoot: URL
  ) throws -> URL {
    let source = bundle.appendingPathComponent(artifact.relativePath)
    let destination = destinationRoot.appendingPathComponent(
      URL(fileURLWithPath: artifact.relativePath).lastPathComponent
    )
    let data = try Data(contentsOf: source)
    guard UInt64(data.count) == artifact.sizeBytes,
      SHA256Digest(hashing: data).rawValue == artifact.digest
    else {
      throw PhysicalError.unsafeInput("artifact changed during secure staging")
    }
    try data.write(to: destination, options: .withoutOverwriting)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o400, .ownerAccountID: 0, .groupOwnerAccountID: 0],
      ofItemAtPath: destination.path
    )
    return destination
  }

  private static func ensurePrivateRootDirectory(_ url: URL) throws {
    if !FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
    }
    var status = stat()
    guard lstat(url.path, &status) == 0,
      (status.st_mode & S_IFMT) == S_IFDIR,
      status.st_uid == 0,
      status.st_mode & 0o077 == 0
    else {
      throw PhysicalError.unsafeInput("unsafe canary state directory")
    }
  }

  private static func verifyCachedPayload(
    _ url: URL,
    receipt: CanaryPayloadCacheReceipt
  ) throws {
    var status = stat()
    guard lstat(url.path, &status) == 0,
      (status.st_mode & S_IFMT) == S_IFREG,
      status.st_uid == 0,
      status.st_gid == 0,
      status.st_mode & 0o777 == 0o400,
      UInt64(status.st_size) == receipt.sizeBytes
    else {
      throw PhysicalError.unsafeInput("cached payload identity changed")
    }
  }

  private static func verifyRunningTool(_ artifact: CanaryArtifact) throws {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0])
      .standardizedFileURL
    let data = try Data(contentsOf: executable)
    guard UInt64(data.count) == artifact.sizeBytes,
      SHA256Digest(hashing: data).rawValue == artifact.digest
    else {
      throw PhysicalError.unsafeInput("physical canary tool identity changed")
    }
  }

  private static func readSequence(_ url: URL) throws -> UInt64 {
    guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
    let data = try readSmall(url, maximumBytes: 32)
    guard let string = String(data: data, encoding: .utf8),
      let value = UInt64(string.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
      throw PhysicalError.unsafeInput("invalid canary replay state")
    }
    return value
  }

  private static func persistSequence(_ sequence: UInt64, at url: URL) throws {
    try Data("\(sequence)\n".utf8).write(to: url, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o400, .ownerAccountID: 0, .groupOwnerAccountID: 0],
      ofItemAtPath: url.path
    )
  }

  private static func readSmall(_ url: URL, maximumBytes: Int) throws -> Data {
    var status = stat()
    guard lstat(url.path, &status) == 0,
      (status.st_mode & S_IFMT) == S_IFREG,
      status.st_mode & 0o022 == 0,
      status.st_size > 0,
      status.st_size <= maximumBytes
    else {
      throw PhysicalError.unsafeInput("unsafe input: \(url.lastPathComponent)")
    }
    return try Data(contentsOf: url)
  }

  private static func writePrivate<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(value).write(to: url, options: .withoutOverwriting)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o400],
      ofItemAtPath: url.path
    )
  }

  private static func lengthPrefixedDigest(_ fields: [String]) -> String {
    let canonical = fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
    return SHA256Digest(hashing: Data(canonical.utf8)).rawValue
  }

  private static func readAndValidateAuthorization(
    username: String
  ) throws -> MachineOwnerAuthorization {
    var buffer = [CChar](repeating: 0, count: 1_025)
    guard
      readpassphrase(
        "Machine owner password: ",
        &buffer,
        buffer.count,
        0
      ) != nil
    else {
      throw PhysicalError.admission("machine owner password unavailable")
    }
    defer {
      for index in buffer.indices { buffer[index] = 0 }
    }
    let password = Data(
      buffer.prefix(while: { $0 != 0 }).map(UInt8.init(bitPattern:))
    )
    let authorization = try MachineOwnerAuthorization(
      username: username,
      password: password
    )
    try OpenDirectoryMachineOwnerCredentialValidator().validate(authorization)
    return authorization
  }
}
