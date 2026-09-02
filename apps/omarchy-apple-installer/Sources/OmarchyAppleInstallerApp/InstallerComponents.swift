import AppKit
import OmarchyInstallerUXCore
import SwiftUI

// MARK: - Chrome

struct InstallerRail: View {
  let current: InstallerRailStep
  let completed: Set<InstallerRailStep>
  let blocked: Bool
  /// Completed steps are clickable so the person can walk back through the
  /// flow; the current and future steps are not.
  var onSelect: (InstallerRailStep) -> Void = { _ in }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      AppMark(size: 156)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 6)
        .padding(.bottom, 22)
      ForEach(InstallerRailStep.allCases) { step in
        railRow(step)
      }
      Spacer(minLength: 12)
    }
    .padding(8)
    .frame(width: OmarchyTheme.railWidth, alignment: .leading)
    .background(OmarchyTheme.sidebar)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Install steps")
  }

  private func railRow(_ step: InstallerRailStep) -> some View {
    let isCurrent = step == current
    let isDone = completed.contains(step)
    return Button {
      if isDone {
        onSelect(step)
      }
    } label: {
      railRowLabel(step, isCurrent: isCurrent, isDone: isDone)
    }
    .buttonStyle(.plain)
    .focusable(false)
    .focusEffectDisabled()
    .disabled(!isDone && !isCurrent)
    .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
  }

  private func railRowLabel(_ step: InstallerRailStep, isCurrent: Bool, isDone: Bool) -> some View {
    HStack(spacing: 11) {
      ZStack {
        Circle()
          .fill(
            isCurrent || isDone ? OmarchyTheme.accent : OmarchyTheme.track
          )
          .frame(width: 27, height: 27)
        Text("\(step.number)")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(
            isCurrent || isDone ? OmarchyTheme.accentText : OmarchyTheme.secondaryText
          )
      }
      Text(step.title)
        .font(.system(size: 19.5, weight: isCurrent ? .semibold : .regular))
        .foregroundStyle(
          isDone ? OmarchyTheme.secondaryText : OmarchyTheme.text
        )
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(isCurrent ? OmarchyTheme.accentSoft : Color.clear)
    )
    .contentShape(RoundedRectangle(cornerRadius: 10))
    .accessibilityElement(children: .combine)
  }
}

struct AppMark: View {
  var size: CGFloat = 56

  var body: some View {
    Group {
      if let image = Self.image {
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .padding(size * 0.06)
      } else {
        Text("OM")
          .font(.system(size: size * 0.3, weight: .black))
          .foregroundStyle(OmarchyTheme.accent)
      }
    }
    .frame(width: size, height: size)
    .accessibilityLabel("Omarchy")
  }

  /// The authoritative Omarchy asset, loaded from wherever this build keeps
  /// it: the SwiftPM resource bundle when running from `.build`, or
  /// `Contents/Resources` in the packaged app, where `build-app.sh` installs
  /// the digest-checked source file. The lettermark below is only ever drawn
  /// if neither exists.
  ///
  /// `Bundle.module` is deliberately not used: its generated accessor calls
  /// `fatalError` when the bundle is missing, which is exactly the packaged
  /// app. This search covers the same locations without trapping.
  private static let image: NSImage? = {
    for url in resourceURLs() {
      if let image = NSImage(contentsOf: url) {
        return image
      }
    }
    return nil
  }()

  private static func resourceURLs() -> [URL] {
    let bundleName = "OmarchyAppleInstallerTrustCore_OmarchyAppleInstallerApp"
    var roots = [URL]()
    if let resourceURL = Bundle.main.resourceURL {
      roots.append(resourceURL)
    }
    roots.append(Bundle.main.bundleURL)
    if let executable = Bundle.main.executableURL {
      roots.append(executable.deletingLastPathComponent())
    }

    var urls = [URL]()
    for root in roots {
      let bundleURL = root.appendingPathComponent("\(bundleName).bundle")
      if let bundle = Bundle(url: bundleURL),
        let url = bundle.url(forResource: "omarchy-icon", withExtension: "png")
      {
        urls.append(url)
      }
    }
    if let url = Bundle.main.url(
      forResource: "omarchy-icon",
      withExtension: "png"
    ) {
      urls.append(url)
    }
    return urls
  }
}

