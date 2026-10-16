import IslandCore
import SwiftUI

/// The island outline. Attached to a notch it flares into the top edge of the screen;
/// on other displays it floats as a rounded rectangle.
struct IslandShape: Shape {
  var ear: CGFloat
  var radius: CGFloat
  var attached: Bool

  var animatableData: AnimatablePair<CGFloat, CGFloat> {
    get { AnimatablePair(ear, radius) }
    set {
      ear = newValue.first
      radius = newValue.second
    }
  }

  func path(in rect: CGRect) -> Path {
    guard attached else {
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
  static let update = Color(red: 0.24, green: 0.56, blue: 1.0)
  static let surface = Color.white.opacity(0.055)
  static let hairline = Color.white.opacity(0.09)
}

enum Motion {
  /// Shape morphs between compact, banner, and expanded.
  static let morph = Animation.spring(response: 0.3, dampingFraction: 0.85)
  /// Shrinking must not overshoot: a bounce below the resting size exposes what is behind it.
  static let collapse = Animation.spring(response: 0.26, dampingFraction: 1)
  static let snappy = Animation.snappy(duration: 0.18)
}

extension AnyTransition {
  /// Content arrives after the shape has started growing and leaves before it shrinks.
  static var islandContent: AnyTransition {
    .asymmetric(
      insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
        .animation(.smooth(duration: 0.2).delay(0.04)),
      removal: .opacity.animation(.easeOut(duration: 0.08)))
  }
}

extension PRGroup {
  /// Board columns follow a PR's life from left to right; "needs you" sits where a PR
  /// waits on you between review and merging.
  static let boardOrder: [PRGroup] = [.draft, .open, .merging, .merged]

  var glyph: Glyph {
    switch self {
    case .open: .pullRequest
    case .merging: .mergeQueue
    case .draft: .draft
    case .merged: .merge
    }
  }

  var color: Color {
    switch self {
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
    case .open: .pullRequest
    case nil: .closed
    }
  }

  /// The PR's state, with the specific reason when it needs you.
  var stateLabel: (text: String, color: Color) {
    switch group {
    case .open where needsYou: (status.label, status.color)
    case .merging: (queuePosition == nil ? "Auto-merge" : "Merging", Palette.merging)
    case .open:
      [.checking, .unknown].contains(status)
        ? ("Open", Palette.open) : (status.label, Palette.open)
    case .draft: ("Draft", Palette.draft)
    case .merged: ("Merged", Palette.merged)
    case nil: ("Closed", Palette.failed)
    }
  }

  var glyphColor: Color {
    switch group {
    case .merged: Palette.merged
    case .draft: Palette.draft
    case .merging: Palette.merging
    case .open: Palette.open
    case nil: Palette.failed
    }
  }
}

extension PRStatus {
  var color: Color {
    switch self {
    case .failed, .conflicts, .changesRequested, .closed: Palette.failed
    case .review, .waiting, .behind, .blocked: Palette.attention
    case .ready, .opened, .readyForReview: Palette.open
    case .draft: Palette.draft
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
    case .ready: .checkFill
    case .queued: .mergeQueue
    case .draft: .draft
    default: .pullRequest
    }
  }

  var eventTitle: String {
    switch self {
    case .merged: "Merged"
    case .failed: "Checks failed"
    case .review: "Review requested"
    case .ready: "Ready to merge"
    case .queued: "Merging"
    case .draft: "New draft PR"
    default: label
    }
  }

  /// Lower shows first when several changes arrive together.
  var bannerPriority: Int {
    switch self {
    case .merged: 0
    case .failed: 1
    case .review: 2
    case .ready: 3
    case .queued: 4
    case .readyForReview: 5
    case .opened, .draft: 6
    default: 7
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

  /// A short duration such as "48s", "5m 1s", or "1h 12m".
  static func duration(_ seconds: TimeInterval) -> String {
    let total = Int(max(0, seconds).rounded())
    switch total {
    case ..<60: return "\(total)s"
    case ..<3600: return total % 60 == 0 ? "\(total / 60)m" : "\(total / 60)m \(total % 60)s"
    default: return "\(total / 3600)h \((total % 3600) / 60)m"
    }
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

/// A row that reveals the rest of a shortened list.
struct ShowMoreButton: View {
  let hidden: Int
  let action: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        Text("Show \(hidden) more")
      }
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(.white.opacity(hovered ? 0.85 : 0.5))
      .frame(maxWidth: .infinity).padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(.white.opacity(hovered ? 0.07 : 0.035))
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
  }
}

/// A repository's image: its owner's GitHub avatar, or the repository glyph until
/// that loads. Images are kept in memory so re-rendering never fetches them again.
struct RepoAvatar: View {
  let url: URL?
  var size: CGFloat = 18
  /// People are shown in circles; repositories and organizations in rounded squares.
  var circular = false
  var placeholder: Glyph = .repo
  @State private var image: NSImage?

  @MainActor private static var cache: [URL: NSImage] = [:]

  var body: some View {
    Group {
      if let image = image ?? url.flatMap({ Self.cache[$0] }) {
        Image(nsImage: image).resizable().interpolation(.high)
          .frame(width: size, height: size)
          .clipShape(
            RoundedRectangle(cornerRadius: circular ? size / 2 : size * 0.28, style: .continuous))
      } else {
        GlyphView(glyph: placeholder, size: size * 0.8).foregroundStyle(.white.opacity(0.5))
          .frame(width: size, height: size)
      }
    }
    .task(id: url) {
      guard let url, Self.cache[url] == nil,
        let (data, _) = try? await URLSession.shared.data(from: url),
        let loaded = NSImage(data: data)
      else { return }
      Self.cache[url] = loaded
      withAnimation(.easeOut(duration: 0.15)) { image = loaded }
    }
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
