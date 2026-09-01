import Foundation

enum EngineContractMessage: Equatable, Sendable {
  case inspection(EngineInspectionMessage)
  case inventory(EngineInventoryMessage)
  case plan(EnginePlanMessage)
  case event(EngineEventMessage)
  case checkpoint(EngineCheckpointMessage)
  case completion(EngineCompletionMessage)
}

struct EngineContractEnvelope: Equatable, Sendable {
  let schemaVersion: Int
  let sequence: UInt64
  let message: EngineContractMessage
}

struct EngineInspectionMessage: Codable, Equatable, Sendable {
  let deviceIdentifier: String
  let support: String
}

struct EngineInventoryMessage: Codable, Equatable, Sendable {
  let layoutDigest: String
  let systemStoreIdentifier: String
  let candidates: [EngineInstallCandidate]

  var computedLayoutDigest: String {
    var fields = [systemStoreIdentifier]
    for candidate in candidates {
      fields.append(contentsOf: [
        candidate.kind,
        candidate.sourceIdentifier,
        String(candidate.offsetBytes),
        String(candidate.lengthBytes),
      ])
      if ["repair", "replace"].contains(candidate.kind),
        let identity = candidate.identityDigest
      {
        fields.append(identity)
      }
    }
    return InstallerDigest.lengthPrefixedSHA256(fields).rawValue
  }
}

struct EngineInstallCandidate: Codable, Equatable, Sendable {
  let kind: String
  let sourceIdentifier: String
  let offsetBytes: UInt64
  let lengthBytes: UInt64
  let minimumInstallBytes: UInt64
  let minimumContainerBytes: UInt64
  let identityDigest: String?
}

struct EnginePlanMessage: Codable, Equatable, Sendable {
  let planDigest: String
  let deviceIdentifier: String
  let storeIdentifier: String
  let layoutDigest: String
  let candidateKind: String
  let sourceIdentifier: String
  let offsetBytes: UInt64
  let lengthBytes: UInt64
  let engineVersion: String
  let engineDigest: String
  let metadataDigest: String
  let payloadDigest: String
  let repairManifestDigest: String?
  let requiredHumanSteps: [String]

  var computedPlanDigest: String {
    var fields = [
      deviceIdentifier,
      storeIdentifier,
      layoutDigest,
      candidateKind,
      sourceIdentifier,
      String(offsetBytes),
      String(lengthBytes),
      engineVersion,
      engineDigest,
      metadataDigest,
      payloadDigest,
    ]
    if let repairManifestDigest {
      fields.append(repairManifestDigest)
    }
    fields.append(requiredHumanSteps.joined(separator: ","))
    return InstallerDigest.lengthPrefixedSHA256(fields).hexadecimal
  }
}

struct EngineEventMessage: Codable, Equatable, Sendable {
  let planDigest: String
  let name: String
}

struct EngineCheckpointMessage: Codable, Equatable, Sendable {
  let planDigest: String
  let identifier: String
  let phase: String
  let evidenceDigest: String
}

struct EngineCompletionMessage: Codable, Equatable, Sendable {
  let planDigest: String
  let outcome: String
}

public enum EngineContractError: Error, Equatable, Sendable {
  case emptyTranscript
  case truncatedTranscript
  case lineTooLong(Int)
  case invalidJSON(Int)
  case unknownFields(Int)
  case unsupportedSchema(Int)
  case invalidSequence(expected: UInt64, actual: UInt64)
  case invalidMessage(Int)
  case invalidDigest(Int)
  case unsafeExtent(Int)
  case stalePlanDigest(Int)
  case duplicateCheckpoint(String)
  case phaseRegression(Int)
  case messageAfterCompletion(Int)
}

struct EngineTranscriptDecoder: Sendable {
  static let maximumLineBytes = 65_536