// MARK: - Building blocks

struct Panel<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      content
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 13)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: OmarchyTheme.cardRadius)
        .fill(OmarchyTheme.card)
    )
    .overlay(
      RoundedRectangle(cornerRadius: OmarchyTheme.cardRadius)
        .strokeBorder(OmarchyTheme.separator, lineWidth: 1)
    )
  }
}

struct PanelHeader: View {
  let title: String
  var accessory: String?

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .font(OmarchyTheme.panelTitle)
        .foregroundStyle(OmarchyTheme.secondaryText)
      Spacer(minLength: 8)
      if let accessory {
        Text(accessory)
          .font(OmarchyTheme.panelTitle.monospacedDigit())
          .foregroundStyle(OmarchyTheme.accent)
      }
    }
  }
}

/// The ⓘ affordance: a hover/focus tooltip that keeps a dense fact one
/// gesture away without putting it on the screen.
struct InfoTip: View {
  let text: String
  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      Image(systemName: "info.circle")
        .font(.system(size: 11))
        .foregroundStyle(OmarchyTheme.secondaryText)
    }
    .buttonStyle(.plain)
    .help(text)
    .popover(isPresented: $isPresented, arrowEdge: .top) {
      Text(text)
        .font(OmarchyTheme.caption)
        .foregroundStyle(OmarchyTheme.secondaryText)
        .frame(width: 230, alignment: .leading)
        .padding(11)
    }
    .accessibilityLabel("More information")
    .accessibilityHint(text)
  }
}

/// The Details panel: everything dense lives behind one of these.
struct DetailsPanel<Content: View>: View {
  let title: String
  var initiallyExpanded = false
  @ViewBuilder var content: Content

  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation(.easeInOut(duration: 0.12)) { isExpanded.toggle() }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(OmarchyTheme.accent)
          Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(OmarchyTheme.secondaryText)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if isExpanded {
        Divider().overlay(OmarchyTheme.separator)
        VStack(alignment: .leading, spacing: 8) {
          content
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .background(
      RoundedRectangle(cornerRadius: OmarchyTheme.cardRadius)
        .fill(OmarchyTheme.card)
    )
    .overlay(
      RoundedRectangle(cornerRadius: OmarchyTheme.cardRadius)
        .strokeBorder(OmarchyTheme.separator, lineWidth: 1)
    )
    .onAppear { isExpanded = initiallyExpanded }
  }
}

struct FactGrid: View {
  let rows: [PlanFactRow]
  var labelWidth: CGFloat = 118
  var showsCheckmarks = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(rows) { row in
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(row.label)
            .font(OmarchyTheme.body)
            .foregroundStyle(OmarchyTheme.secondaryText)
            .frame(width: labelWidth, alignment: .leading)
          if showsCheckmarks {
            Image(systemName: "checkmark")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(OmarchyTheme.accent)
          }
          Text(row.value)
            .font(row.isMonospaced ? OmarchyTheme.monospaceSmall : OmarchyTheme.body)
            .foregroundStyle(OmarchyTheme.text)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
        }
      }
    }
  }
}

struct PreflightGrid: View {
  let checks: [PreflightCheck]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(checks) { check in
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(check.label)
            .font(OmarchyTheme.body)
            .foregroundStyle(OmarchyTheme.secondaryText)
            .frame(width: 118, alignment: .leading)
          Image(
            systemName: check.satisfied
              ? "checkmark" : "exclamationmark.triangle.fill"
          )
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(
            check.satisfied ? OmarchyTheme.accent : OmarchyTheme.caution
          )
          Text(check.value)
            .font(OmarchyTheme.body)
            .foregroundStyle(OmarchyTheme.text)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          InfoTip(text: check.tooltip)
        }
      }
    }
  }
}

struct StatusBadge: View {
  enum Kind { case ok, blocked }

  let text: String
  let kind: Kind

