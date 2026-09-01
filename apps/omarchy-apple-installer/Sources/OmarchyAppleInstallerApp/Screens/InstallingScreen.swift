import OmarchyInstallerUXCore
import SwiftUI

/// Screen D. The bar advances on real checkpoints streamed from the engine's
/// journal; when the stream degrades the bar becomes indeterminate and says so,
/// but the run is never affected.
struct InstallingScreen: View {
  let progress: InstallProgressDisplay

  @State private var elapsed: TimeInterval = 0
  @State private var stageStartedAt = Date()

  private let ticker = Timer.publish(every: 1, on: .main, in: .common)
    .autoconnect()

  var body: some View {
    ScreenScaffold(
      headline: progress.phaseTitle,
      subheadline: nil
    ) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        InfoTip(text: PlainLanguage.installProgressTooltip)
        Spacer(minLength: 0)
        Text(elapsedText)
          .font(OmarchyTheme.caption.monospacedDigit())
          .foregroundStyle(OmarchyTheme.secondaryText)
      }

      SegmentedProgress(
        fractions: progress.stageFractions,
        activeIndex: progress.stageIndex,
        labels: progress.stageLabels,
        isRunning: !progress.degraded,
        predictedActiveFraction: predictedActiveFraction
      )

      Text(PlainLanguage.installWarning)
        .font(OmarchyTheme.body.weight(.medium))
        .foregroundStyle(OmarchyTheme.caution)
        .padding(.top, 6)

      if progress.degraded {
        Text(PlainLanguage.installDegraded)
          .font(OmarchyTheme.caption)
          .foregroundStyle(OmarchyTheme.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }

      DetailsPanel(
        title: PlainLanguage.installJournalTitle,
        initiallyExpanded: true
      ) {
        if progress.feed.isEmpty {
          Text(PlainLanguage.installVerifyingOwner)
            .font(OmarchyTheme.monospaceSmall)
            .foregroundStyle(OmarchyTheme.secondaryText)
        } else {
          VStack(alignment: .leading, spacing: 3) {
            ForEach(progress.feed) { line in
              Text(line.text)
                .font(OmarchyTheme.monospaceSmall)
                .foregroundStyle(
                  line.kind == .event
                    ? OmarchyTheme.secondaryText : OmarchyTheme.accent
                )
                .lineLimit(1)
                .truncationMode(.middle)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    } actions: {
      EmptyView()
    }
    .onReceive(ticker) { _ in
      elapsed = Date().timeIntervalSince(progress.startedAt)
    }
    .onChange(of: progress.stageIndex) { _, _ in
      stageStartedAt = Date()
    }
  }

  /// Checkpoints only report stage completion, so the active segment shows a
  /// time-based estimate that advances left to right and saturates below full
  /// until the real checkpoint lands.
  private var predictedActiveFraction: Double {
    let stageElapsed = max(0, Date().timeIntervalSince(stageStartedAt))
    return 1 - exp(-stageElapsed / 75)
  }

  private var elapsedText: String {
    let total = Int(max(0, elapsed))
    return String(format: "%02d:%02d", total / 60, total % 60)
  }
}
