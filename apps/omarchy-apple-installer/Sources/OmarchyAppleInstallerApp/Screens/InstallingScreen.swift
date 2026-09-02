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

  private var activeStageLabel: String {
    let index = progress.stageIndex
    if progress.stageLabels.indices.contains(index) {
      return progress.stageLabels[index]
    }
    return progress.phaseTitle
  }

  private var overallFraction: Double? {
    let count = progress.stageFractions.count
    guard count > 0 else {
      return nil
    }
    var fractions = progress.stageFractions
    if fractions.indices.contains(progress.stageIndex) {
      fractions[progress.stageIndex] = max(fractions[progress.stageIndex], predictedActiveFraction)
    }
    let total = fractions.reduce(0) { $0 + min(1, max(0, $1)) }
    return min(1, max(0, total / Double(count)))
  }

  var body: some View {
    ScreenScaffold(
      headline: progress.phaseTitle,
      subheadline: nil
    ) {
      // One bar for the whole installation. Every stage counts equally; the
      // active stage blends in the checkpoint-based prediction so the bar keeps
      // moving between journal events. A degraded stream sweeps instead.
      Panel {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .firstTextBaseline) {
            Text(activeStageLabel)
              .font(.system(size: 14, weight: .semibold))
              .lineLimit(1)
              .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(elapsedText)
              .font(OmarchyTheme.caption.monospacedDigit())
              .foregroundStyle(OmarchyTheme.secondaryText)
            if let overallFraction {
              Text("\(Int((overallFraction * 100).rounded()))%")
                .font(OmarchyTheme.body.monospacedDigit())
                .foregroundStyle(OmarchyTheme.secondaryText)
            }
          }
          ProgressTrack(fraction: progress.degraded ? nil : overallFraction, height: 20)
        }
        .padding(.vertical, 6)
      }
      // A little air between the title and the progress card.
      .padding(.top, 12)
      // No subtitle on this page, so give the title some room to breathe.
      .padding(.top, 14)

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
