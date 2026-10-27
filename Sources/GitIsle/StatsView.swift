import IslandCore
import SwiftUI

struct StatsView: View {
  let store: IslandStore
  @Binding var contentHeight: CGFloat

  var body: some View {
    let trends = store.trends
    MeasuredColumn {
      VStack(spacing: 10) {
        PullRequestsCard(store: store, trends: trends)
        // Equal-height columns: each card stretches to the taller one.
        HStack(alignment: .top, spacing: 10) {
          LinesCard(trends: trends, hourly: store.statsDays == 1)
          ClockCard(trends: trends, days: store.statsDays)
        }
        .fixedSize(horizontal: false, vertical: true)
        Text("Counts come from GitHub; charts from the PRs GitIsle keeps for 30 days.")
          .font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
          .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
      }
      .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
      .animation(Motion.snappy, value: store.statsDays)
      .animation(Motion.snappy, value: store.repositoryFilter)
    } onHeight: {
      contentHeight = $0
    }
  }
}

private let wideMetricColumns = Array(
  repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: 4)

private struct Card<Accessory: View, Content: View>: View {
  let glyph: Glyph
  let tint: Color
  let title: String
  var badge: String?
  var badgeColor: Color = .white.opacity(0.4)
  @ViewBuilder let accessory: Accessory
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        GlyphView(glyph: glyph, size: 15).foregroundStyle(tint)
        Text(title).font(.system(size: 13, weight: .semibold))
        Spacer()
        if let badge {
          Text(badge).font(.system(size: 10.5, weight: .medium)).foregroundStyle(badgeColor)
        }
        accessory
      }
      content
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.surface))
  }
}

extension Card where Accessory == EmptyView {
  /// A card with nothing beside its title.
  init(
    glyph: Glyph, tint: Color, title: String, badge: String? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.init(
      glyph: glyph, tint: tint, title: title, badge: badge, accessory: { EmptyView() },
      content: content)
  }
}

private struct Metric: View {
  let label: String
  let value: String
  var numeric: Double?
  /// The colour of the chart series this number belongs to.
  var dot: Color?
  var valueColor: Color = .white

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
        .foregroundStyle(valueColor)
        .contentTransition(numeric.map { .numericText(value: $0) } ?? .opacity)
        .lineLimit(1).minimumScaleFactor(0.7)
      HStack(spacing: 5) {
        if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
        Text(label)
      }
      .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Your PRs opened, merged and reviewed in the period, and opened and merged each day.
private struct PullRequestsCard: View {
  let store: IslandStore
  let trends: PullRequestTrends

  var body: some View {
    let counts = store.statsCounts
    let login = store.githubStats?.login ?? store.github?.login
    Card(glyph: .github, tint: .white, title: "Pull requests", badge: login.map { "@\($0)" }) {
      ChartMenu(style: store.settings.githubChart) { style in
        store.update { $0.githubChart = style }
      }
    } content: {
      if counts == nil, let error = store.githubStatsError {
        Text(error).font(.system(size: 11)).foregroundStyle(Palette.attention).lineLimit(3)
      }
      LazyVGrid(columns: wideMetricColumns, alignment: .leading, spacing: 10) {
        count("Opened", counts?.opened, dot: Palette.open)
        count("Merged", counts?.merged, dot: Palette.merged)
        count("Reviewed", counts?.reviewed)
        count("Open now", store.openNow)
      }
      .animation(Motion.snappy, value: store.statsDays)
      TrendChart(
        series: [
          .init(name: "Opened", values: trends.opened, tint: Palette.open),
          .init(name: "Merged", values: trends.merged, tint: Palette.merged),
        ],
        highlight: store.statsDays, style: store.settings.githubChart,
        caption: "Opened and merged per day · 30 days",
        format: { "\(Int($0[0])) opened, \(Int($0[1])) merged" })
    }
  }

  /// A count, or a dash while GitHub's count for this period and these repositories loads.
  private func count(_ label: String, _ value: Int?, dot: Color? = nil) -> Metric {
    Metric(
      label: label, value: value.map(String.init) ?? "—", numeric: value.map(Double.init),
      dot: dot)
  }
}

/// Lines your merged PRs added and removed: added grows up from the middle, removed down.
private struct LinesCard: View {
  let trends: PullRequestTrends
  /// Today's bars are hours; other periods' are days.
  let hourly: Bool
  @State private var hovered: Int?