  var body: some View {
    Text(text)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(
        kind == .ok ? OmarchyTheme.accentText : Color.white
      )
      .padding(.horizontal, 12)
      .padding(.vertical, 4)
      .background(
        Capsule().fill(
          kind == .ok ? OmarchyTheme.accent : OmarchyTheme.danger
        )
      )
  }
}

struct DeviceRow: View {
  let name: String
  let meta: String
  let badge: StatusBadge

  var body: some View {
    HStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 6) {
        Text(name)
          .font(.system(size: 14, weight: .semibold))
        Text(meta)
          .font(.system(size: 11.5))
          .foregroundStyle(OmarchyTheme.secondaryText)
      }
      Spacer(minLength: 8)
      badge
        .padding(.trailing, 12)
    }
  }
}

struct DiskBar: View {
  let macOSBytes: UInt64
  let omarchyBytes: UInt64
  /// When set, the divider between the segments is draggable and reports the
  /// Omarchy share of the disk (0...1) as it moves.
  var onAdjustOmarchyFraction: ((Double) -> Void)?
  /// Called once when the drag ends, with the final Omarchy share.
  var onCommitOmarchyFraction: ((Double) -> Void)?
  /// While set, the divider is drawn but drags are ignored (a re-plan is in
  /// flight). Keeping the handle on screen avoids it flashing off and on.
  var isFrozen = false

  var body: some View {
    GeometryReader { geometry in
      let total = max(1, Double(macOSBytes + omarchyBytes))
      let width = geometry.size.width
      let omarchyWidth = width * Double(omarchyBytes) / total
      ZStack(alignment: .leading) {
        HStack(spacing: 0) {
          segment(
            name: "MacOS",
            bytes: macOSBytes,
            width: width - omarchyWidth,
            background: OmarchyTheme.track,
            foreground: OmarchyTheme.secondaryText
          )
          segment(
            name: "Omarchy",
            bytes: omarchyBytes,
            width: omarchyWidth,
            background: OmarchyTheme.accent,
            foreground: OmarchyTheme.accentText
          )
        }
        if onAdjustOmarchyFraction != nil {
          RoundedRectangle(cornerRadius: 3)
            .fill(Color.white)
            .frame(width: 6, height: 18)
            .overlay(
              RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.black.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 1.5)
            .offset(x: min(max(4, width - omarchyWidth - 3), width - 10))
        }
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            guard !isFrozen else { return }
            let x = min(max(0, value.location.x), width)
            onAdjustOmarchyFraction?(1 - x / max(1, width))
          }
          .onEnded { value in
            guard !isFrozen else { return }
            let x = min(max(0, value.location.x), width)
            onCommitOmarchyFraction?(1 - x / max(1, width))
          },
        including: onAdjustOmarchyFraction == nil ? .none : .all
      )
    }
    .frame(height: 24)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .accessibilityElement(children: .combine)
  }

  private func segment(
    name: String,
    bytes: UInt64,
    width: CGFloat,
    background: Color,
    foreground: Color
  ) -> some View {
    ZStack {
      background
      // Just the amount of space; the colour says which side is which.
      Text(PlainLanguage.bytes(bytes))
        .accessibilityLabel(name + " " + PlainLanguage.bytes(bytes))
      .font(.system(size: 10.5, weight: .semibold))
      .foregroundStyle(foreground)
      .lineLimit(1)
      .padding(.horizontal, 4)
    }
    .frame(width: max(0, width))
  }
}

struct ProgressTrack: View {
  let fraction: Double?
  var height: CGFloat = 6

  @State private var sweep = false

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule().fill(OmarchyTheme.track)
        if let fraction {
          Capsule()
            .fill(OmarchyTheme.accent)
            .frame(width: geometry.size.width * min(1, max(0, fraction)))
            .animation(.linear(duration: 0.18), value: fraction)
        } else {
          Capsule()
            .fill(OmarchyTheme.accent.opacity(0.75))
            .frame(width: geometry.size.width * 0.32)
            .offset(x: sweep ? geometry.size.width * 0.68 : 0)
            .animation(
              .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
              value: sweep
            )
            .onAppear { sweep = true }
        }
      }
    }
    .frame(height: height)
  }
}

