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
        && !store.showingOnboarding && store.detailsPullRequest == nil
      let details =
        store.tab == .activity && store.detailsPullRequest != nil && !store.showingSettings
        && !store.showingOnboarding
      let width =
        store.showingSettings && !store.showingOnboarding
        ? metrics.settingsWidth
        : board
          ? metrics.boardWidth(columns: store.sections.count)
          : details ? metrics.detailsWidth : metrics.expandedWidth
      // Stats and Settings grow with the screen, so their cards fit without scrolling.
      let tall =
        store.showingSettings
        || (store.tab == .stats && !store.showingOnboarding)
      return CGSize(
        width: width + 2 * metrics.ear,
        height: min(
          tall ? metrics.maxStatsHeight : metrics.maxExpandedHeight,
          chrome + max(contentHeight, ExpandedIsland.repositoryPickerHeight(store))))
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
    if let first = store.merging.first {
      HStack(spacing: 6) {
        // The merge queue's checks, as the ring shows the PR's own while they run.
        if let queue = first.queueChecks { CheckRing(summary: queue, size: 14, lineWidth: 2.2) }
        if let since = first.mergingSince {
          // How long the PR has been merging; the system updates the timer without polling.
          Text(since, style: .timer)
            .foregroundStyle(Palette.merging)
            .multilineTextAlignment(.trailing)
            .fixedSize()
        } else if let queue = first.queueChecks {
          Text(verbatim: "\(queue.passed)/\(queue.total)").foregroundStyle(.white.opacity(0.6))
        }
      }
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
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(reference).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
          }
          Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
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
    .accessibilityLabel("\(title): \(event.detail)")
    .accessibilityHint("Opens the pull request on GitHub")
  }

  /// "Checks failed: unit" when the failing checks are known; other notes, such as the projects
  /// behind a preview, lead the second line instead.
  private var title: String {
    guard event.kind == .failed, let note = event.note else { return event.kind.eventTitle }
    return "\(event.kind.eventTitle): \(note)"
  }

  private var detail: String {
    guard event.kind != .failed, let note = event.note else { return event.detail }
    return "\(note) · \(event.detail)"
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
  /// Setup's buttons are taller than the footer's icons and need room to clear the
  /// island's rounded bottom corners.
  static let onboardingFooterHeight: CGFloat = 46

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
      && store.detailsPullRequest == nil
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
        } else if store.tab == .activity, let pr = store.detailsPullRequest {
          PRDetailsView(store: store, pr: pr, contentHeight: $contentHeight)
        } else {
          switch store.tab {
          case .activity: ActivityView(store: store, contentHeight: $contentHeight)
          case .stats: StatsView(store: store, contentHeight: $contentHeight)
          }
        }
      }
      .id(
        store.showingOnboarding
          ? "onboarding"
          : store.showingSettings
            ? "settings" : store.detailsPullRequest.map { "pr-\($0.id)" } ?? store.tab.rawValue
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
    .overlayPreferenceValue(RepositoryButtonBounds.self) { anchor in
      GeometryReader { proxy in
        if Self.showsRepositoryPicker(store), let anchor {
          let button = proxy[anchor]
          ZStack(alignment: .topLeading) {
            // A click anywhere else closes the picker without acting on what's under it.
            Color.black.opacity(0.001).contentShape(Rectangle())
              .onTapGesture { withAnimation(Motion.snappy) { store.repositoryPickerOpen = false } }
            RepositoryPicker(store: store)
              .offset(
                x: min(max(button.minX, 12), proxy.size.width - RepositoryPicker.width - 12),
                y: button.maxY + 6)
          }
          .transition(.opacity)
        }
      }
    }
    .overlay {
      GeometryReader { proxy in
        if let dropdown = store.dropdown {
          let placement = dropdown.placement
          let size = proxy.size
          ZStack(alignment: .topLeading) {
            // A click anywhere else closes the dropdown without acting on what's under it.
            Color.black.opacity(0.001).contentShape(Rectangle())
              .onTapGesture { withAnimation(Motion.snappy) { store.dropdown = nil } }
            DropdownMenu(dropdown: dropdown) {
              withAnimation(Motion.snappy) { store.dropdown = nil }
            }
            // Placed by its own size, so it lines up with its control however wide it is.
            .alignmentGuide(.leading) { -placement.x(width: $0.width, in: size) }
            .alignmentGuide(.top) { -placement.y(height: $0.height, in: size) }
            .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
          }
          .transition(.opacity)
        }
      }
    }
    .coordinateSpace(.named(Dropdown.space))
    .environment(store)
  }

  /// The picker belongs to Activity; leaving it hides the picker.
  static func showsRepositoryPicker(_ store: IslandStore) -> Bool {
    store.repositoryPickerOpen && showsFilterBar(store)
  }

  /// Content height the island needs so the open picker isn't cut off by its bottom edge.
  static func repositoryPickerHeight(_ store: IslandStore) -> CGFloat {
    guard showsRepositoryPicker(store) else { return 0 }
    return RepositoryPicker.height(repositories: store.repositoryChoices.count) - 60
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
    } else if store.tab == .activity, let pr = store.detailsPullRequest {
      HStack(spacing: 10) {
        FooterButton(glyph: nil, systemImage: "chevron.left", label: "Back") {
          withAnimation(Motion.snappy) { store.closeDetails() }
        }
        RepoAvatar(url: pr.ownerAvatar, size: 20)
        let owner = pr.repository.split(separator: "/").first.map { "\($0)/" } ?? ""
        let name = pr.repository.split(separator: "/").last.map(String.init) ?? pr.repository
        (Text(verbatim: owner).foregroundStyle(.white.opacity(0.5)) + Text(verbatim: name))
          .font(.system(size: 14, weight: .semibold)).lineLimit(1)
        HStack(spacing: 5) {
          GlyphView(glyph: pr.glyph, size: 13).foregroundStyle(pr.glyphColor)
          Text(verbatim: "#\(pr.number)").monospacedDigit()
        }
        .font(.system(size: 14, weight: .semibold)).fixedSize()
        Spacer()
        HStack(spacing: 4) {
          ShareButton(store: store, pr: pr)
          PreviewButton(
            previews: store.pullRequestDetails[pr.id]?.previews ?? pr.previews ?? [])
          FooterButton(glyph: .github, label: "Open on GitHub") {
            NSWorkspace.shared.open(pr.url)
          }
        }
      }
      .padding(.leading, 22).padding(.trailing, 22)
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
        RepositoryButton(store: store)
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
    if let note = store.footerNote {
      Text(note).foregroundStyle(.white.opacity(0.75))
    } else if let release = store.updater.available, store.updater.installing {
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

/// Opens the repository picker, and says which repositories the island is limited to.
private struct RepositoryButton: View {
  @Bindable var store: IslandStore
  @State private var hovered = false

  var body: some View {
    let filter = store.repositoryFilter
    Button {
      withAnimation(Motion.snappy) { store.repositoryPickerOpen.toggle() }
    } label: {
      HStack(spacing: 6) {
        if filter.count == 1, let selected = filter.first {
          RepoAvatar(
            url: store.repositoryChoices.first { $0.name == selected }?.avatar, size: 14)
          Text(verbatim: selected.split(separator: "/").last.map(String.init) ?? selected)
            .lineLimit(1).frame(maxWidth: 110, alignment: .leading)
        } else {
          GlyphView(glyph: .repo, size: 12)
          Text(filter.isEmpty ? "All repos" : "\(filter.count) repos")
        }
        GlyphView(glyph: .chevronDown, size: 10).foregroundStyle(.white.opacity(0.5))
          .rotationEffect(.degrees(store.repositoryPickerOpen ? 180 : 0))
      }
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(.white.opacity(filter.isEmpty ? 0.6 : 0.95))
      .padding(.horizontal, 10).padding(.vertical, 5)
      .background(
        Capsule().fill(
          .white.opacity(
            filter.isEmpty && !store.repositoryPickerOpen ? (hovered ? 0.1 : 0.06) : 0.14))
      )
      .contentShape(Capsule())
    }
    .buttonStyle(.plain).fixedSize()
    .onHover { hovered = $0 }
    .anchorPreference(key: RepositoryButtonBounds.self, value: .bounds) { $0 }
    .accessibilityLabel("Repository filter")
    .accessibilityValue(
      filter.isEmpty ? "All repositories" : filter.sorted().joined(separator: ", "))
  }
}

/// Where the repository button sits, so the picker opens right under it.
struct RepositoryButtonBounds: PreferenceKey {
  static let defaultValue: Anchor<CGRect>? = nil
  static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
    value = value ?? nextValue()
  }
}

/// Limits the island to some repositories. Each row toggles one, so several can be chosen;
/// the list scrolls past `maxRows`.
struct RepositoryPicker: View {
  let store: IslandStore

  static let rowHeight: CGFloat = 30
  static let maxRows = 7
  static let width: CGFloat = 270
  static let padding: CGFloat = 6

  /// The picker's height for this many repositories.
  static func height(repositories: Int) -> CGFloat {
    padding * 2 + rowHeight + 9 + CGFloat(min(max(repositories, 1), maxRows)) * rowHeight
  }

  var body: some View {
    VStack(spacing: 0) {
      PickerRow(selected: store.repositoryFilter.isEmpty) {
        GlyphView(glyph: .repo, size: 14).frame(width: 16)
        Text("All repositories")
      } action: {
        store.repositoryFilter = []
      }
      Rectangle().fill(Palette.hairline).frame(height: 1).padding(.vertical, 4)
      ScrollView {
        VStack(spacing: 0) {
          ForEach(store.repositoryChoices, id: \.name) { choice in
            PickerRow(selected: store.repositoryFilter.contains(choice.name)) {
              RepoAvatar(url: choice.avatar, size: 16)
              (Text(verbatim: owner(choice.name)).foregroundStyle(.white.opacity(0.45))
                + Text(verbatim: name(choice.name)))
                .lineLimit(1).truncationMode(.middle)
            } action: {
              if store.repositoryFilter.remove(choice.name) == nil {
                store.repositoryFilter.insert(choice.name)
              }
            }
          }
        }
      }
      .scrollIndicators(.automatic)
      .frame(
        height: CGFloat(min(max(store.repositoryChoices.count, 1), Self.maxRows)) * Self.rowHeight
      )
    }
    .padding(Self.padding)
    .frame(width: Self.width)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.1)))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline)
    )
    .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Repositories")
  }

  private func owner(_ repository: String) -> String {
    repository.split(separator: "/").first.map { "\($0)/" } ?? ""
  }

  private func name(_ repository: String) -> String {
    repository.split(separator: "/").last.map(String.init) ?? repository
  }
}

