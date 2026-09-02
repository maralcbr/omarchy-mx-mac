import OmarchyInstallerUXCore
import SwiftUI

/// The download screen: one progress bar for everything the installer fetches
/// (real bytes from the signed catalog's pinned sizes, never an estimate),
/// then a hold at "Everything is ready" until the person continues.
struct PreparingScreen: View {
  let update: AssetProgressUpdate
  var isReady = false
  var onContinue: () -> Void = {}
  var onBack: () -> Void = {}

  /// Later stages (engine inspection, planning) report no bytes; keep the
  /// last known totals so the bar stays put instead of resetting.
  @State private var lastBytesCompleted: UInt64 = 0
  @State private var lastTotalBytes: UInt64 = 0
  @State private var lastFileName = ""

  /// The person is installing the OS package; the pinned engine and its
  /// metadata are fetched and verified alongside it but are tooling, so the
  /// bar tracks the package alone.
  private var package: AssetProgressRow? {
    update.rows.first { $0.role == "payload" } ?? update.rows.first
  }

  private static let barHeight: CGFloat = 20

  var body: some View {
    ScreenScaffold(
      headline: isReady ? PlainLanguage.preparedHeadline : PlainLanguage.preparingHeadline,
      subheadline: isReady ? PlainLanguage.preparedSubheadline : PlainLanguage.preparingSubheadline
    ) {
      Panel {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .firstTextBaseline) {
            Text(title)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(isReady ? OmarchyTheme.accent : OmarchyTheme.text)
              .lineLimit(1)
              .truncationMode(.middle)
            Spacer(minLength: 8)
            if let accessory {
              Text(accessory)
                .font(OmarchyTheme.body.monospacedDigit())
                .foregroundStyle(OmarchyTheme.secondaryText)
            }
          }
          ProgressTrack(fraction: fraction, height: Self.barHeight)
            .padding(.top, 10)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
      }
    } actions: {
      if isReady {
        Button(PlainLanguage.planBack, action: onBack)
          .omarchySecondaryButton()
        Button(PlainLanguage.preparedContinue, action: onContinue)
          .omarchyPrimaryButton()
          .keyboardShortcut(.defaultAction)
      } else {
        EmptyView()
      }
    }
    .onChange(of: update, initial: true) { _, _ in
      if let package, package.totalBytes > 0 {
        lastBytesCompleted = package.bytesCompleted
        lastTotalBytes = package.totalBytes
        lastFileName = package.fileName
      }
    }
  }

  private var title: String {
    if isReady {
      return PlainLanguage.downloadVerified
    }
    if update.stage == .downloading {
      return PlainLanguage.downloadingPackagesTitle
    }
    return PlainLanguage.preparingStageTitle(update.stage)
  }

  private var fraction: Double? {
    if isReady {
      return 1
    }
    if update.stage == .downloading, let package, package.totalBytes > 0 {
      return Double(package.bytesCompleted) / Double(package.totalBytes)
    }
    // Between downloading and the plan: hold the last position rather than
    // flipping to an indeterminate sweep.
    guard lastTotalBytes > 0 else {
      return nil
    }
    return Double(lastBytesCompleted) / Double(lastTotalBytes)
  }

  private var accessory: String? {
    let total = (package?.totalBytes ?? 0) > 0 ? package!.totalBytes : lastTotalBytes
    guard total > 0 else {
      return nil
    }
    if isReady {
      return PlainLanguage.bytes(total)
    }
    let completed = (package?.totalBytes ?? 0) > 0 ? package!.bytesCompleted : lastBytesCompleted
    return "\(PlainLanguage.bytes(completed)) of \(PlainLanguage.bytes(total))"
  }
}
