#if os(macOS)
  import Darwin
  import Foundation

  public enum InstallConfESPError: Error, Equatable, Sendable {
    case invalidStoreIdentifier
    case notFound
    case ambiguous
    case mountFailed
    case writeFailed
    case readbackMismatch
    case unmountFailed
  }

  public enum InstallConfHandoff: Equatable, Sendable {
    case recorded
    case notRecorded
  }

  /// One GPT row considered when locating the ESP the engine just created.
  public struct InstallConfESPPartition: Equatable, Sendable {
    public let identifier: String
    public let storeIdentifier: String
    public let type: String
    public let name: String
    public let offsetBytes: UInt64
    public let lengthBytes: UInt64

    public init(
      identifier: String,
      storeIdentifier: String,
      type: String,
      name: String,
      offsetBytes: UInt64,
      lengthBytes: UInt64
    ) {
      self.identifier = identifier
      self.storeIdentifier = storeIdentifier
      self.type = type
      self.name = name
      self.offsetBytes = offsetBytes
      self.lengthBytes = lengthBytes
    }
  }

  public struct InstallConfESPIdentity: Equatable, Sendable {
    public let partitionIdentifier: String
    public let storeIdentifier: String

    public init(partitionIdentifier: String, storeIdentifier: String) {
      self.partitionIdentifier = partitionIdentifier
      self.storeIdentifier = storeIdentifier
    }
  }

  /// Picks the new Omarchy ESP from the engine plan's store and extent.
  ///
  /// The engine allocates `[offset, offset+length)` on `storeIdentifier` and
  /// creates the stub APFS, then `EFI - OMARC`, then the Linux boot and root
  /// partitions. Exactly one EFI volume named `EFI - OMARC` inside that extent
  /// is the handover target.
  public enum InstallConfESPLocator {
    public static let volumeName = "EFI - OMARC"
    private static let efiTypes: Set<String> = ["EFI", "EFI System Partition"]
    private static let storePattern = #"^disk[0-9]+$"#
    private static let partitionPattern = #"^disk[0-9]+s[0-9]+$"#

    public static func identify(
      storeIdentifier: String,
      offsetBytes: UInt64,
      lengthBytes: UInt64,
      partitions: [InstallConfESPPartition]
    ) throws -> InstallConfESPIdentity {
      guard storeIdentifier.range(of: storePattern, options: .regularExpression) != nil
      else {
        throw InstallConfESPError.invalidStoreIdentifier
      }
      guard lengthBytes > 0,
        offsetBytes.addingReportingOverflow(lengthBytes).overflow == false
      else {
        throw InstallConfESPError.notFound
      }
      let end = offsetBytes + lengthBytes
      let matches = partitions.filter { partition in
        partition.storeIdentifier == storeIdentifier
          && Self.efiTypes.contains(partition.type)
          && partition.name == volumeName
          && partition.lengthBytes > 0
          && partition.offsetBytes >= offsetBytes
          && partition.offsetBytes < end
          && partition.identifier.range(
            of: partitionPattern, options: .regularExpression) != nil
          && partition.identifier.hasPrefix(storeIdentifier)
      }
      guard matches.count == 1, let match = matches.first else {
        throw matches.isEmpty
          ? InstallConfESPError.notFound : InstallConfESPError.ambiguous
      }
      return InstallConfESPIdentity(
        partitionIdentifier: match.identifier,
        storeIdentifier: storeIdentifier
      )
    }
  }

  public protocol InstallConfESPHelping: Sendable {
    func write(
      _ conf: InstallConf,
      storeIdentifier: String,
      offsetBytes: UInt64,
      lengthBytes: UInt64
    ) async throws
  }

  /// App-side recorder: any helper failure becomes the default-on summary,
  /// never an install failure.
  public struct InstallConfESPWriter: Sendable {
    private let helper: any InstallConfESPHelping

    public init(helper: any InstallConfESPHelping) {
      self.helper = helper
    }

    public func record(
      _ conf: InstallConf,
      storeIdentifier: String,
      offsetBytes: UInt64,
      lengthBytes: UInt64
    ) async -> InstallConfHandoff {
      do {
        try await helper.write(
          conf,
          storeIdentifier: storeIdentifier,
          offsetBytes: offsetBytes,
          lengthBytes: lengthBytes
        )
        return .recorded
      } catch {
        return .notRecorded
      }
    }
  }

  public struct AuthorizedInstallConfESPHelper: InstallConfESPHelping {
    public let submitter: AuthenticatedEngineXPCSubmitter
    public let authorization: MachineOwnerAuthorization

    public init(
      submitter: AuthenticatedEngineXPCSubmitter,
      authorization: MachineOwnerAuthorization
    ) {
      self.submitter = submitter
      self.authorization = authorization
    }

    public func write(
      _ conf: InstallConf,
      storeIdentifier: String,
      offsetBytes: UInt64,
      lengthBytes: UInt64
    ) async throws {
      try await submitter.writeInstallConf(
        conf,
        storeIdentifier: storeIdentifier,
        offsetBytes: offsetBytes,
        lengthBytes: lengthBytes,
        authorization: authorization
      )
    }
  }

  protocol InstallConfESPDiskOperating: Sendable {
    func partitions(on storeIdentifier: String) throws -> [InstallConfESPPartition]
    func mount(_ identifier: String, at mountPoint: URL) throws
    func unmount(_ identifier: String) throws
  }

  /// Privileged writer used by the helper: mount the identified ESP read-write
  /// at a private mount point, write atomically, read back, unmount.
  struct InstallConfESPMountWriter: @unchecked Sendable {
    private let disks: any InstallConfESPDiskOperating
    private let workingDirectory: URL
    private let fileManager: FileManager
    private let contentsOf: @Sendable (URL) throws -> Data

    init(
      disks: any InstallConfESPDiskOperating,
      workingDirectory: URL,
      fileManager: FileManager = .default,
      contentsOf: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) {
      self.disks = disks
      self.workingDirectory = workingDirectory
      self.fileManager = fileManager
      self.contentsOf = contentsOf
    }

    func write(
      _ conf: InstallConf,
      storeIdentifier: String,
      offsetBytes: UInt64,
      lengthBytes: UInt64
    ) throws {
      let identity = try InstallConfESPLocator.identify(
        storeIdentifier: storeIdentifier,
        offsetBytes: offsetBytes,
        lengthBytes: lengthBytes,
        partitions: try disks.partitions(on: storeIdentifier)
      )
      let mountPoint = workingDirectory.appendingPathComponent(
        "esp-handoff",
        isDirectory: true
      )
      try prepareMountPoint(mountPoint)
      do {
        try disks.mount(identity.partitionIdentifier, at: mountPoint)
      } catch {
        throw InstallConfESPError.mountFailed
      }
      var mounted = true
      defer {
        if mounted {
          try? disks.unmount(identity.partitionIdentifier)
        }
      }
      try writeAtomically(conf, on: mountPoint)
      let readback =
        mountPoint
        .appendingPathComponent(InstallConf.directoryName, isDirectory: true)
        .appendingPathComponent(InstallConf.fileName)
      let observed: Data
      do {
        observed = try contentsOf(readback)
      } catch {
        throw InstallConfESPError.readbackMismatch
      }
      guard let parsed = try? InstallConf.parse(observed), parsed == conf,
        observed == conf.serializedData
      else {
        throw InstallConfESPError.readbackMismatch
      }
      do {
        try disks.unmount(identity.partitionIdentifier)
        mounted = false
      } catch {
        throw InstallConfESPError.unmountFailed
      }
    }

    private func prepareMountPoint(_ mountPoint: URL) throws {
      if fileManager.fileExists(atPath: mountPoint.path) {
        try? fileManager.removeItem(at: mountPoint)
      }
      try fileManager.createDirectory(
        at: mountPoint,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
    }

    private func writeAtomically(_ conf: InstallConf, on mountPoint: URL) throws {
      let directory = mountPoint.appendingPathComponent(
        InstallConf.directoryName,
        isDirectory: true
      )
      do {
        try fileManager.createDirectory(
          at: directory,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o755]
        )
        let destination = directory.appendingPathComponent(InstallConf.fileName)
        let temporary = directory.appendingPathComponent(
          ".\(InstallConf.fileName).tmp"
        )
        if fileManager.fileExists(atPath: temporary.path) {
          try fileManager.removeItem(at: temporary)
        }
        try conf.serializedData.write(to: temporary, options: .withoutOverwriting)
        try fileManager.setAttributes(
          [.posixPermissions: 0o644],
          ofItemAtPath: temporary.path
        )
        let handle = try FileHandle(forWritingTo: temporary)
        try handle.synchronize()
        try handle.close()
        if fileManager.fileExists(atPath: destination.path) {
          try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporary, to: destination)
      } catch let error as InstallConfESPError {
        throw error
      } catch {
        throw InstallConfESPError.writeFailed
      }
    }
  }

  struct DiskutilInstallConfESPOperator: InstallConfESPDiskOperating {
    var commands: @Sendable ([String]) throws -> Data = Self.systemRun

    func partitions(on storeIdentifier: String) throws -> [InstallConfESPPartition] {
      let listing = try plist(["list", "-plist", storeIdentifier])
      guard let disks = listing["AllDisksAndPartitions"] as? [[String: Any]],
        let entry = disks.first(where: {
          $0["DeviceIdentifier"] as? String == storeIdentifier
        }),
        let records = entry["Partitions"] as? [[String: Any]]
      else {
        throw InstallConfESPError.notFound
      }
      return try records.compactMap { item -> InstallConfESPPartition? in
        guard let identifier = item["DeviceIdentifier"] as? String else {
          return nil
        }
        let info = try plist(["info", "-plist", identifier])
        guard info["ParentWholeDisk"] as? String == storeIdentifier else {
          return nil
        }
        let offset = (info["PartitionMapPartitionOffset"] as? NSNumber)?.uint64Value ?? 0
        let size = (info["Size"] as? NSNumber)?.uint64Value ?? 0
        return InstallConfESPPartition(
          identifier: identifier,
          storeIdentifier: storeIdentifier,
          type: info["Content"] as? String ?? "",
          name: info["VolumeName"] as? String ?? "",
          offsetBytes: offset,
          lengthBytes: size
        )
      }
    }

    func mount(_ identifier: String, at mountPoint: URL) throws {
      _ = try run(["mount", "-mountPoint", mountPoint.path, identifier])
    }

    func unmount(_ identifier: String) throws {
      _ = try run(["unmount", identifier])
    }

    private func plist(_ arguments: [String]) throws -> [String: Any] {
      guard
        let value = try PropertyListSerialization.propertyList(from: run(arguments), format: nil)
          as? [String: Any]
      else {
        throw InstallConfESPError.notFound
      }
      return value
    }

    private func run(_ arguments: [String]) throws -> Data {
      try commands(arguments)
    }

    private static func systemRun(_ arguments: [String]) throws -> Data {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
      process.arguments = arguments
      process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      process.standardInput = FileHandle.nullDevice
      try process.run()
      let result = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationReason == .exit, process.terminationStatus == 0 else {
        throw InstallConfESPError.mountFailed
      }
      return result
    }
  }
#endif
