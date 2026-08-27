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
  private let snapshot = InstallerWorkflow().referenceM1ProPreview()
  @State private var selectedStepID = "inspect"
  @State private var planPrepared = false

  private var selectedStep: InstallerWorkflowStep {
    snapshot.steps.first { $0.id == selectedStepID } ?? snapshot.steps[0]
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

      Label("SAFE PREVIEW", systemImage: "lock.shield")
        .font(.caption.weight(.bold))
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12), in: Capsule())
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 20)
  }

  private var stepList: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        Text("INSTALLATION PLAN")
          .font(.caption.weight(.bold))
          .foregroundStyle(.secondary)
        Text(snapshot.deviceName)
          .font(.headline)
        Text(snapshot.deviceIdentifier)
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
    VStack(alignment: .leading, spacing: 26) {
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
        VStack(alignment: .leading, spacing: 14) {
          summaryRow("Distribution", snapshot.distributionName)
          summaryRow("Candidate", snapshot.releaseCandidate)
          summaryRow("Execution", snapshot.canMutateSystem ? "Enabled" : "Locked")
          summaryRow("Owner handoff", "One True Recovery required")
        }
        .padding(8)
      } label: {
        Label("Verified plan envelope", systemImage: "checkmark.seal")
          .font(.headline)
      }

      if planPrepared {
        Label(
          "Safe preview prepared. No authorization was requested and no disk, boot policy, or user setting was changed.",
          systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(.green)
        .padding(14)
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
      } else {
        Label(
          "This build demonstrates the complete handoff before privileged execution is connected.",
          systemImage: "info.circle"
        )
        .foregroundStyle(.secondary)
      }

      Spacer()

      HStack {
        Button("Prepare safe preview") {
          planPrepared = true
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

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

  private func summaryRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
        .foregroundStyle(.secondary)
        .frame(width: 105, alignment: .leading)
      Text(value)
        .fontWeight(.medium)
      Spacer()
    }
  }

  private func statusColor(_ status: InstallerWorkflowStepStatus) -> Color {
    switch status {
    case .planned:
      .blue
    case .ownerRequired:
      .orange
    case .locked:
      .secondary
    }
  }
}
