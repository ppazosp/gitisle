import IslandCore
import SwiftUI

struct StatsView: View {
  let store: IslandStore
  @Binding var contentHeight: CGFloat

  var body: some View {
    MeasuredColumn {
      VStack(spacing: 10) {
        GitHubStatsCard(store: store)
        // Equal-height columns: each card stretches to the taller one.
        HStack(alignment: .top, spacing: 10) {
          ForEach([AgentProvider.claude, .codex], id: \.self) { provider in
            UsageCard(store: store, provider: provider)
          }
        }
        .fixedSize(horizontal: false, vertical: true)
        Text(costNote)
          .font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
          .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
      }
      .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
    } onHeight: {
      contentHeight = $0
    }
  }

  private var costNote: String {
    let base =
      "Tokens come from local history. Costs are estimates at API prices, separate from your plan."
    guard store.settings.currency == .eur else { return base }
    return base + " Euros use 1 USD = \(store.settings.usdToEur.formatted()) EUR."
  }
}

private let wideMetricColumns = Array(
  repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: 4)

private let metricColumns = [
  GridItem(.flexible(), spacing: 8, alignment: .leading),
  GridItem(.flexible(), spacing: 8, alignment: .leading),
]

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
    let days = store.usageDays
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

private struct UsageCard: View {
  let store: IslandStore
  let provider: AgentProvider

  var body: some View {
    let days = store.usageDays
    let summary = store.usage[provider]?.first { $0.days == days }
    let history = store.usage[provider]?.first { $0.days == 30 }
    let settings = store.settings
    Card(
      glyph: provider.glyph, tint: provider.tint,
      title: provider == .claude ? "Claude Code" : "Codex",
      badge: summary?.partial == true ? "Partial history" : nil,
      badgeColor: Palette.attention
    ) {
      ChartMenu(
        style: settings.usageChart, setStyle: { style in store.update { $0.usageChart = style } },
        metric: settings.usageMetric,
        setMetric: { metric in store.update { $0.usageMetric = metric } })
    } content: {
      if let summary {
        LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 10) {
          Metric(
            label: "Tokens", value: Format.count(summary.tokens),
            numeric: summary.tokens.map(Double.init))
          Metric(
            label: "Est. API cost", value: settings.cost(summary.estimatedCost),
            numeric: summary.estimatedCost)
          Metric(
            label: "Cache read", value: Format.count(summary.cachedTokens),
            numeric: summary.cachedTokens.map(Double.init))
        }
        .animation(Motion.snappy, value: days)
        if let history {
          let tokens = settings.usageMetric == .tokens
          let values = tokens ? history.daily : history.dailyCost
          if !values.isEmpty {
            TrendChart(
              values: values, highlight: days, tint: provider.tint.opacity(0.9),
              style: settings.usageChart,
              caption: "\(settings.usageMetric.label) · 30 days",
              format: { value in
                tokens ? "\(Format.count(Int(value))) tokens" : settings.cost(value)
              })
          }
        }
        if !summary.models.isEmpty { models(summary) }
      } else if let error = store.usageErrors[provider] {
        Text(error).font(.system(size: 11)).foregroundStyle(Palette.attention).lineLimit(3)
      } else {
        Text("Reading local history…").font(.system(size: 11))
          .foregroundStyle(.white.opacity(0.4))
      }
    }
  }

  private func models(_ summary: UsageSummary) -> some View {
    let top = Array(summary.models.prefix(3))
    let peak = Double(max(1, top.compactMap(\.tokens).max() ?? 1))
    return VStack(spacing: 6) {
      ForEach(top) { model in
        VStack(spacing: 4) {
          HStack(spacing: 8) {
            Text(model.name).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
              .lineLimit(1)
            Spacer(minLength: 4)
            Text(Format.count(model.tokens)).font(.system(size: 10.5)).monospacedDigit()
              .foregroundStyle(.white.opacity(0.5))
          }
          GeometryReader { proxy in
            Capsule().fill(provider.tint.opacity(0.55))
              .frame(width: max(3, proxy.size.width * Double(model.tokens ?? 0) / peak))
          }
          .frame(height: 3)
        }
      }
    }
    .animation(Motion.snappy, value: store.usageDays)
  }
}