  func decode(_ data: Data) throws -> [EngineContractEnvelope] {
    guard !data.isEmpty else {
      throw EngineContractError.emptyTranscript
    }
    guard data.last == 0x0A else {
      throw EngineContractError.truncatedTranscript
    }

    let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
    guard !lines.isEmpty else {
      throw EngineContractError.emptyTranscript
    }

    var envelopes = [EngineContractEnvelope]()
    for (index, line) in lines.enumerated() {
      let lineNumber = index + 1
      guard line.count <= Self.maximumLineBytes else {
        throw EngineContractError.lineTooLong(lineNumber)
      }
      envelopes.append(try decodeLine(Data(line), lineNumber: lineNumber))
    }

    try validate(envelopes)
    return envelopes
  }

  private func decodeLine(_ data: Data, lineNumber: Int) throws -> EngineContractEnvelope {
    guard
      let object = try? JSONSerialization.jsonObject(with: data),
      let envelope = object as? [String: Any],
      exactKeys(envelope, ["schema_version", "sequence", "type", "payload"]),
      let schemaVersion = envelope["schema_version"] as? Int,
      let sequence = (envelope["sequence"] as? NSNumber)?.uint64Value,
      let type = envelope["type"] as? String,
      let payload = envelope["payload"] as? [String: Any]
    else {
      throw EngineContractError.invalidJSON(lineNumber)
    }

    guard schemaVersion == 1 else {
      throw EngineContractError.unsupportedSchema(schemaVersion)
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    let message: EngineContractMessage

    do {
      switch type {
      case "inspection":
        try requireKeys(payload, ["device_identifier", "support"], lineNumber)
        message = .inspection(try decoder.decode(EngineInspectionMessage.self, from: payloadData))
      case "inventory":
        try requireKeys(
          payload,
          ["layout_digest", "system_store_identifier", "candidates"],
          lineNumber
        )
        guard let candidates = payload["candidates"] as? [[String: Any]] else {
          throw EngineContractError.invalidMessage(lineNumber)
        }
        for candidate in candidates {
          let candidateKeys: Set<String> =
            ["repair", "replace"].contains(candidate["kind"] as? String ?? "")
            ? [
              "kind", "source_identifier", "offset_bytes", "length_bytes",
              "minimum_install_bytes", "minimum_container_bytes",
              "identity_digest",
            ]
            : [
              "kind", "source_identifier", "offset_bytes", "length_bytes",
              "minimum_install_bytes", "minimum_container_bytes",
            ]
          try requireKeys(
            candidate,
            candidateKeys,
            lineNumber
          )
        }
        message = .inventory(try decoder.decode(EngineInventoryMessage.self, from: payloadData))
      case "plan":
        let repairKeys: Set<String> =
          payload["candidate_kind"] as? String == "repair"
          ? ["repair_manifest_digest"]
          : []
        try requireKeys(
          payload,
          Set([
            "plan_digest", "device_identifier", "store_identifier", "layout_digest",
            "candidate_kind", "source_identifier", "offset_bytes", "length_bytes",
            "engine_version", "engine_digest", "metadata_digest", "payload_digest",
            "required_human_steps",
          ]).union(repairKeys),
          lineNumber
        )
        message = .plan(try decoder.decode(EnginePlanMessage.self, from: payloadData))
      case "event":
        try requireKeys(payload, ["plan_digest", "name"], lineNumber)
        message = .event(try decoder.decode(EngineEventMessage.self, from: payloadData))
      case "checkpoint":
        try requireKeys(
          payload,
          ["plan_digest", "identifier", "phase", "evidence_digest"],
          lineNumber
        )
        message = .checkpoint(try decoder.decode(EngineCheckpointMessage.self, from: payloadData))
      case "completion":
        try requireKeys(payload, ["plan_digest", "outcome"], lineNumber)
        message = .completion(try decoder.decode(EngineCompletionMessage.self, from: payloadData))
      default:
        throw EngineContractError.invalidMessage(lineNumber)
      }
    } catch let error as EngineContractError {
      throw error
    } catch {
      throw EngineContractError.invalidMessage(lineNumber)
    }

    return EngineContractEnvelope(
      schemaVersion: schemaVersion,
      sequence: sequence,
      message: message
    )
  }

  private func validate(_ envelopes: [EngineContractEnvelope]) throws {
    var planDigest: String?
    var inventory: EngineInventoryMessage?
    var checkpointIdentifiers = Set<String>()
    var highestPhase = -1
    var completed = false

    for (index, envelope) in envelopes.enumerated() {
      let lineNumber = index + 1
      let expectedSequence = UInt64(lineNumber)
      guard envelope.sequence == expectedSequence else {
        throw EngineContractError.invalidSequence(
          expected: expectedSequence,
          actual: envelope.sequence
        )
      }
      guard !completed else {
        throw EngineContractError.messageAfterCompletion(lineNumber)
      }

      switch envelope.message {
      case .inspection(let inspection):
        guard index == 0, isDeviceIdentifier(inspection.deviceIdentifier),
          ["supported", "unsupported"].contains(inspection.support)
        else {
          throw EngineContractError.invalidMessage(lineNumber)
        }
      case .inventory(let candidateInventory):
        guard index == 1, inventory == nil,
          isSHA256Digest(candidateInventory.layoutDigest),
          candidateInventory.layoutDigest == candidateInventory.computedLayoutDigest,
          isStoreIdentifier(candidateInventory.systemStoreIdentifier)
        else {
          throw EngineContractError.invalidMessage(lineNumber)
        }
        var candidateIdentities = Set<String>()
        for candidate in candidateInventory.candidates {
          guard ["free", "resize", "repair", "replace"].contains(candidate.kind),
            isPartitionIdentifier(candidate.sourceIdentifier),
            candidateIdentities.insert("\(candidate.kind):\(candidate.sourceIdentifier)").inserted,
            candidate.lengthBytes > 0,
            candidate.minimumInstallBytes > 0,
            candidate.offsetBytes.addingReportingOverflow(candidate.lengthBytes).overflow == false,
            (candidate.kind == "free" && candidate.minimumContainerBytes == 0
              && candidate.identityDigest == nil)
              || (candidate.kind == "resize"
                && candidate.minimumContainerBytes > 0
                && candidate.identityDigest == nil)
              || (candidate.kind == "repair"
                && candidate.minimumContainerBytes == 0
                && candidate.minimumInstallBytes == candidate.lengthBytes
                && candidate.identityDigest.map(isSHA256Digest) == true)
              || (candidate.kind == "replace"
                && candidate.minimumContainerBytes == 0
                && candidate.minimumInstallBytes <= candidate.lengthBytes
                && candidate.identityDigest.map(isSHA256Digest) == true)
          else {
            throw EngineContractError.unsafeExtent(lineNumber)
          }
        }
        inventory = candidateInventory
      case .plan(let plan):
        guard let inventory, planDigest == nil, isDeviceIdentifier(plan.deviceIdentifier),
          isPlanDigest(plan.planDigest), plan.planDigest == plan.computedPlanDigest,
          isSHA256Digest(plan.engineDigest),
          isSHA256Digest(plan.metadataDigest), isSHA256Digest(plan.payloadDigest),
          (plan.candidateKind == "repair"
            && plan.repairManifestDigest.map(isSHA256Digest) == true)
            || (plan.candidateKind != "repair" && plan.repairManifestDigest == nil),
          plan.storeIdentifier == inventory.systemStoreIdentifier,
          plan.layoutDigest == inventory.layoutDigest,
          planMatchesInventory(plan, inventory),
          plan.lengthBytes > 0,
          plan.offsetBytes.addingReportingOverflow(plan.lengthBytes).overflow == false,
          !plan.engineVersion.isEmpty,
          !plan.requiredHumanSteps.isEmpty
        else {
          if plan.lengthBytes == 0
            || plan.offsetBytes.addingReportingOverflow(plan.lengthBytes).overflow
          {
            throw EngineContractError.unsafeExtent(lineNumber)
          }
          throw EngineContractError.invalidDigest(lineNumber)
        }
        planDigest = plan.planDigest
      case .event(let event):
        try requireCurrentPlan(event.planDigest, planDigest, lineNumber)
        guard !event.name.isEmpty else {
          throw EngineContractError.invalidMessage(lineNumber)
        }
      case .checkpoint(let checkpoint):
        try requireCurrentPlan(checkpoint.planDigest, planDigest, lineNumber)
        guard isSHA256Digest(checkpoint.evidenceDigest),
          checkpointIdentifiers.insert(checkpoint.identifier).inserted
        else {
          if checkpointIdentifiers.contains(checkpoint.identifier) {
            throw EngineContractError.duplicateCheckpoint(checkpoint.identifier)
          }
          throw EngineContractError.invalidDigest(lineNumber)
        }
        guard let phase = Self.phaseOrder[checkpoint.phase] else {
          throw EngineContractError.invalidMessage(lineNumber)
        }
        guard phase >= highestPhase else {
          throw EngineContractError.phaseRegression(lineNumber)
        }
        highestPhase = phase
      case .completion(let completion):
        try requireCurrentPlan(completion.planDigest, planDigest, lineNumber)
        guard
          ["awaiting_recovery", "awaiting_media", "installed", "manual_recovery_required"]
            .contains(completion.outcome)
        else {
          throw EngineContractError.invalidMessage(lineNumber)
        }
        completed = true
      }
    }
  }

  private func requireCurrentPlan(
    _ candidate: String,
    _ current: String?,
    _ lineNumber: Int
  ) throws {
    guard let current, candidate == current else {
      throw EngineContractError.stalePlanDigest(lineNumber)
    }
  }

  private func planMatchesInventory(
    _ plan: EnginePlanMessage,
    _ inventory: EngineInventoryMessage
  ) -> Bool {
    guard
      let candidate = inventory.candidates.first(where: {
        $0.kind == plan.candidateKind && $0.sourceIdentifier == plan.sourceIdentifier
      }), plan.lengthBytes >= candidate.minimumInstallBytes
    else {
      return false
    }

    if candidate.kind == "free" {
      return plan.offsetBytes == candidate.offsetBytes && plan.lengthBytes <= candidate.lengthBytes
    }

    if candidate.kind == "repair" || candidate.kind == "replace" {
      return plan.offsetBytes == candidate.offsetBytes
        && plan.lengthBytes == candidate.lengthBytes
    }

    guard candidate.kind == "resize",
      candidate.lengthBytes >= candidate.minimumContainerBytes
    else {
      return false
    }
    let available = candidate.lengthBytes - candidate.minimumContainerBytes
    guard plan.lengthBytes <= available else {
      return false
    }
    let (candidateEnd, endOverflow) = candidate.offsetBytes.addingReportingOverflow(
      candidate.lengthBytes
    )
    guard !endOverflow else {
      return false
    }
    return plan.offsetBytes == candidateEnd - plan.lengthBytes
  }

  private func requireKeys(
    _ object: [String: Any],
    _ keys: Set<String>,
    _ lineNumber: Int
  ) throws {
    guard exactKeys(object, keys) else {
      throw EngineContractError.unknownFields(lineNumber)
    }
  }

  private func exactKeys(_ object: [String: Any], _ keys: Set<String>) -> Bool {
    Set(object.keys) == keys
  }

  private func isPlanDigest(_ value: String) -> Bool {
    SHA256Digest(hexadecimal: value) != nil
  }

  private func isSHA256Digest(_ value: String) -> Bool {
    SHA256Digest(rawValue: value) != nil
  }

  private func isDeviceIdentifier(_ value: String) -> Bool {
    value.range(of: #"^apple,[a-z0-9]+$"#, options: .regularExpression) != nil
  }

  private func isStoreIdentifier(_ value: String) -> Bool {
    value.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil
  }

  private func isPartitionIdentifier(_ value: String) -> Bool {
    value.range(of: #"^disk[0-9]+(?:s[0-9]+)?$"#, options: .regularExpression) != nil
  }

  private static let phaseOrder = [
    "preflight": 0,
    "existing_removal": 1,
    "apfs_preparation": 2,
    "stub_and_esp": 3,
    "awaiting_recovery": 4,
    "boot_policy": 5,
    "media_handoff": 6,
    "omarchy_install": 7,
  ]
}