struct PickerRow<Label: View>: View {
  let selected: Bool
  /// Keeps room for the checkmark, for rows that show a choice.
  var checkable = true
  @ViewBuilder let label: Label
  let action: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        label
        Spacer(minLength: checkable ? 8 : 0)
        if checkable {
          Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
            .opacity(selected ? 1 : 0)
        }
      }
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(.white.opacity(selected ? 1 : 0.8))
      .padding(.horizontal, 8)
      .frame(height: RepositoryPicker.rowHeight)
      .background(
        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(
          .white.opacity(hovered ? 0.08 : 0))
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovered = $0 }
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
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

struct FooterButton: View {
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

/// Opens the system share menu for a PR's share card and link.
private struct ShareButton: View {
  let store: IslandStore
  let pr: PullRequest
  @State private var anchor = ViewAnchor()

  var body: some View {
    FooterButton(glyph: nil, systemImage: "square.and.arrow.up", label: "Share") {
      Task { await share() }
    }
    .background(AnchorView(anchor: anchor))
  }

  private func share() async {
    var items: [Any] = [pr.url]
    // The share menu ignores an image next to a link, but takes an image file.
    if let file = await store.shareCardFile(for: pr) { items.insert(file, at: 0) }
    guard let view = anchor.view else { return }
    NSSharingServicePicker(items: items).show(
      relativeTo: view.bounds, of: view, preferredEdge: .minY)
  }
}

/// The view a share menu opens from.
@MainActor private final class ViewAnchor {
  weak var view: NSView?
}

private struct AnchorView: NSViewRepresentable {
  let anchor: ViewAnchor

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    anchor.view = view
    return view
  }

