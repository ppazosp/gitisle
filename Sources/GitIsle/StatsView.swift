import IslandCore
import SwiftUI

struct StatsView: View {
  let store: IslandStore
  @Binding var contentHeight: CGFloat

  var body: some View {
    let shipping = store.shipping
    MeasuredColumn {
      VStack(spacing: 10) {
        GitHubStatsCard(store: store)
        // Equal-height columns: each card stretches to the taller one.
        HStack(alignment: .top, spacing: 10) {
          SpeedCard(store: store, shipping: shipping)
          SizeCard(store: store, shipping: shipping)
        }
        .fixedSize(horizontal: false, vertical: true)
        RepositoriesCard(shipping: shipping)
        Text("Speed, size and repositories come from the merged PRs GitIsle already keeps.")
          .font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
          .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
      }
      .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
      .animation(Motion.snappy, value: store.statsDays)
    } onHeight: {
      contentHeight = $0
    }
  }
}

private let wideMetricColumns = Array(
  repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: 4)

private let metricColumns = Array(
  repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: 3)

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

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
        .contentTransition(numeric.map { .numericText(value: $0) } ?? .opacity)
        .lineLimit(1).minimumScaleFactor(0.7)
      Text(label).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct GitHubStatsCard: View {
  let store: IslandStore

  var body: some View {
    let stats = store.githubStats
    let days = store.statsDays
    Card(glyph: .github, tint: .white, title: "GitHub", badge: stats.map { "@\($0.login)" }) {
      ChartMenu(style: store.settings.githubChart) { style in
        store.update { $0.githubChart = style }
      }
    } content: {
      if let stats, let window = stats.window(days: days) {
        LazyVGrid(columns: wideMetricColumns, alignment: .leading, spacing: 10) {
          Metric(label: "Opened", value: "\(window.opened)", numeric: Double(window.opened))
          Metric(label: "Merged", value: "\(window.merged)", numeric: Double(window.merged))
          Metric(label: "Reviewed", value: "\(window.reviewed)", numeric: Double(window.reviewed))
          Metric(
            label: "Open now", value: "\(store.openPRs.count)",
            numeric: Double(store.openPRs.count))
        }
        .animation(Motion.snappy, value: days)
        if !stats.daily.isEmpty {
          TrendChart(
            values: Array(stats.daily.suffix(30)), highlight: days, tint: Palette.open,
            style: store.settings.githubChart, caption: "Contributions · 30 days",
            format: { "\(Int($0)) contributions" })
        }
      } else if let error = store.githubStatsError {
        Text(error).font(.system(size: 11)).foregroundStyle(Palette.attention).lineLimit(3)
      } else {
        Text("Loading activity…").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
      }
    }
  }
}

/// How fast PRs go from opened to merged.
private struct SpeedCard: View {
  let store: IslandStore
  let shipping: ShippingStats

  var body: some View {
    Card(glyph: .clock, tint: Palette.merged, title: "Speed") {
      LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 10) {
        Metric(label: "To merge", value: shipping.medianTimeToMerge.map(Format.span) ?? "—")
        Metric(label: "Fastest", value: shipping.fastest.map(Format.span) ?? "—")
        Metric(label: "Slowest", value: shipping.slowest.map(Format.span) ?? "—")
      }
      TrendChart(
        values: shipping.dailyTimeToMerge, highlight: store.statsDays, tint: Palette.merged,
        style: store.settings.githubChart, caption: "Median time to merge · 30 days",
        format: { $0 == 0 ? "No merges" : Format.span($0 * 3600) })
    }
  }
}

/// How much changed in the PRs merged.
private struct SizeCard: View {
  let store: IslandStore
  let shipping: ShippingStats

  var body: some View {
    Card(glyph: .commit, tint: Palette.open, title: "Size") {
      LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 10) {
        Metric(
          label: "Added", value: "+" + Format.count(shipping.additions),
          numeric: Double(shipping.additions))
        Metric(
          label: "Removed", value: "−" + Format.count(shipping.deletions),
          numeric: Double(shipping.deletions))
        Metric(
          label: "Typical PR", value: shipping.medianSize.map { "\(Format.count($0)) lines" } ?? "—"
        )
      }
      TrendChart(
        values: shipping.dailyLines, highlight: store.statsDays, tint: Palette.open,
        style: store.settings.githubChart, caption: "Lines changed · 30 days",
        format: { "\(Format.count(Int($0))) lines" })
    }
  }
}

/// Where merges went, most first.
private struct RepositoriesCard: View {
  let shipping: ShippingStats

  /// More would make the page scroll; the rest are summed up below.
  static let shown = 4

  var body: some View {
    let top = Array(shipping.repositories.prefix(Self.shown))
    let peak = Double(max(1, top.first?.merged ?? 1))
    Card(
      glyph: .repo, tint: .white, title: "Repositories",
      badge: shipping.merged == 1 ? "1 merge" : "\(shipping.merged) merges"
    ) {
      if top.isEmpty {
        Text("No merges in this period.").font(.system(size: 11))
          .foregroundStyle(.white.opacity(0.4))
      } else {
        VStack(spacing: 8) {
          ForEach(top, id: \.name) { repository in
            HStack(spacing: 10) {
              RepositoryName(name: repository.name)
                .frame(width: 200, alignment: .leading)
              GeometryReader { proxy in
                Capsule().fill(Palette.merged.opacity(0.6))
                  .frame(width: max(4, proxy.size.width * Double(repository.merged) / peak))
              }
              .frame(height: 5)
              Text("\(repository.merged)").font(.system(size: 11, weight: .semibold))
                .monospacedDigit().foregroundStyle(.white.opacity(0.7))
                .frame(width: 30, alignment: .trailing)
            }
          }
          let rest = shipping.repositories.dropFirst(Self.shown)
          if !rest.isEmpty {
            let merges = rest.reduce(0) { $0 + $1.merged }
            Text("\(rest.count) more, \(merges) \(merges == 1 ? "merge" : "merges")")
              .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
  }
}

/// "owner/name" with the owner dimmed, as the activity list shows repositories.
private struct RepositoryName: View {
  let name: String

  var body: some View {
    let parts = name.split(separator: "/", maxSplits: 1).map(String.init)
    (Text(parts.count == 2 ? parts[0] + "/" : "").foregroundStyle(.white.opacity(0.45))
      + Text(parts.last ?? name).foregroundStyle(.white.opacity(0.9)))
      .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
  }
}
