import OmarchyInstallerUXCore
import SwiftUI

/// The download panel: real bytes from the signed catalog's pinned sizes,
/// never an estimate, with a Verified ✓ per artifact once its digest matched.
struct PreparingScreen: View {
  let update: AssetProgressUpdate

  var body: some View {
    ScreenScaffold(
      headline: PlainLanguage.preparingHeadline,
      subheadline: PlainLanguage.preparingSubheadline
    ) {
      Panel {
        PanelHeader(
          title: PlainLanguage.preparingStageTitle(update.stage),
          accessory: aggregateAccessory
        )
        ProgressTrack(fraction: aggregateFraction, height: 13.5)
      }

      if !update.rows.isEmpty {
        Panel {
          PanelHeader(title: PlainLanguage.downloadingTitle)
          VStack(alignment: .leading, spacing: 9) {
            ForEach(update.rows) { row in
              artifactRow(row)
            }
          }
        }
      }
    } actions: {
      EmptyView()
    }
  }

  private var aggregateFraction: Double? {
    guard update.isDeterminate else {
      return nil
    }
    return Double(update.bytesCompleted) / Double(max(1, update.totalBytes))
  }

  private var aggregateAccessory: String? {
    guard update.totalBytes > 0 else {
      return nil
    }
    if update.rows.allSatisfy(\.isVerified) {
      return PlainLanguage.downloadVerified
    }
    return
      "\(PlainLanguage.bytes(update.bytesCompleted)) of \(PlainLanguage.bytes(update.totalBytes))"
  }

  private func artifactRow(_ row: AssetProgressRow) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(row.fileName)
          .font(OmarchyTheme.body)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer(minLength: 8)
        Text(rowAccessory(row))
          .font(OmarchyTheme.caption.monospacedDigit())
          .foregroundStyle(
            row.isVerified ? OmarchyTheme.accent : OmarchyTheme.secondaryText
          )
      }
      ProgressTrack(
        fraction: row.phase == .assembling ? nil : row.fraction,
        height: 13.5
      )
    }
  }

  private func rowAccessory(_ row: AssetProgressRow) -> String {
    switch row.phase {
    case .verified:
      return PlainLanguage.downloadVerified
    case .assembling:
      return "Assembling…"
    case .downloading:
      let part =
        row.partCount.map { count in
          " · part \((row.partIndex ?? 0) + 1) of \(count)"
        } ?? ""
      return
        "\(PlainLanguage.bytes(row.bytesCompleted)) of \(PlainLanguage.bytes(row.totalBytes))\(part)"
    }
  }
}