  var body: some View {
    let lines = trends.lines
    Card(glyph: .code, tint: .white, title: "Lines", badge: "merged PRs") {
      HStack(spacing: 18) {
        Metric(
          label: "Added", value: "+" + trends.added.formatted(),
          numeric: Double(trends.added), valueColor: Palette.open)
        Metric(
          label: "Removed", value: "−" + trends.removed.formatted(),
          numeric: Double(trends.removed), valueColor: Palette.failed)
      }
      DivergingBars(lines: lines, hovered: $hovered)
        .frame(minHeight: 96, maxHeight: .infinity)
      Text(caption(lines))
        .font(.system(size: 10)).monospacedDigit()
        .foregroundStyle(.white.opacity(hovered == nil ? 0.35 : 0.7))
        .lineLimit(1)
    }
  }

  private func caption(_ lines: [PullRequestTrends.Lines]) -> String {
    guard let hovered, lines.indices.contains(hovered) else {
      let cut = lines.contains { Double(max($0.added, $0.removed)) > DivergingBars.cap(lines) }
      return cut
        ? "Per \(hourly ? "hour" : "day") · tall bars cut to fit"
        : "Added above, removed below · per \(hourly ? "hour" : "day")"
    }
    let bucket = lines[hovered]
    let when =
      hourly
      ? bucket.start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
      : bucket.start.formatted(.dateTime.month(.abbreviated).day())
    return "\(when) · +\(bucket.added.formatted()) −\(bucket.removed.formatted())"
  }
}

/// One bar per hour or day, added above the middle and removed below. One huge cleanup would
/// flatten every other bar, so bars stop at a cap set by the typical ones; the caption says so.
private struct DivergingBars: View {
  let lines: [PullRequestTrends.Lines]
  @Binding var hovered: Int?

  /// Three times the upper quartile of the non-zero values, so only outliers get cut.
  static func cap(_ lines: [PullRequestTrends.Lines]) -> Double {
    let values = lines.flatMap { [$0.added, $0.removed] }.filter { $0 > 0 }.sorted()
    guard let largest = values.last else { return 1 }
    let quartile = values[min(values.count - 1, values.count * 3 / 4)]
    return Double(max(1, min(largest, quartile * 3)))
  }

