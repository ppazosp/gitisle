import Charts
import IslandCore
import SwiftUI

/// A 30-day trend in one of several styles. The selected period is emphasized, and
/// hovering a day shows its value in the caption.
struct TrendChart: View {
  let values: [DailyValue]
  /// How many trailing days belong to the selected period.
  let highlight: Int
  let tint: Color
  let style: ChartStyle
  let caption: String
  let format: (Double) -> String
  var height: CGFloat = 52
  @State private var selected: Date?

  private struct Point: Identifiable {
    let date: Date
    let value: Double
    let active: Bool
    var id: Date { date }
  }

  private static let parser: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.calendar = Calendar(identifier: .gregorian)
    return formatter
  }()

  private var points: [Point] {
    var running = 0.0
    return values.enumerated().compactMap { index, day in
      guard let date = Self.parser.date(from: day.day) else { return nil }
      running += day.value
      return Point(
        date: date, value: style == .cumulative ? running : day.value,
        active: index >= values.count - highlight)
    }
  }

  var body: some View {
    let points = self.points
    let peak = max(points.map(\.value).max() ?? 0, 1)
    let hovered = selected.flatMap { day in
      points.first { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }
    VStack(alignment: .leading, spacing: 6) {
      Chart {
        // Bars colour the selected period; other styles mark where it starts, and only
        // when it is shorter than the chart.
        if style != .bars, points.first?.active == false,
          let start = points.first(where: \.active)?.date
        {
          RuleMark(x: .value("Period start", start))
            .foregroundStyle(.white.opacity(0.18))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        ForEach(points) { point in
          switch style {
          case .bars:
            BarMark(x: .value("Day", point.date, unit: .day), y: .value("Value", point.value))
              .foregroundStyle(point.active ? tint : .white.opacity(0.14))
              .cornerRadius(1.5)
          case .line:
            LineMark(x: .value("Day", point.date), y: .value("Value", point.value))
              .interpolationMethod(.catmullRom)
              .foregroundStyle(tint)
              .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
          case .area, .cumulative:
            AreaMark(x: .value("Day", point.date), y: .value("Value", point.value))
              .interpolationMethod(.catmullRom)
              .foregroundStyle(
                LinearGradient(
                  colors: [tint.opacity(0.45), tint.opacity(0.02)], startPoint: .top,
                  endPoint: .bottom))
            LineMark(x: .value("Day", point.date), y: .value("Value", point.value))
              .interpolationMethod(.catmullRom)
              .foregroundStyle(tint)
              .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
          }
        }
        if let hovered {
          if style == .bars {
            RuleMark(x: .value("Day", hovered.date, unit: .day))
              .foregroundStyle(.white.opacity(0.4))
              .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
          } else {
            RuleMark(x: .value("Day", hovered.date))
              .foregroundStyle(.white.opacity(0.4))
              .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
            PointMark(x: .value("Day", hovered.date), y: .value("Value", hovered.value))
              .foregroundStyle(tint).symbolSize(28)
          }
        }
      }
      .chartXAxis(.hidden)
      .chartYAxis(.hidden)
      .chartYScale(domain: 0...peak)
      .chartLegend(.hidden)
      .chartXSelection(value: $selected)
      .frame(height: height)
      .animation(Motion.snappy, value: style)
      .animation(Motion.snappy, value: highlight)

      Text(captionText(hovered))
        .font(.system(size: 10)).monospacedDigit()
        .foregroundStyle(.white.opacity(hovered == nil ? 0.35 : 0.7))
        .contentTransition(.opacity)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(caption)
  }

  private func captionText(_ hovered: Point?) -> String {
    guard let hovered else { return caption }
    let day = hovered.date.formatted(.dateTime.month(.abbreviated).day())
    return "\(day) · \(format(hovered.value))"
  }
}

/// Chooses a chart style, and optionally what the chart measures.
struct ChartMenu: View {
  let style: ChartStyle
  let setStyle: (ChartStyle) -> Void
  var metric: UsageMetric?
  var setMetric: ((UsageMetric) -> Void)?

  var body: some View {
    Menu {
      Section("Chart") {
        ForEach(ChartStyle.allCases, id: \.self) { option in
          Button {
            setStyle(option)
          } label: {
            Label(option.label, systemImage: option == style ? "checkmark" : option.symbol)
          }
        }
      }
      if let metric, let setMetric {
        Section("Show") {
          ForEach(UsageMetric.allCases, id: \.self) { option in
            Button {
              setMetric(option)
            } label: {
              Label(option.label, systemImage: option == metric ? "checkmark" : "circle")
            }
          }
        }
      }
    } label: {
      Image(systemName: style.symbol)
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(.white.opacity(0.6))
        .frame(width: 26, height: 20)
        .background(Capsule().fill(.white.opacity(0.07)))
        .contentShape(Capsule())
    }
    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    .help("Chart style")
    .accessibilityLabel("Chart style")
  }
}
