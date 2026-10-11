import IslandCore
import SwiftUI

/// The island outline. Attached to a notch it flares into the top edge of the screen;
/// on other displays it floats as a rounded rectangle.
struct IslandShape: Shape {
  var ear: CGFloat
  var radius: CGFloat

  var animatableData: AnimatablePair<CGFloat, CGFloat> {
    get { AnimatablePair(ear, radius) }
    set {
      ear = newValue.first
      radius = newValue.second
    }
  }

  func path(in rect: CGRect) -> Path {
    guard ear > 0 else {
      return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
    }
    let ear = min(ear, rect.width / 4, rect.height / 2)
    let radius = max(0, min(radius, rect.height - ear, (rect.width - 2 * ear) / 2))
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + ear, y: rect.minY + ear),
      control: CGPoint(x: rect.minX + ear, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.minX + ear, y: rect.maxY - radius))
    path.addCurve(
      to: CGPoint(x: rect.minX + ear + radius, y: rect.maxY),
      control1: CGPoint(x: rect.minX + ear, y: rect.maxY - radius * 0.45),
      control2: CGPoint(x: rect.minX + ear + radius * 0.45, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.maxX - ear - radius, y: rect.maxY))
    path.addCurve(
      to: CGPoint(x: rect.maxX - ear, y: rect.maxY - radius),
      control1: CGPoint(x: rect.maxX - ear - radius * 0.45, y: rect.maxY),
      control2: CGPoint(x: rect.maxX - ear, y: rect.maxY - radius * 0.45))
    path.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - ear, y: rect.minY))
    path.closeSubpath()
    return path
  }
}

enum Palette {
  static let open = Color(red: 0.25, green: 0.73, blue: 0.31)
  static let draft = Color(red: 0.55, green: 0.58, blue: 0.62)
  static let merged = Color(red: 0.64, green: 0.44, blue: 0.97)
  static let merging = Color(red: 0.82, green: 0.60, blue: 0.13)
  static let failed = Color(red: 0.97, green: 0.32, blue: 0.29)
  static let attention = Color(red: 0.94, green: 0.62, blue: 0.27)
  static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
  static let surface = Color.white.opacity(0.055)
  static let hairline = Color.white.opacity(0.09)
}

enum Motion {
  /// Shape morphs between compact, banner, and expanded.
  static let morph = Animation.spring(response: 0.42, dampingFraction: 0.82)
  static let snappy = Animation.snappy(duration: 0.24)
}

extension AnyTransition {
  /// Content arrives after the shape has started growing and leaves before it shrinks.
  static var islandContent: AnyTransition {
    .asymmetric(
      insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
        .animation(.smooth(duration: 0.28).delay(0.07)),
      removal: .opacity.animation(.easeOut(duration: 0.1)))
  }
}

extension PRGroup {
  var glyph: Glyph {
    switch self {
    case .needsYou, .open: .pullRequest
    case .merging: .mergeQueue
    case .draft: .draft
    case .merged: .merge
    }
  }

  var color: Color {
    switch self {
    case .needsYou: Palette.attention
    case .open: Palette.open
    case .merging: Palette.merging
    case .draft: Palette.draft
    case .merged: Palette.merged
    }
  }
}

extension PullRequest {
  var glyph: Glyph {
    switch group {
    case .merged: .merge
    case .draft: .draft
    case .merging: .mergeQueue
    case .needsYou, .open: .pullRequest
    case nil: .closed
    }
  }

  var glyphColor: Color {
    switch group {
    case .merged: Palette.merged
    case .draft: Palette.draft
    case .merging: Palette.merging
    case .needsYou, .open: Palette.open
    case nil: Palette.failed
    }
  }
}

extension PRStatus {
  var color: Color {
    switch self {
    case .failed, .conflicts, .changesRequested, .closed: Palette.failed
    case .review, .waiting, .behind, .blocked: Palette.attention
    case .ready: Palette.open
    case .merged: Palette.merged
    case .queued: Palette.merging
    default: .secondary
    }
  }

  /// Event glyph for banners.
  var eventGlyph: Glyph {
    switch self {
    case .merged: .merge
    case .failed: .failFill
    case .review: .eye
    case .queued: .mergeQueue
    default: .pullRequest
    }
  }

  var eventTitle: String {
    switch self {
    case .merged: "Merged"
    case .failed: "Checks failed"
    case .review: "Review requested"
    case .queued: "Merging"
    default: label
    }
  }

  /// Lower shows first when several changes arrive together.
  var bannerPriority: Int {
    switch self {
    case .merged: 0
    case .failed: 1
    case .review: 2
    case .queued: 3
    default: 4
    }
  }
}

extension AgentProvider {
  var glyph: Glyph { self == .codex ? .openai : .claude }
  var tint: Color { self == .codex ? .white : Palette.claude }
}

enum Format {
  static func count(_ value: Int?) -> String {
    guard let value else { return "—" }
    return value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
  }

  static func cost(_ value: Double?) -> String {
    guard let value else { return "—" }
    return value.formatted(.currency(code: "USD").precision(.fractionLength(value < 100 ? 2 : 0)))
  }

  /// A short age such as "now", "4m", "2h", or "3d".
  static func age(_ date: Date, now: Date = Date()) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    switch seconds {
    case ..<60: return "now"
    case ..<3600: return "\(Int(seconds / 60))m"
    case ..<86_400: return "\(Int(seconds / 3600))h"
    default: return "\(Int(seconds / 86_400))d"
    }
  }
}

