import OmarchyAppleInstallerTrustCore
import SwiftUI

@main
struct OmarchyAppleInstallerApp: App {
  var body: some Scene {
    WindowGroup("Omarchy MX Mac Installer") {
      InstallerRootView()
        .frame(minWidth: 960, minHeight: 640)
    }
    .defaultSize(width: 1080, height: 720)
  }
}

private struct InstallerRootView: View {
  private let workflow = InstallerWorkflow()
  @State private var selectedStepID = "inspect"
  @State private var planPrepared = false
  @State private var hostInspection: AppleSiliconHostInspection?
  @State private var inspectionError: String?
  @State private var isInspecting = true

  private var snapshot: InstallerWorkflowSnapshot {
    if let hostInspection {
      workflow.preview(for: hostInspection)
    } else {
      workflow.referenceM1ProPreview()
    }
  }

  private var selectedStep: InstallerWorkflowStep {
    snapshot.steps.first { $0.id == selectedStepID } ?? snapshot.steps[0]
  }

  private var installationBlocked: Bool {
    snapshot.blockedReason != nil
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      HStack(spacing: 0) {
        stepList
        Divider()
        detail
      }
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .task {
      await inspectThisMac()
    }
  }

  private var header: some View {
    HStack(spacing: 18) {
      ZStack {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .fill(Color.accentColor.gradient)
          .frame(width: 58, height: 58)
        Image(systemName: "laptopcomputer.and.arrow.down")
          .font(.system(size: 26, weight: .semibold))
          .foregroundStyle(.white)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text("Omarchy MX Mac Installer")
          .font(.system(size: 25, weight: .semibold))
        Text("Prepare Apple Silicon for a verified Omarchy installation")
          .foregroundStyle(.secondary)
      }

      Spacer()

      Label(
        installationBlocked ? "INSTALLATION LOCKED" : "SAFE PREVIEW",
        systemImage: installationBlocked ? "xmark.shield" : "lock.shield"
      )
      .font(.caption.weight(.bold))
      .foregroundStyle(installationBlocked ? .red : .orange)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        (installationBlocked ? Color.red : Color.orange).opacity(0.12),
        in: Capsule()
      )
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 20)
  }

  private var stepList: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        Text("THIS MAC")
          .font(.caption.weight(.bold))
          .foregroundStyle(.secondary)
        Text(isInspecting ? "Inspecting…" : snapshot.deviceName)
          .font(.headline)
        Text(isInspecting ? "read-only preflight" : snapshot.deviceIdentifier)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }
      .padding(22)

      ScrollView {
        VStack(spacing: 6) {
          ForEach(Array(snapshot.steps.enumerated()), id: \.element.id) { index, step in
            Button {
              selectedStepID = step.id
            } label: {
              stepRow(number: index + 1, step: step)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 12)
      }

      Spacer(minLength: 12)

      HStack(spacing: 8) {
        Image(systemName: "externaldrive.badge.xmark")
        Text("Disk mutation disabled")
      }
      .font(.caption.weight(.medium))
      .foregroundStyle(.secondary)
      .padding(20)
    }
    .frame(width: 350)
    .background(Color.secondary.opacity(0.045))
  }

  private func stepRow(
    number: Int,
    step: InstallerWorkflowStep
  ) -> some View {
    HStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(selectedStepID == step.id ? Color.accentColor : Color.secondary.opacity(0.13))
          .frame(width: 30, height: 30)
        Text(String(number))
          .font(.caption.weight(.bold))
          .foregroundStyle(selectedStepID == step.id ? .white : .secondary)
      }

      VStack(alignment: .leading, spacing: 3) {
        Text(step.title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
        Text(step.status.label)
          .font(.caption)
          .foregroundStyle(statusColor(step.status))
      }

      Spacer()
      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
      selectedStepID == step.id ? Color.accentColor.opacity(0.1) : .clear,
      in: RoundedRectangle(cornerRadius: 10, style: .continuous)
    )
    .contentShape(Rectangle())
  }

  private var detail: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack(alignment: .top, spacing: 18) {
        Image(systemName: selectedStep.systemImage)
          .font(.system(size: 32, weight: .medium))
          .foregroundStyle(Color.accentColor)
          .frame(width: 58, height: 58)
          .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))

        VStack(alignment: .leading, spacing: 7) {
          Text(selectedStep.title)
            .font(.system(size: 28, weight: .semibold))
          Text(selectedStep.detail)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          summaryRow("Model", hostInspection?.identity.model ?? "Pending")
          summaryRow("macOS", hostInspection?.macOSVersion ?? "Pending")
          summaryRow("Power", hostInspection?.powerSource.rawValue ?? "Pending")
          summaryRow("FileVault", fileVaultStatus)
          summaryRow("APFS free", freeSpaceStatus)
          summaryRow("Downloads", downloadStatus)
        }
        .padding(8)
      } label: {
        Label("Read-only preflight", systemImage: "checkmark.seal")
          .font(.headline)
      }

      if let reason = snapshot.blockedReason {
        statusMessage(
          reason,
          systemImage: "xmark.octagon.fill",
          color: .red
        )
      } else if let inspectionError {
        statusMessage(
          inspectionError,
          systemImage: "exclamationmark.triangle.fill",
          color: .red
        )
      } else if planPrepared {
        statusMessage(
          "Safe preview prepared. No authorization was requested and no disk, boot policy, or user setting was changed.",
          systemImage: "checkmark.circle.fill",
          color: .green
        )
      } else {
        Label(
          "Host inspection is live. Verified downloads remain locked until a production-signed model catalog is available.",
          systemImage: "info.circle"
        )
        .foregroundStyle(.secondary)
      }

      Spacer()

      HStack {
        Button(isInspecting ? "Inspecting…" : "Inspect this Mac") {
          Task { await inspectThisMac() }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isInspecting)

        Button("Prepare safe preview") {
          planPrepared = true
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isInspecting || hostInspection == nil)

        Button("Start installation") {}
          .buttonStyle(.bordered)
          .controlSize(.large)
          .disabled(true)

        Spacer()

        Text("Live engine disconnected")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }
    }
    .padding(34)
  }

  private var fileVaultStatus: String {
    guard let hostInspection else {
      return "Pending"
    }
    return hostInspection.fileVaultEnabled ? "On" : "Off"
  }

  private var freeSpaceStatus: String {
    guard let storage = hostInspection?.storage else {
      return "Pending"
    }
    return ByteCountFormatter.string(
      fromByteCount: Int64(storage.containerFreeBytes),
      countStyle: .file
    )
  }

  private var downloadStatus: String {
    if installationBlocked {
      return "Blocked for this model"
    }
    return "Awaiting signed catalog"
  }

  private func summaryRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
        .foregroundStyle(.secondary)
        .frame(width: 92, alignment: .leading)
      Text(value)
        .fontWeight(.medium)
      Spacer()
    }
  }

  private func statusMessage(
    _ message: String,
    systemImage: String,
    color: Color
  ) -> some View {
    Label(message, systemImage: systemImage)
      .foregroundStyle(color)
      .padding(14)
      .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
  }

  private func statusColor(_ status: InstallerWorkflowStepStatus) -> Color {
    switch status {
    case .planned:
      .blue
    case .observed:
      .green
    case .ownerRequired:
      .orange
    case .blocked:
      .red
    case .locked:
      .secondary
    }
  }

  @MainActor
  private func inspectThisMac() async {
    isInspecting = true
    planPrepared = false
    do {
      let result = try await Task.detached(priority: .userInitiated) {
        try AppleSiliconHostInspector().inspect()
      }.value
      hostInspection = result
      inspectionError = nil
    } catch {
      hostInspection = nil
      inspectionError = "Read-only inspection failed. Installation remains locked."
    }
    isInspecting = false
  }
}
