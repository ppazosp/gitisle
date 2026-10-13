import AppKit
import IslandCore
import SwiftUI

struct IslandView: View {
  @Bindable var store: IslandStore
  let metrics: IslandMetrics
  @State private var contentHeight: CGFloat = 220
  /// The widest side of the live pill's content, measured by `CompactBar`.
  @State private var liveSide: CGFloat = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let presentation = store.presentation
    let size = size(for: presentation)
    let ear = metrics.ear(for: presentation)
    let shape = IslandShape(
      ear: ear, radius: metrics.cornerRadius(for: presentation), attached: metrics.hasNotch)
    ZStack(alignment: .top) {
      if presentation == .expanded {
        ExpandedIsland(store: store, metrics: metrics, contentHeight: $contentHeight)
          .transition(.islandContent)
      } else if presentation == .idle {
        // Nothing to show; the island is still a hover and click target.
        Color.clear.contentShape(Rectangle()).onTapGesture { store.expanded = true }
          .accessibilityElement()
          .accessibilityLabel("GitIsle")
          .accessibilityHint("Expands the island")
          .accessibilityAddTraits(.isButton)
      } else {
        VStack(spacing: 0) {
          CompactBar(store: store, metrics: metrics, side: $liveSide)
          if presentation == .banner, let event = store.recentEvent {
            EventBanner(event: event, extra: store.recentEventExtra)
              .transition(.islandContent)
          }
        }
        .transition(.islandContent)
      }
    }
    .padding(.horizontal, ear)
    .frame(width: size.width, height: size.height, alignment: .top)
    .background(.black)
    .clipShape(shape)
    .background {
      shape.fill(.black)
        .shadow(
          color: .black.opacity([.idle, .live].contains(presentation) ? 0 : 0.45), radius: 18,
          y: 10)
    }
    .contentShape(shape)
    .contextMenu {
      Text(
        "GitIsle \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"
      )
      Button("Settings…") { store.openSettings() }
      Divider()
      Button("Quit GitIsle") { NSApp.terminate(nil) }
    }
    .foregroundStyle(.white)
    .environment(\.colorScheme, .dark)
    .onGeometryChange(for: CGSize.self) {
      $0.size
    } action: {
      store.islandSize = $0
    }
    .animation(
      reduceMotion
        ? .easeInOut(duration: 0.15)
        : [.idle, .live].contains(presentation) ? Motion.collapse : Motion.morph,
      value: presentation
    )
    .animation(reduceMotion ? nil : Motion.morph, value: contentHeight)
    .animation(reduceMotion ? nil : Motion.morph, value: liveSide)
    .padding(.top, metrics.topGap)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private func size(for presentation: IslandStore.Presentation) -> CGSize {
    switch presentation {
    case .idle:
      return metrics.idleSize
    case .live:
      return CGSize(
        width: metrics.liveWidth(side: liveSide) + 2 * metrics.ear, height: metrics.closedHeight)
    case .banner:
      let banner = metrics.bannerSize(liveWidth: metrics.liveWidth(side: liveSide))
      return CGSize(width: banner.width + 2 * metrics.ear, height: banner.height)
    case .expanded:
      let chrome = ExpandedIsland.chromeHeight(metrics, store: store)
      let board =
        store.tab == .activity && store.activityLayout == .board && !store.showingSettings
        && !store.showingOnboarding
      let width = board ? metrics.boardWidth(columns: store.sections.count) : metrics.expandedWidth
      return CGSize(
        width: width + 2 * metrics.ear,
        height: min(
          store.tab == .stats && !store.showingSettings && !store.showingOnboarding
            ? metrics.maxStatsHeight : metrics.maxExpandedHeight,
          chrome + contentHeight))
    }
  }
}

// MARK: - Compact

private struct CompactBar: View {
  let store: IslandStore
  let metrics: IslandMetrics
  /// Reports the wider side's natural width, so the island can grow to fit it.
  @Binding var side: CGFloat
  @State private var leadingWidth: CGFloat = 0
  @State private var trailingWidth: CGFloat = 0