struct SegmentedProgress: View {
  let fractions: [Double]
  let activeIndex: Int
  let labels: [String]
  let isRunning: Bool
  var predictedActiveFraction: Double = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 2) {
        ForEach(Array(fractions.enumerated()), id: \.offset) { index, fraction in
          ProgressTrack(
            fraction: fraction >= 1
              ? 1
              : (index == activeIndex && isRunning
                ? min(0.92, max(0, predictedActiveFraction)) : 0),
            height: 12
          )
        }
      }
      HStack(spacing: 2) {
        ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
          Text(label)
            .font(.system(size: 10.5, weight: index == activeIndex ? .semibold : .regular))
            .foregroundStyle(
              index == activeIndex ? OmarchyTheme.accent : OmarchyTheme.secondaryText
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }
}

struct RecoveryStepRow: View {
  let step: RecoveryStep

  var body: some View {
    HStack(alignment: .top, spacing: 13) {
      Text("\(step.number)")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(OmarchyTheme.accentText)
        .frame(width: 24, height: 24)
        .background(Circle().fill(OmarchyTheme.accent))
      VStack(alignment: .leading, spacing: 2) {
        Text(step.title)
          .font(.system(size: 13, weight: .semibold))
        Text(step.detail)
          .font(OmarchyTheme.body)
          .foregroundStyle(OmarchyTheme.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: OmarchyTheme.cardRadius)
        .fill(OmarchyTheme.card)
    )
    .overlay(
      RoundedRectangle(cornerRadius: OmarchyTheme.cardRadius)
        .strokeBorder(OmarchyTheme.separator, lineWidth: 1)
    )
  }
}

/// One screen: headline, one sentence, content, then a single action row
/// pinned to the window's bottom-right corner.
struct ScreenScaffold<Content: View, Actions: View>: View {
  let headline: String
  var headlineIsError = false
  let subheadline: String?
  var hint: String?
  @ViewBuilder var content: Content
  @ViewBuilder var actions: Actions

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 0) {
        Text(headline)
          .font(OmarchyTheme.headline)
          .foregroundStyle(headlineIsError ? OmarchyTheme.danger : OmarchyTheme.text)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.bottom, 6)
        if let subheadline {
          Text(subheadline)
            .font(OmarchyTheme.subheadline)
            .foregroundStyle(OmarchyTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 20)
        }
        VStack(alignment: .leading, spacing: 14) {
          content
        }
        Spacer(minLength: 16)
      }
      .frame(maxWidth: OmarchyTheme.contentMaxWidth, alignment: .leading)
      HStack(spacing: 16) {
        if let hint {
          Text(hint)
            .font(OmarchyTheme.caption)
            .foregroundStyle(OmarchyTheme.secondaryText)
        }
        Spacer(minLength: 0)
        actions
      }
      .padding(.top, 16)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(OmarchyTheme.contentPadding)
  }
}

/// Rectangular action buttons with rounded corners — the system's large
/// bordered styles render as capsules, which the approved look rejects.
struct OmarchyPrimaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .medium))
      .foregroundStyle(OmarchyTheme.accentText)
      .padding(.horizontal, 21)
      .frame(height: 42)
      .background(
        RoundedRectangle(cornerRadius: 9)
          .fill(OmarchyTheme.accent)
      )
      .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
  }
}

struct OmarchySecondaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15))
      .foregroundStyle(OmarchyTheme.text)
      .padding(.horizontal, 21)
      .frame(height: 42)
      .background(
        RoundedRectangle(cornerRadius: 9)
          .fill(OmarchyTheme.card)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 9)
          .strokeBorder(OmarchyTheme.separator, lineWidth: 1)
      )
      .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
  }
}

extension View {
  func omarchyPrimaryButton() -> some View {
    buttonStyle(OmarchyPrimaryButtonStyle())
  }

  func omarchySecondaryButton() -> some View {
    buttonStyle(OmarchySecondaryButtonStyle())
  }
}