/// A compact segmented control whose selection slides between options.
struct PillPicker<Value: Hashable>: View {
  let options: [(value: Value, label: String)]
  @Binding var selection: Value
  var fontSize: CGFloat = 12
  @Namespace private var namespace

  var body: some View {
    HStack(spacing: 0) {
      ForEach(options, id: \.value) { option in
        let selected = option.value == selection
        Button {
          withAnimation(Motion.snappy) { selection = option.value }
        } label: {
          Text(option.label)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(selected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 10).padding(.vertical, 4.5)
            .background {
              if selected {
                Capsule().fill(.white.opacity(0.14))
                  .matchedGeometryEffect(id: "selection", in: namespace)
              }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
    .padding(2)
    .background(Capsule().fill(.white.opacity(0.06)))
  }
}

/// Check progress as a segmented ring: passed, failed, then pending.
struct CheckRing: View {
  let summary: CheckSummary
  var size: CGFloat = 13
  var lineWidth: CGFloat = 2

  var body: some View {
    let total = max(1, Double(summary.total))
    let passed = Double(summary.passed) / total
    let failed = Double(summary.failed) / total
    ZStack {
      Circle().stroke(.white.opacity(0.12), lineWidth: lineWidth)
      Circle().trim(from: 0, to: passed)
        .stroke(Palette.open, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
      Circle().trim(from: passed, to: passed + failed)
        .stroke(Palette.failed, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
      Circle().trim(from: passed + failed, to: 1)
        .stroke(Palette.merging, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
    }
    .rotationEffect(.degrees(-90))
    .frame(width: size, height: size)
  }
}

/// CI state for a PR row, as GitHub shows it: a check, a cross, or progress.
struct CheckBadge: View {
  let pr: PullRequest

  var body: some View {
    if let summary = pr.checkSummary {
      HStack(spacing: 5) {
        if summary.failed > 0 {
          Text("\(summary.failed) failed").foregroundStyle(Palette.failed)
        } else if summary.pending > 0 {
          Text("\(summary.passed)/\(summary.total)").foregroundStyle(.secondary)
        }
        if summary.failed == 0 && summary.pending == 0 {
          GlyphView(glyph: .checkFill, size: 13).foregroundStyle(Palette.open)
        } else {
          CheckRing(summary: summary)
        }
      }
      .font(.system(size: 10.5, weight: .medium)).monospacedDigit()
      .help("\(summary.passed) passed · \(summary.failed) failed · \(summary.pending) running")
    } else if let checks = pr.checks {
      switch checks {
      case "SUCCESS": GlyphView(glyph: .checkFill, size: 13).foregroundStyle(Palette.open)
      case "FAILURE", "ERROR": GlyphView(glyph: .failFill, size: 13).foregroundStyle(Palette.failed)
      default: Circle().fill(Palette.merging).frame(width: 7, height: 7).frame(width: 13)
      }
    }
  }
}

/// A softly breathing status dot for live work.
struct PulseDot: View {
  var color: Color
  var size: CGFloat = 6
  var animated = true
  @State private var pulsing = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Circle().fill(color).frame(width: size, height: size)
      .background {
        Circle().fill(color.opacity(0.45))
          .scaleEffect(pulsing ? 2.3 : 1).opacity(pulsing ? 0 : 0.8)
      }
      .onAppear {
        guard animated, !reduceMotion else { return }
        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
          pulsing = true
        }
      }
  }
}

/// Daily bars with the selected trailing window highlighted.
struct DailyBars: View {
  let values: [DailyValue]
  let highlight: Int
  var tint: Color
  var height: CGFloat = 34

  var body: some View {
    let peak = max(1, values.map(\.value).max() ?? 1)
    HStack(alignment: .bottom, spacing: 2) {
      ForEach(Array(values.enumerated()), id: \.element.id) { index, day in
        let active = index >= values.count - highlight
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
          .fill(active ? tint : .white.opacity(0.13))
          .frame(height: max(2, height * day.value / peak))
          .frame(maxWidth: .infinity)
          .help("\(day.day): \(Format.count(Int(day.value)))")
      }
    }
    .frame(height: height, alignment: .bottom)
    .animation(Motion.snappy, value: highlight)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Daily activity for the last \(values.count) days")
  }
}

/// A vertically scrolling column that reports its content's natural height,
/// so the island can grow to fit and only scroll once it reaches its maximum.
struct MeasuredColumn<Content: View>: View {
  @ViewBuilder let content: Content
  let onHeight: (CGFloat) -> Void

  var body: some View {
    ScrollView {
      content.onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: {
        onHeight($0)
      }
    }
    .scrollIndicators(.never)
  }
}

struct SectionHeader: View {
  let title: String
  var count: Int?
  var glyph: Glyph?
  var color: Color = .secondary

  var body: some View {
    HStack(spacing: 6) {
      if let glyph { GlyphView(glyph: glyph, size: 11).foregroundStyle(color) }
      Text(title.uppercased())
        .font(.system(size: 10, weight: .semibold)).tracking(0.6)
        .foregroundStyle(.white.opacity(0.45))
      if let count {
        Text("\(count)").font(.system(size: 10, weight: .semibold)).monospacedDigit()
          .foregroundStyle(.white.opacity(0.3))
          .contentTransition(.numericText(value: Double(count)))
      }
      Spacer(minLength: 0)
    }
    .padding(.top, 14).padding(.bottom, 4).padding(.horizontal, 8)
  }
}