  var body: some View {
    Button {
      // The top row is about one PR; clicking opens it. A long hover opens the island.
      if let pr = store.livePullRequest {
        NSWorkspace.shared.open(pr.url)
      } else {
        store.expanded = true
      }
    } label: {
      HStack(spacing: 0) {
        HStack(spacing: 6) { leading }
          .fixedSize()
          .onGeometryChange(for: CGFloat.self) {
            $0.size.width
          } action: { width in
            leadingWidth = width
            side = max(leadingWidth, trailingWidth)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        // Reserved for the camera housing: content is never laid out under the notch.
        Color.clear.frame(width: metrics.liveGap)
        trailing
          .fixedSize()
          .onGeometryChange(for: CGFloat.self) {
            $0.size.width
          } action: { width in
            trailingWidth = width
            side = max(leadingWidth, trailingWidth)
          }
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .font(.system(size: 13, weight: .semibold))
      .monospacedDigit()
      .lineLimit(1)
      .padding(.horizontal, metrics.livePadding)
      .frame(maxWidth: .infinity, minHeight: metrics.closedHeight, maxHeight: metrics.closedHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityText)
    .accessibilityHint(
      store.livePullRequest == nil ? "Expands the island" : "Opens the pull request on GitHub")
  }

  // Icons and numbers only: the closed island is too small for sentences.
  @ViewBuilder private var leading: some View {
    if let first = store.merging.first {
      GlyphView(glyph: .mergeQueue, size: 15).foregroundStyle(Palette.merging)
        .phaseAnimator([1.0, 0.45]) { glyph, opacity in
          glyph.opacity(opacity)
        } animation: { _ in
          .easeInOut(duration: 1.1)
        }
      number(first, more: store.merging.count - 1)
    } else if let first = store.checking.first {
      if let summary = first.checkSummary {
        CheckRing(summary: summary, size: 14, lineWidth: 2.2)
      } else {
        GlyphView(glyph: .clock, size: 14).foregroundStyle(Palette.merging)
      }
      number(first, more: store.checking.count - 1)
    }
  }

  @ViewBuilder private func number(_ pr: PullRequest, more: Int) -> some View {
    Text(verbatim: "#\(pr.number)")
    if more > 0 {
      Text(verbatim: "+\(more)").foregroundStyle(.white.opacity(0.45))
    }
  }

  @ViewBuilder private var trailing: some View {
    if let first = store.merging.first, let since = first.mergingSince {
      // How long the PR has been merging; the system updates the timer without polling.
      Text(since, style: .timer)
        .foregroundStyle(Palette.merging)
        .multilineTextAlignment(.trailing)
        .fixedSize()
    } else if store.merging.isEmpty, let summary = store.checking.first?.checkSummary {
      Text(verbatim: "\(summary.passed)/\(summary.total)")
        .foregroundStyle(.white.opacity(0.6))
        .contentTransition(.numericText(value: Double(summary.passed)))
    }
  }

  private var accessibilityText: String {
    var parts = ["GitIsle"]
    if let pr = store.merging.first { parts.append("pull request \(pr.number) merging") }
    if let pr = store.checking.first { parts.append("checks running on \(pr.number)") }
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
      .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 10)
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
  static let filterBarHeight: CGFloat = 36
  static let footerHeight: CGFloat = 38
  /// Setup's buttons need room to clear the island's rounded bottom corners.
  static let onboardingFooterHeight: CGFloat = 58

  static func footerHeight(_ store: IslandStore) -> CGFloat {
    store.showingOnboarding ? onboardingFooterHeight : footerHeight
  }

  static func chromeHeight(_ metrics: IslandMetrics, store: IslandStore) -> CGFloat {
    topInset(metrics) + headerHeight + (showsFilterBar(store) ? filterBarHeight : 0)
      + footerHeight(store) + 1
  }

  /// State filters belong to Activity, in both layouts.
  static func showsFilterBar(_ store: IslandStore) -> Bool {
    store.tab == .activity && !store.showingSettings && !store.showingOnboarding
  }

  static func topInset(_ metrics: IslandMetrics) -> CGFloat {
    metrics.hasNotch ? metrics.notchHeight + 4 : 10
  }

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(.top, Self.topInset(metrics))
        .frame(height: Self.topInset(metrics) + Self.headerHeight, alignment: .bottom)
      if Self.showsFilterBar(store) {
        StateFilterBar(store: store)
          .padding(.horizontal, 28)
          .frame(height: Self.filterBarHeight, alignment: .top)
          .transition(.opacity)
      }
      Rectangle().fill(Palette.hairline).frame(height: 1).padding(.horizontal, 28)
      Group {
        if store.showingOnboarding {
          OnboardingView(store: store, contentHeight: $contentHeight)
        } else if store.showingSettings {
          SettingsView(store: store, contentHeight: $contentHeight)
        } else {
          switch store.tab {
          case .activity: ActivityView(store: store, contentHeight: $contentHeight)
          case .stats: StatsView(store: store, contentHeight: $contentHeight)
          }
        }
      }
      .id(
        store.showingOnboarding
          ? "onboarding" : store.showingSettings ? "settings" : store.tab.rawValue
      )
      .transition(.opacity.animation(.easeOut(duration: 0.12)))
      .frame(maxHeight: .infinity, alignment: .top)
      Group {
        if store.showingOnboarding {
          OnboardingFooter(store: store)
        } else {
          footer
        }
      }
      .frame(height: Self.footerHeight(store))
    }
  }

  @ViewBuilder private var header: some View {
    if store.showingOnboarding {
      HStack(spacing: 10) {
        Text("Set up GitIsle").font(.system(size: 14, weight: .semibold))
        Spacer()
        OnboardingProgress(step: store.onboardingStep)
      }
      .padding(.horizontal, 28)
      .frame(height: Self.headerHeight)
    } else if store.showingSettings {
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
        RepositoryMenu(store: store)
        PillPicker(
          options: ActivityWindow.allCases.map { ($0, $0.label) },
          selection: $store.activityWindow, fontSize: 11)
        LayoutToggle(layout: $store.activityLayout)
      case .stats:
        PillPicker(
          options: [(1, "Today"), (7, "7 days"), (30, "30 days")],
          selection: $store.usageDays, fontSize: 11)
      }
    }
    .padding(.horizontal, 28)
    .frame(height: Self.headerHeight)
  }

