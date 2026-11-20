import Charts
import IslandCore
import SwiftUI

/// A 30-day trend of one or more series in one of several styles. Days before the selected
/// period are shaded, and hovering a day shows its values in the caption.
struct TrendChart: View {
  struct Series {
    let name: String
    let values: [DailyValue]
    let tint: Color
  }

  let series: [Series]
  /// How many trailing days belong to the selected period.
  let highlight: Int
  let style: ChartStyle
  let caption: String
  /// Describes one day's values, one per series, while it's hovered.
  let format: ([Double]) -> String
  var height: CGFloat = 52
  @State private var selected: Date?

  private struct Point: Identifiable {
    let series: Int
    let date: Date
    let value: Double
    var id: String { "\(series)-\(date.timeIntervalSinceReferenceDate)" }
  }

  private static let parser: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.calendar = Calendar(identifier: .gregorian)
    return formatter
  }()

  private var points: [Point] {
    series.enumerated().flatMap { index, series in
      var running = 0.0
      return series.values.compactMap { day -> Point? in
        guard let date = Self.parser.date(from: day.day) else { return nil }
        running += day.value
        return Point(
          series: index, date: date, value: style == .cumulative ? running : day.value)
      }
    }
  }

  var body: some View {
    let points = self.points
    let peak = max(points.map(\.value).max() ?? 0, 1)
    let hovered = selected.map { day in
      points.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }
    let days = Array(Set(points.map(\.date))).sorted()
    let start = days.count > highlight ? days[days.count - highlight] : nil
    VStack(alignment: .leading, spacing: 6) {
      Chart {
        ForEach(points) { point in
          let tint = series[point.series].tint
          let name = series[point.series].name
          switch style {
          case .bars:
            BarMark(x: .value("Day", point.date, unit: .day), y: .value("Value", point.value))
              .position(by: .value("Series", name))
              .foregroundStyle(tint)
              .cornerRadius(1.5)
          case .line:
            LineMark(
              x: .value("Day", point.date), y: .value("Value", point.value),
              series: .value("Series", name)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
          case .area, .cumulative:
            AreaMark(
              x: .value("Day", point.date), y: .value("Value", point.value),
              series: .value("Series", name), stacking: .unstacked
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
              LinearGradient(
                colors: [tint.opacity(0.3), tint.opacity(0.02)], startPoint: .top,
                endPoint: .bottom))
            LineMark(
              x: .value("Day", point.date), y: .value("Value", point.value),
              series: .value("Series", name)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
          }
        }
        if let day = hovered?.first?.date {
          RuleMark(x: .value("Day", day, unit: .day))
            .foregroundStyle(.white.opacity(0.4))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
        }
      }
      .chartXAxis(.hidden)
      .chartYAxis(.hidden)
      .chartYScale(domain: 0...peak)
      .chartLegend(.hidden)
      .chartXSelection(value: $selected)
      // A shade over the days before the period. Charts swaps a mark's colour without
      // animating it, while the shade's width animates.
      .chartOverlay { proxy in
        GeometryReader { geometry in
          if let frame = proxy.plotFrame.map({ geometry[$0] }) {
            let edge = start.flatMap { day in
              // Bars fill their whole day, so the period starts at the day's left edge;
              // lines start halfway between the day and the one before.
              proxy.position(forX: style == .bars ? day : day.addingTimeInterval(-43_200))
            }
            Rectangle()
              // The card's own colour: its surface over the black island.
              .fill(Color(white: 0.055).opacity(0.72))
              .frame(width: max(0, edge ?? 0), height: frame.height)
              .offset(x: frame.minX, y: frame.minY)
              .allowsHitTesting(false)
          }
        }
      }
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

  private func captionText(_ hovered: [Point]?) -> String {
    guard let hovered, let date = hovered.first?.date else { return caption }
    let day = date.formatted(.dateTime.month(.abbreviated).day())
    let values = series.indices.map { index in
      hovered.first { $0.series == index }?.value ?? 0
    }
    return "\(day) · \(format(values))"
  }
}

/// Chooses a chart style.
struct ChartMenu: View {
  let style: ChartStyle
  let setStyle: (ChartStyle) -> Void

  var body: some View {
    DropdownButton(id: "chart-github", trailing: true) {
      [
        Dropdown.Section(
          id: "chart", title: "Chart",
          items: ChartStyle.allCases.map { option in
            Dropdown.Item(
              id: option.rawValue, title: option.label, systemImage: option.symbol,
              selected: option == style
            ) { setStyle(option) }
          })
      ]
    } label: {
      Image(systemName: style.symbol)
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(.white.opacity(0.6))
        .frame(width: 26, height: 20)
        .background(Capsule().fill(.white.opacity(0.07)))
        .contentShape(Capsule())
    }
    .fixedSize()
    .help("Chart style")
    .accessibilityLabel("Chart style")
  }
}
