import AppKit
import IslandCore
import SwiftUI

struct IslandView: View {
  @Bindable var store: IslandStore
  let metrics: IslandMetrics
  @State private var contentHeight: CGFloat = 220
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let presentation = store.presentation
    let size = size(for: presentation)
    let shape = IslandShape(ear: metrics.ear, radius: metrics.cornerRadius(for: presentation))
    ZStack(alignment: .top) {
      if presentation == .expanded {
        ExpandedIsland(store: store, metrics: metrics, contentHeight: $contentHeight)
          .transition(.islandContent)
      } else {
        VStack(spacing: 0) {
          CompactBar(store: store, metrics: metrics)
          if presentation == .banner, let event = store.recentEvent {
            EventBanner(event: event, extra: store.recentEventExtra)
              .transition(.islandContent)
          }
        }
        .transition(.islandContent)
      }
    }
    .padding(.horizontal, metrics.ear)
    .frame(width: size.width, height: size.height, alignment: .top)
    .background(.black)
    .clipShape(shape)
    .background {
      shape.fill(.black)
        .shadow(color: .black.opacity(presentation == .compact ? 0 : 0.45), radius: 18, y: 10)
    }
    .contentShape(shape)
    .foregroundStyle(.white)
    .environment(\.colorScheme, .dark)
    .onGeometryChange(for: CGSize.self) {
      $0.size
    } action: {
      store.islandSize = $0
    }
    .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.morph, value: presentation)
    .animation(reduceMotion ? nil : Motion.morph, value: contentHeight)
    .padding(.top, metrics.topGap)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private func size(for presentation: IslandStore.Presentation) -> CGSize {
    switch presentation {
    case .compact:
      return CGSize(width: metrics.closedWidth + 2 * metrics.ear, height: metrics.closedHeight)
    case .banner:
      let banner = metrics.bannerSize
      return CGSize(width: banner.width + 2 * metrics.ear, height: banner.height)
    case .expanded:
      let chrome = ExpandedIsland.chromeHeight(metrics)
      return CGSize(
        width: metrics.expandedWidth + 2 * metrics.ear,
        height: min(metrics.maxExpandedHeight, chrome + contentHeight))
    }
  }
}

// MARK: - Compact

private struct CompactBar: View {
  let store: IslandStore
  let metrics: IslandMetrics

  var body: some View {
    Button {
      store.expanded = true
    } label: {
      HStack(spacing: 7) {
        leading
        if metrics.hasNotch {
          Spacer(minLength: metrics.notchWidth)
        } else {
          Spacer(minLength: 10)
        }
        trailing
      }
      .font(.system(size: 13.5, weight: .medium))
      .monospacedDigit()
      .lineLimit(1)
      .padding(.horizontal, metrics.hasNotch ? 14 : 18)
      .frame(maxWidth: .infinity, minHeight: metrics.closedHeight, maxHeight: metrics.closedHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityText)
    .accessibilityHint("Expands the island")
  }

  @ViewBuilder private var leading: some View {
    if store.githubError != nil && store.github == nil {
      GlyphView(glyph: .sync, size: 15).foregroundStyle(Palette.attention)
      Text("Offline").foregroundStyle(.secondary)
    } else if store.github == nil {
      GlyphView(glyph: .github, size: 16).foregroundStyle(.secondary)
      Text("Connecting").foregroundStyle(.secondary)
    } else if let first = store.merging.first {
      GlyphView(glyph: .mergeQueue, size: 16).foregroundStyle(Palette.merging)
        .phaseAnimator([1.0, 0.45]) { glyph, opacity in
          glyph.opacity(opacity)
        } animation: { _ in
          .easeInOut(duration: 1.1)
        }
      Text(verbatim: "#\(first.number)")
      if store.merging.count > 1 {
        Text(verbatim: "+\(store.merging.count - 1)").foregroundStyle(.white.opacity(0.45))
      }
    } else if store.attention.isEmpty {
      GlyphView(glyph: .checkFill, size: 15).foregroundStyle(Palette.open)
      Text("All clear").foregroundStyle(.white.opacity(0.85))
    } else {
      GlyphView(glyph: .pullRequest, size: 16).foregroundStyle(Palette.open)
      Text("\(store.attention.count) need you")
        .contentTransition(.numericText(value: Double(store.attention.count)))
    }
  }

  @ViewBuilder private var trailing: some View {
    if let since = store.merging.first?.mergingSince {
      // How long the PR has been merging; the system updates the timer without polling.
      Text(since, style: .timer)
        .foregroundStyle(Palette.merging)
        .multilineTextAlignment(.trailing)
        .fixedSize()
    } else {
      Text("\(store.openPRs.count) open")
        .foregroundStyle(.white.opacity(0.5))
        .contentTransition(.numericText(value: Double(store.openPRs.count)))
    }
  }

  private var accessibilityText: String {
    var parts = ["GitIsle", "\(store.attention.count) pull requests need you"]
    if !store.merging.isEmpty { parts.append("\(store.merging.count) merging") }
    parts.append("\(store.openPRs.count) open")
    return parts.joined(separator: ", ")
  }
}

// MARK: - Banner

private struct EventBanner: View {
  let event: IslandEvent
  let extra: Int