  /// Refresh sits with the status it updates; settings and app updates sit on the right.
  private var footer: some View {
    HStack(spacing: 4) {
      FooterButton(glyph: .sync, label: "Refresh", spinning: refreshing) {
        Task {
          async let github: Void = store.refreshGitHub()
          async let usage: Void = store.refreshUsage()
          async let stats: Void = store.refreshStats()
          _ = await (github, usage, stats)
        }
      }
      .disabled(refreshing || store.isDemo)
      status.font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
      Spacer()
      FooterButton(glyph: .gear, label: "GitIsle settings") {
        withAnimation(Motion.snappy) { store.showingSettings.toggle() }
      }
      if let release = store.updater.available {
        FooterButton(
          glyph: .download, label: "Update to GitIsle \(release.version)", tint: Palette.update
        ) {
          if !store.isDemo { store.updater.install() }
        }
        .disabled(store.updater.installing)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
      }
    }
    .padding(.horizontal, 18)
    .animation(Motion.snappy, value: store.updater.available)
  }

  private var refreshing: Bool { store.githubRefreshing || store.usageRefreshing }

  @ViewBuilder private var status: some View {
    if let release = store.updater.available, store.updater.installing {
      Text("Updating to \(release.version)…")
    } else if let error = store.updater.error {
      Text(error).foregroundStyle(Palette.failed)
    } else if store.isDemo {
      // Marketing captures can relabel the example data, for example "Updated just now".
      Text(ProcessInfo.processInfo.environment["GITISLE_PREVIEW_LABEL"] ?? "Example data")
    } else if let github = store.github {
      let age = github.fetchedAt.formatted(.relative(presentation: .named))
      Text(store.cached ? "Cached · \(age)" : "Updated \(age)")
    } else {
      Text("Waiting for GitHub")
    }
  }
}

/// Limits Activity to one repository.
private struct RepositoryMenu: View {
  let store: IslandStore

  var body: some View {
    Menu {
      Button("All repositories") { store.repositoryFilter = nil }
      Divider()
      ForEach(store.repositoryChoices, id: \.name) { choice in
        Button(choice.name) { store.repositoryFilter = choice.name }
      }
    } label: {
      HStack(spacing: 6) {
        if let selected = store.repositoryFilter {
          RepoAvatar(
            url: store.repositoryChoices.first { $0.name == selected }?.avatar, size: 14)
          Text(verbatim: selected.split(separator: "/").last.map(String.init) ?? selected)
            .lineLimit(1).frame(maxWidth: 110, alignment: .leading)
        } else {
          GlyphView(glyph: .repo, size: 12)
          Text("All repos")
        }
        GlyphView(glyph: .chevronDown, size: 10).foregroundStyle(.white.opacity(0.5))
      }
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(.white.opacity(store.repositoryFilter == nil ? 0.6 : 0.95))
      .padding(.horizontal, 10).padding(.vertical, 5)
      .background(Capsule().fill(.white.opacity(store.repositoryFilter == nil ? 0.06 : 0.14)))
      .contentShape(Capsule())
    }
    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    .accessibilityLabel("Repository filter")
  }
}

/// Switches Activity between the repository list and the state board.
private struct LayoutToggle: View {
  @Binding var layout: IslandStore.ActivityLayout
  @Namespace private var namespace

  var body: some View {
    HStack(spacing: 0) {
      ForEach(
        [(IslandStore.ActivityLayout.list, Glyph.list, "List"), (.board, .board, "Board")],
        id: \.0
      ) { option, glyph, label in
        let selected = option == layout
        Button {
          withAnimation(Motion.morph) { layout = option }
        } label: {
          GlyphView(glyph: glyph, size: 12)
            .foregroundStyle(.white.opacity(selected ? 1 : 0.5))
            .frame(width: 28, height: 22)
            .background {
              if selected {
                Capsule().fill(.white.opacity(0.14))
                  .matchedGeometryEffect(id: "layout", in: namespace)
              }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
    .padding(2)
    .background(Capsule().fill(.white.opacity(0.06)))
  }
}

private struct FooterButton: View {
  let glyph: Glyph?
  var systemImage = "chevron.up"
  let label: String
  var spinning = false
  /// Colors the button to stand out, for something waiting on you.
  var tint: Color?
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
      .background(
        RoundedRectangle(cornerRadius: 6).fill(
          tint.map { $0.opacity(hovered ? 0.3 : 0.18) } ?? .white.opacity(hovered ? 0.08 : 0))
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(tint ?? .white.opacity(hovered ? 0.9 : 0.55))
    .onHover { hovered = $0 }
    .help(label)
    .accessibilityLabel(label)
  }
}