  func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
}

/// Opens the PR's preview deploy. A dot shows its state: green ready, amber building, red
/// failed. Several projects open as a dropdown.
private struct PreviewButton: View {
  let previews: [PreviewDeploy]

  var body: some View {
    if let first = previews.first {
      Group {
        if previews.count == 1 {
          FooterButton(glyph: nil, systemImage: "globe", label: label(first)) {
            if let url = first.url { NSWorkspace.shared.open(url) }
          }
          .disabled(first.url == nil)
        } else {
          DropdownButton(id: "pr-previews", trailing: true) {
            [
              Dropdown.Section(
                id: "previews", title: nil,
                items: previews.map { preview in
                  Dropdown.Item(
                    id: preview.name, title: label(preview), systemImage: "globe",
                    enabled: preview.url != nil
                  ) {
                    if let url = preview.url { NSWorkspace.shared.open(url) }
                  }
                })
            ]
          } label: {
            Image(systemName: "globe").font(.system(size: 11, weight: .semibold))
              .frame(width: 26, height: 24).contentShape(Rectangle())
          }
          .fixedSize()
          .foregroundStyle(.white.opacity(0.55))
          .help("Previews")
        }
      }
      .overlay(alignment: .bottomTrailing) {
        Circle().fill(color(previews)).frame(width: 6, height: 6)
          .background(Circle().fill(.black).padding(-1.5))
          .offset(x: -5, y: -4)
          .allowsHitTesting(false)
      }
    }
  }

  private func label(_ preview: PreviewDeploy) -> String {
    switch preview.state {
    case .ready: "Open \(preview.name) preview"
    case .building: "\(preview.name) preview is building"
    case .failed: "\(preview.name) preview failed"
    }
  }

  /// Failed wins, then building, so the dot never hides a problem.
  private func color(_ previews: [PreviewDeploy]) -> Color {
    if previews.contains(where: { $0.state == .failed }) { return Palette.failed }
    if previews.contains(where: { $0.state == .building }) { return Palette.merging }
    return Palette.open
  }
}
