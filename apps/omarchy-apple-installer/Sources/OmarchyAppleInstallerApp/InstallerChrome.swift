import OmarchyAppleInstallerTrustCore
import SwiftUI

struct InstallerHeaderView: View {
  let installationBlocked: Bool

  var body: some View {
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
}

struct InstallerStepSidebar: View {
  let snapshot: InstallerWorkflowSnapshot
  let isInspecting: Bool
  @Binding var selectedStepID: String

  var body: some View {
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

  private func statusColor(_ status: InstallerWorkflowStepStatus) -> Color {
    switch status {
    case .planned: .blue
    case .observed: .green
    case .ownerRequired: .orange
    case .blocked: .red
    case .locked: .secondary
    }
  }
}
