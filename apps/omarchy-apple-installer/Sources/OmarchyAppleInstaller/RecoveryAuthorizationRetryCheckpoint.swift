#if os(macOS)
  import CryptoKit
  import Foundation

  struct RecoveryAuthorizationRetryCheckpoint {
    private static let eventNames = [
      "apfs_preparation_started",
      "stub_and_esp_started",
      "recovery_handoff_started",
    ]
    private static let checkpointIdentifiers = [
      "apfs-target-prepared",
      "stub-and-esp-installed",
    ]
    private static let checkpointPhases = [
      "apfs_preparation",
      "stub_and_esp",
    ]

    static func isEligible(
      transcript: Data,
      planDigest: String,
      deviceIdentifier: String,
      storeIdentifier: String,
      checkpointEvidence: [String: Data]
    ) -> Bool {
      guard transcript.last == 0x0A,
        Set(checkpointEvidence.keys) == Set(checkpointIdentifiers)
      else {
        return false
      }
      let lines = transcript.split(separator: 0x0A)
      guard lines.count == 8 else {
        return false
      }
      var records = [[String: Any]]()
      for (index, line) in lines.enumerated() {
        guard
          let record = try? JSONSerialization.jsonObject(
            with: Data(line)
          ) as? [String: Any],
          Set(record.keys)
            == Set([
              "schema_version", "sequence", "type", "payload",
            ]),
          record["schema_version"] as? Int == 1,
          record["sequence"] as? Int == index + 1,
          record["payload"] is [String: Any]
        else {
          return false
        }
        records.append(record)
      }
      guard
        recordType(records[0]) == "inspection",
        payload(records[0])?["device_identifier"] as? String
          == deviceIdentifier,
        payload(records[0])?["support"] as? String == "supported",
        recordType(records[1]) == "inventory",
        payload(records[1])?["system_store_identifier"] as? String
          == storeIdentifier,
        recordType(records[2]) == "plan",
        payload(records[2])?["plan_digest"] as? String == planDigest,
        payload(records[2])?["device_identifier"] as? String
          == deviceIdentifier,
        payload(records[2])?["store_identifier"] as? String
          == storeIdentifier
      else {
        return false
      }

      for index in 0..<eventNames.count {
        let recordIndex = 3 + index * 2
        guard recordType(records[recordIndex]) == "event",
          let event = payload(records[recordIndex]),
          event["plan_digest"] as? String == planDigest,
          event["name"] as? String == eventNames[index]
        else {
          return false
        }
        if index == checkpointIdentifiers.count {
          continue
        }
        let checkpointIndex = recordIndex + 1
        let identifier = checkpointIdentifiers[index]
        guard recordType(records[checkpointIndex]) == "checkpoint",
          let checkpoint = payload(records[checkpointIndex]),
          checkpoint["plan_digest"] as? String == planDigest,
          checkpoint["identifier"] as? String == identifier,
          checkpoint["phase"] as? String == checkpointPhases[index],
          let expectedDigest = checkpoint["evidence_digest"] as? String,
          let evidence = checkpointEvidence[identifier],
          digest(evidence) == expectedDigest
        else {
          return false
        }
      }
      return true
    }

    private static func recordType(_ record: [String: Any]) -> String? {
      record["type"] as? String
    }

    private static func payload(
      _ record: [String: Any]
    ) -> [String: Any]? {
      record["payload"] as? [String: Any]
    }

    private static func digest(_ data: Data) -> String {
      "sha256:"
        + SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
    }
  }
#endif