  var body: some View {
    Button {
      NSWorkspace.shared.open(event.url)
    } label: {
      HStack(spacing: 11) {
        GlyphView(glyph: event.kind.eventGlyph, size: 16)
          .foregroundStyle(event.kind.color)
          .frame(width: 32, height: 32)
          .background(Circle().fill(event.kind.color.opacity(0.18)))
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(event.kind.eventTitle).font(.system(size: 13, weight: .semibold))
            Text(reference).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
          }
          Text(event.detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
        }
        .lineLimit(1)
        Spacer(minLength: 4)
        if extra > 0 {
          Text("+\(extra)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.1)))
        }
      }
      .padding(.horizontal, 16).padding(.bottom, 12).padding(.top, 2)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(event.kind.eventTitle): \(event.detail)")
    .accessibilityHint("Opens the pull request on GitHub")
  }

  /// "owner/repo #12" from the stored "owner/repo #12 · Merged" title.
  private var reference: String {
    event.title.components(separatedBy: " · ").first ?? event.title
  }
}

// MARK: - Expanded

private struct ExpandedIsland: View {
  @Bindable var store: IslandStore
  let metrics: IslandMetrics
  @Binding var contentHeight: CGFloat

  static let headerHeight: CGFloat = 54
  static let footerHeight: CGFloat = 46

  static func chromeHeight(_ metrics: IslandMetrics) -> CGFloat {
    topInset(metrics) + headerHeight + footerHeight + 1
  }

  static func topInset(_ metrics: IslandMetrics) -> CGFloat {
    metrics.hasNotch ? metrics.notchHeight + 4 : 10
  }

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(.top, Self.topInset(metrics))
        .frame(height: Self.topInset(metrics) + Self.headerHeight, alignment: .bottom)
      Rectangle().fill(Palette.hairline).frame(height: 1).padding(.horizontal, 28)
      Group {
        if store.showingSettings {
          SettingsView(store: store, contentHeight: $contentHeight)
        } else {
          switch store.tab {
          case .activity: ActivityView(store: store, contentHeight: $contentHeight)
          case .stats: StatsView(store: store, contentHeight: $contentHeight)
          }
        }
      }
      .id(store.showingSettings ? "settings" : store.tab.rawValue)
      .transition(.opacity.animation(.easeOut(duration: 0.12)))
      .frame(maxHeight: .infinity, alignment: .top)
      footer.frame(height: Self.footerHeight)
    }
  }

  @ViewBuilder private var header: some View {
    if store.showingSettings {
      HStack(spacing: 10) {
        FooterButton(glyph: nil, systemImage: "chevron.left", label: "Back") {
          withAnimation(Motion.snappy) { store.showingSettings = false }
        }
        Text("Settings").font(.system(size: 14, weight: .semibold))
        Spacer()
      }
      .padding(.horizontal, 22)
      .frame(height: Self.headerHeight)
    } else {
      tabsHeader
    }
  }

  private var tabsHeader: some View {
    HStack(spacing: 8) {
      PillPicker(
        options: IslandStore.IslandTab.allCases.map { ($0, $0.rawValue) },
        selection: $store.tab)
      Spacer(minLength: 8)
      switch store.tab {
      case .activity:
        PillPicker(
          options: ActivityWindow.allCases.map { ($0, $0.label) },
          selection: $store.activityWindow, fontSize: 11)
      case .stats:
        PillPicker(
          options: [(1, "Today"), (7, "7 days"), (30, "30 days")],
          selection: $store.usageDays, fontSize: 11)
      }
    }
    .padding(.horizontal, 28)
    .frame(height: Self.headerHeight)
  }

  private var footer: some View {
    HStack(spacing: 4) {
      status.font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
      Spacer()
      FooterButton(glyph: .sync, label: "Refresh", spinning: refreshing) {
        Task {
          async let github: Void = store.refreshGitHub()
          async let usage: Void = store.refreshUsage()
          async let stats: Void = store.refreshStats()
          _ = await (github, usage, stats)
        }
      }
      .disabled(refreshing || store.isDemo)
      FooterButton(glyph: .gear, label: "GitIsle settings") {
        withAnimation(Motion.snappy) { store.showingSettings.toggle() }
      }
      FooterButton(glyph: nil, label: "Collapse island") { store.dismiss() }
    }
    .padding(.horizontal, 24)
  }

  private var refreshing: Bool { store.githubRefreshing || store.usageRefreshing }

  @ViewBuilder private var status: some View {
    if store.isDemo {
      Text("Example data")
    } else if let github = store.github {
      let age = github.fetchedAt.formatted(.relative(presentation: .named))
      Text(store.cached ? "Cached · \(age)" : "Updated \(age)")
    } else {
      Text("Waiting for GitHub")
    }
  }
}

private struct FooterButton: View {
  let glyph: Glyph?
  var systemImage = "chevron.up"
  let label: String
  var spinning = false
  let action: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      Group {
        if let glyph, spinning {
          // Each turn ends where the next starts, so stopping never rewinds the glyph.
          GlyphView(glyph: glyph, size: 13)
            .phaseAnimator([0.0, 1.0]) { view, turn in
              view.rotationEffect(.degrees(turn * 360))
            } animation: { turn in
              turn == 1 ? .linear(duration: 0.9) : nil
            }
        } else if let glyph {
          GlyphView(glyph: glyph, size: 13)
        } else {
          Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
        }
      }
      .frame(width: 26, height: 24)
      .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(hovered ? 0.08 : 0)))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.white.opacity(hovered ? 0.9 : 0.55))
    .onHover { hovered = $0 }
    .accessibilityLabel(label)
  }
}