  var body: some View {
    let cap = Self.cap(lines)
    GeometryReader { proxy in
      let half = proxy.size.height / 2
      let slot = proxy.size.width / CGFloat(max(lines.count, 1))
      let width = max(1.5, slot * (lines.count > 24 ? 0.72 : 0.62))
      ZStack(alignment: .topLeading) {
        Rectangle().fill(.white.opacity(0.08)).frame(height: 1).offset(y: half)
        ForEach(Array(lines.enumerated()), id: \.offset) { index, bucket in
          let x = slot * CGFloat(index) + (slot - width) / 2
          let dim = hovered != nil && hovered != index
          bar(bucket.added, cap: cap, half: half, color: Palette.open, up: true)
            .frame(width: width).offset(x: x, y: 0).opacity(dim ? 0.45 : 1)
          bar(bucket.removed, cap: cap, half: half, color: Palette.failed, up: false)
            .frame(width: width).offset(x: x, y: half + 1).opacity(dim ? 0.45 : 1)
        }
      }
      // Offsets move the removed bars down without growing the stack, so it takes the full
      // size here or hovering would only reach the top half.
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
      .contentShape(Rectangle())
      .onContinuousHover { phase in
        switch phase {
        case .active(let point):
          hovered = min(max(Int(point.x / slot), 0), lines.count - 1)
        case .ended: hovered = nil
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Lines added and removed")
  }

  /// A bar of `value` lines, stopping at the cap.
  private func bar(_ value: Int, cap: Double, half: CGFloat, color: Color, up: Bool) -> some View {
    let length = value == 0 ? 0 : max(1.5, (half - 1) * min(Double(value), cap) / cap)
    return VStack(spacing: 0) {
      if up { Spacer(minLength: 0) }
      UnevenRoundedRectangle(
        topLeadingRadius: up ? 1.5 : 0, bottomLeadingRadius: up ? 0 : 1.5,
        bottomTrailingRadius: up ? 0 : 1.5, topTrailingRadius: up ? 1.5 : 0
      )
      .fill(color)
      .frame(height: length)
      if !up { Spacer(minLength: 0) }
    }
    .frame(height: half - 1)
  }
}

/// The hours of the day you open and merge PRs: one pair of bars per hour around a clock.
private struct ClockCard: View {
  let trends: PullRequestTrends
  let days: Int

  var body: some View {
    let opened = trends.openedByHour
    let merged = trends.mergedByHour
    let totals = zip(opened, merged).map(+)
    let busiest = totals.max().flatMap { $0 > 0 ? totals.firstIndex(of: $0) : nil }
    Card(
      glyph: .clock, tint: .white, title: "Around the clock",
      badge: days == 1 ? "today" : "\(days) days"
    ) {
      ZStack {
        HourClock(opened: opened, merged: merged)
        VStack(spacing: 1) {
          Text(busiest.map { String(format: "%02d:00", $0) } ?? "—")
            .font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
            .contentTransition(.numericText(value: Double(busiest ?? -1)))
          Text("busiest hour").font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 196)
      HStack(spacing: 12) {
        legend("Opened", Palette.open)
        legend("Merged", Palette.merged)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      busiest.map { "PRs by hour of day. Busiest at \($0):00." } ?? "No PRs in this period.")
  }

  private func legend(_ label: String, _ color: Color) -> some View {
    HStack(spacing: 5) {
      Circle().fill(color).frame(width: 6, height: 6)
      Text(label)
    }
    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
  }
}

/// 24 hours around a circle, midnight at the top, with an opened and a merged bar side by
/// side for each hour. Each bar is its own shape, so a new period grows and shrinks them.
private struct HourClock: View {
  let opened: [Int]
  let merged: [Int]

  var body: some View {
    let peak = Double(max((opened + merged).max() ?? 0, 1))
    let series: [([Int], Double, Color)] = [
      (opened, -0.055, Palette.open), (merged, 0.055, Palette.merged),
    ]
    GeometryReader { proxy in
      let radius = min(proxy.size.width, proxy.size.height) / 2
      let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
      ZStack {
        Circle().stroke(.white.opacity(0.12), lineWidth: 1)
          .frame(width: (radius * 0.4 - 4) * 2, height: (radius * 0.4 - 4) * 2)
          .position(center)
        ForEach(0..<24, id: \.self) { hour in
          ForEach(0..<2, id: \.self) { index in
            let (values, offset, color) = series[index]
            let value = Double(values[hour])
            RadialBar(
              angle: Self.angle(hour: Double(hour) + 0.5) + offset,
              length: value / peak
            )
            .stroke(
              value > 0 ? color : .white.opacity(0.15),
              style: StrokeStyle(lineWidth: 4, lineCap: .round))
          }
        }
        ForEach([0, 6, 12, 18], id: \.self) { hour in
          let angle = Self.angle(hour: Double(hour))
          Text(String(format: "%02d", hour)).font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.4))
            .position(
              x: center.x + radius * 0.82 * cos(angle) + 9 * cos(angle),
              y: center.y + radius * 0.82 * sin(angle) + 9 * sin(angle))
        }
      }
    }
  }

  /// Midnight at the top, going clockwise.
  static func angle(hour: Double) -> Double { hour / 24 * 2 * .pi - .pi / 2 }
}

/// One hour's bar: it starts at 0.4 of the radius and grows outwards by `length`, a share of
/// the busiest hour, up to 0.42 of the radius.
private struct RadialBar: Shape {
  let angle: Double
  var length: Double

  var animatableData: Double {
    get { length }
    set { length = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let radius = min(rect.width, rect.height) / 2
    let inner = radius * 0.4
    let end = inner + max(radius * 0.42 * length, 1.5)
    var path = Path()
    path.move(to: point(rect, inner))
    path.addLine(to: point(rect, end))
    return path
  }

  private func point(_ rect: CGRect, _ distance: Double) -> CGPoint {
    CGPoint(x: rect.midX + distance * cos(angle), y: rect.midY + distance * sin(angle))
  }
}
