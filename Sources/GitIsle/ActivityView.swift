import AppKit
import IslandCore
import SwiftUI

extension EnvironmentValues {
  @Entry var activityHeightLimit: CGFloat = .infinity
}

private let activityListInsets = EdgeInsets(top: 8, leading: 14, bottom: 4, trailing: 14)
private let activityPreviewLimit = 8

struct ActivityView: View {
  let store: IslandStore
  @Binding var contentHeight: CGFloat
  @Environment(\.activityHeightLimit) private var heightLimit

  var body: some View {
    Group {
      switch store.activityLayout {
      case .list:
        ActivityList(store: store, contentHeight: $contentHeight, heightLimit: heightLimit)
      case .board:
        BoardView(store: store, contentHeight: $contentHeight, heightLimit: heightLimit)
      }
    }
    // Lay out the new content once. The island animates to that size.
    .transaction(
      value: ActivityFilters(
        layout: store.activityLayout, states: store.stateFilter, query: store.activityQuery,
        repositories: store.repositoryFilter, window: store.activityWindow)
    ) { transaction in
      transaction.animation = nil
      transaction.disablesAnimations = true
    }
    .environment(\.openPullRequest) { pr in
      withAnimation(Motion.snappy) { store.openDetails(pr) }
    }
    .environment(\.stackLinks, store.stackLinks)
    .environment(store)
  }
}

private struct ActivityList: View {
  let store: IslandStore
  @Binding var contentHeight: CGFloat
  let heightLimit: CGFloat
  @State private var showsAllPRs = false

  private enum Row: Identifiable {
    enum ID: Hashable {
      case header(String)
      case pile(String)
    }

    case header(RepoSection, collapsed: Bool, separated: Bool)
    case pile([PullRequest], bottom: PullRequest, trailingSpace: Bool)

    var id: ID {
      switch self {
      case .header(let section, _, _): .header(section.id)
      case .pile(_, let bottom, _): .pile(bottom.id)
      }
    }
  }

  var body: some View {
    let sections = store.repositories.enumerated().map { index, section in
      self.rows(for: section, separated: index > 0)
    }
    let rows = sections.flatMap(\.rows)
    let hasHiddenPRs = sections.contains { $0.hasHiddenPRs }
    let hasExpandedRepo = store.repositories.contains {
      !store.collapsedRepositories.contains($0.id)
    }
    // Count only the rows that are actually shown. At this lower bound the list
    // already fills the island, so it can scroll without measuring every row.
    let rowCount = rows.reduce(0) { count, row in
      switch row {
      case .header: count + 1
      case .pile(let pile, let bottom, _):
        count + (store.foldedStacks.contains(bottom.id) ? 1 : pile.count)
      }
    }
    MeasuredColumn(fixedHeight: CGFloat(rowCount) * 36 >= heightLimit ? heightLimit : nil) {
      LazyVStack(alignment: .leading, spacing: 0) {
        notices
        if store.github != nil && store.repositories.isEmpty {
          ActivityEmptyState(store: store)
        }
        ForEach(rows) { item in
          // One view per item gives the lazy stack stable scroll positions across repositories.
          VStack(spacing: 0) { row(item) }
        }
        if hasExpandedRepo && (hasHiddenPRs || store.canLoadMorePRs()) {
          MorePRsRow(store: store, hasHiddenPRs: hasHiddenPRs) {
            withAnimation(Motion.snappy) { showsAllPRs = true }
          }
          .padding(.horizontal, 8).padding(.bottom, 4)
        }
      }
      .padding(activityListInsets)
    } onHeight: {
      contentHeight = $0
    }
    .animation(Motion.snappy, value: store.repositories)
  }

  private func rows(for section: RepoSection, separated: Bool) -> (
    rows: [Row], hasHiddenPRs: Bool
  ) {
    let collapsed = store.collapsedRepositories.contains(section.id)
    var rows: [Row] = [.header(section, collapsed: collapsed, separated: separated)]
    guard !collapsed else { return (rows, false) }
    let piles = PRStacks.piles(section.pullRequests, links: store.stackLinks)
    var shownByState: [PRGroup: Int] = [:]
    let visible =
      showsAllPRs
      ? piles
      : piles.filter { pile in
        guard let state = pile.first?.group else { return false }
        shownByState[state, default: 0] += 1
        return shownByState[state, default: 0] <= activityPreviewLimit
      }
    for (index, pile) in visible.enumerated() {
      if let bottom = pile.first {
        rows.append(
          .pile(pile, bottom: bottom, trailingSpace: index == visible.count - 1))
      }
    }
    return (rows, visible.count < piles.count)
  }

  @ViewBuilder private func row(_ item: Row) -> some View {
    switch item {
    case .header(let section, let collapsed, let separated):
      RepositoryHeader(section: section, collapsed: collapsed, separated: separated) {
        withAnimation(Motion.snappy) { store.toggleCollapsed(section.id) }
      }
    case .pile(let pile, let bottom, let trailingSpace):
      Group {
        if pile.count > 1 {
          ListStack(pile: pile, unfolded: !store.foldedStacks.contains(bottom.id)) {
            withAnimation(Motion.snappy) { store.toggleStack(bottom.id) }
          }
        } else {
          PRRow(pr: bottom)
        }
      }
      .padding(.bottom, trailingSpace ? 8 : 0)
      .transition(.opacity)
    }
  }

  @ViewBuilder private var notices: some View {
    if let error = store.githubError {
      Notice(text: error)
    }
  }
}

private struct ActivityFilters: Equatable {
  let layout: IslandStore.ActivityLayout
  let states: Set<PRGroup>
  let query: String
  let repositories: Set<String>
  let window: ActivityWindow
}

private struct Notice: View {
  let text: String
  var body: some View {
    Text(text).font(.system(size: 11)).foregroundStyle(Palette.attention)
      .textSelection(.enabled)
      .padding(10).frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 10).fill(Palette.attention.opacity(0.1)))
      .padding(.vertical, 6)
  }
}

private struct ActivityEmptyState: View {
  let store: IslandStore

  var body: some View {
    let searching = !store.activityQuery.isEmpty
    VStack(spacing: 0) {
      Group {
        if searching {
          Label("No matching PRs", systemImage: "xmark.circle")
            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.58))
        } else {
          HStack(spacing: 8) {
            GlyphView(glyph: .checkFill, size: 14).foregroundStyle(Palette.open)
            Text(emptyMessage)
              .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.7))
          }
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, searching ? 18 : 22)
      if store.canLoadMorePRs() {
        MorePRsRow(store: store)
          .padding(.horizontal, 8)
          .padding(.vertical, 5)
      }
    }
  }

  private var emptyMessage: String {
    if !store.stateFilter.isEmpty { return "No PRs match these filters" }
    return store.activityWindow == .all ? "You're all caught up" : "No PRs in this date range"
  }
}

private struct MorePRsRow: View {
  let store: IslandStore
  var group: PRGroup?
  var hasHiddenPRs = false
  var reveal: (() -> Void)?
  @State private var hovered = false

  var body: some View {
    let loading = store.loadingMorePRs && !hasHiddenPRs
    VStack(spacing: 4) {
      Button {
        reveal?()
        if !hasHiddenPRs { Task { await store.loadMorePRs(in: group) } }
      } label: {
        HStack(spacing: 6) {
          Text(loading ? "Loading…" : "Load more PRs").lineLimit(1)
          if loading {
            ProgressView().controlSize(.mini)
          } else {
            GlyphView(glyph: .chevronDown, size: 9)
          }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(hovered ? 0.95 : 0.7))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(hovered ? 0.06 : 0)))
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .onHover { hovered = $0 }
      .disabled(!hasHiddenPRs && store.githubRefreshing)
      .help(
        hasHiddenPRs ? "Show more loaded pull requests" : "Fetch more pull requests from GitHub")
      if !hasHiddenPRs, let error = store.morePRsError {
        Text(error).font(.system(size: 11)).foregroundStyle(Palette.attention)
          .lineLimit(2)
      }
    }
    .frame(maxWidth: .infinity)
  }
}

/// Summarizes a repository's PR states and toggles its section.
private struct RepositoryHeader: View {
  let section: RepoSection
  let collapsed: Bool
  let separated: Bool
  let toggle: () -> Void
  @State private var hovered = false

  var body: some View {
    VStack(spacing: 0) {
      if separated {
        Rectangle().fill(Palette.hairline).frame(height: 1).padding(.horizontal, 8)
      }
      HStack(spacing: 9) {
        RepoAvatar(url: section.avatar)
        (Text(verbatim: "\(section.owner)/").foregroundStyle(.white.opacity(0.45))
          + Text(verbatim: section.name).foregroundStyle(.white))
          .font(.system(size: 13, weight: .semibold)).lineLimit(1)
        Spacer(minLength: 12)
        ForEach(PRGroup.boardOrder, id: \.self) { group in
          if let item = section.counts.first(where: { $0.group == group }) {
            HStack(spacing: 4) {
              GlyphView(glyph: group.glyph, size: 11)
              Text("\(item.count)").monospacedDigit()
                .contentTransition(.numericText(value: Double(item.count)))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(group.color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(group.color.opacity(0.13)))
            .help("\(item.count) \(group.label.lowercased())")
          }
        }
        GlyphView(glyph: .chevronDown, size: 12).foregroundStyle(.white.opacity(0.45))
          .rotationEffect(.degrees(collapsed ? -90 : 0))
          .padding(.leading, 2)
      }
      .padding(.horizontal, 10).padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(.white.opacity(hovered ? 0.06 : 0))
      )
      .contentShape(Rectangle())
      .onTapGesture(perform: toggle)
      .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
      .accessibilityElement(children: .contain)
      .accessibilityLabel(
        "\(section.repository), \(section.pullRequests.count) pull requests, "
          + (collapsed ? "collapsed" : "expanded")
      )
      .accessibilityAction(named: collapsed ? "Expand" : "Collapse", toggle)
    }
  }
}

/// State filters shared by List and Board. Click to toggle, or secondary-click to isolate.
struct StateFilterBar: View {
  @Bindable var store: IslandStore

  var body: some View {
    let canIsolate =
      !store.repositoryPickerOpen && store.dropdown == nil && store.checksPreview == nil
    HStack(spacing: 6) {
      ActivitySearchField(query: $store.activitySearch, expanded: store.expanded)
      Rectangle().fill(Palette.hairline).frame(width: 1, height: 16).padding(.horizontal, 2)
      ForEach(PRGroup.boardOrder, id: \.self) { group in
        let count = store.stateCounts.first { $0.group == group }?.count ?? 0
        let selected = store.stateFilter.contains(group)
        let capped =
          group == .merged && store.activityWindow == .all && store.activityQuery.isEmpty
          && store.repositoryFilter.isEmpty && store.github?.mergedHistory?.nextCursor != nil
        StateChip(
          group: group, count: count, capped: capped, selected: selected,
          dimmed: !store.stateFilter.isEmpty && !selected,
          action: { store.toggleState(group) },
          isolate: canIsolate ? { store.stateFilter = [group] } : nil)
      }
      Spacer(minLength: 4)
      if !store.stateFilter.isEmpty {
        Button {
          store.stateFilter = []
        } label: {
          Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.6))
            .frame(width: 20, height: 20)
            .background(Circle().fill(.white.opacity(0.08)))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Clear filters")
        .accessibilityLabel("Clear filters")
        .transition(.opacity)
      }
    }
    .animation(Motion.snappy, value: store.stateFilter)
  }
}

private struct ActivitySearchField: View {
  @Binding var query: String
  let expanded: Bool
  @State private var focus = ActivitySearchFocus()
  @State private var hovered = false

  var body: some View {
    let capsule = Capsule()
    HStack(spacing: 6) {
      Button {
        focus.beginEditing()
      } label: {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 11, weight: .medium))
      }
      .buttonStyle(.plain)
      .accessibilityHidden(true)
      NativeActivitySearchInput(query: $query, focus: focus, expanded: expanded)
        .frame(height: 15)
      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 10))
            .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear search")
      }
    }
    .font(.system(size: 11, weight: .medium))
    .foregroundStyle(.white.opacity(0.6))
    .padding(.horizontal, 10)
    .frame(width: 130, height: 24)
    .background(capsule.fill(.white.opacity(query.isEmpty ? hovered ? 0.1 : 0.06 : 0.14)))
    .background {
      ActivitySearchRegion()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    .contentShape(capsule)
    .onHover { hovered = $0 }
  }
}

@MainActor private final class ActivitySearchFocus {
  weak var field: NSTextField?

  func beginEditing() {
    guard let field, let window = field.window else { return }
    window.makeKey()
    window.makeFirstResponder(field)
  }
}

final class ActivitySearchTextField: NSTextField {
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    (window as? IslandPanel)?.activitySearchField = self
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if window !== newWindow {
      endSearchEditing()
      if let panel = window as? IslandPanel, panel.activitySearchField === self {
        panel.activitySearchField = nil
      }
    }
    super.viewWillMove(toWindow: newWindow)
  }

  func endSearchEditing() {
    guard let window else { return }
    if let editor = currentEditor() {
      if window.firstResponder === editor { window.makeFirstResponder(nil) }
      if currentEditor() === editor { window.endEditing(for: self) }
    }
    if window.firstResponder === self { window.makeFirstResponder(nil) }
  }
}

private struct NativeActivitySearchInput: NSViewRepresentable {
  @Binding var query: String
  let focus: ActivitySearchFocus
  let expanded: Bool

  func makeCoordinator() -> Coordinator { Coordinator(query: $query) }

  func makeNSView(context: Context) -> ActivitySearchTextField {
    let field = ActivitySearchTextField()
    let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    field.isEditable = true
    field.isSelectable = true
    field.isBordered = false
    field.isBezeled = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.cell?.usesSingleLineMode = true
    field.font = font
    field.textColor = .white.withAlphaComponent(0.95)
    field.placeholderAttributedString = NSAttributedString(
      string: "Title, repo, #123",
      attributes: [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.6)])
    field.setAccessibilityLabel("Search pull requests")
    field.setAccessibilityHelp("Search by pull request title, repository, or number")
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    field.delegate = context.coordinator
    focus.field = field
    return field
  }

  func updateNSView(_ field: ActivitySearchTextField, context: Context) {
    context.coordinator.query = $query
    if let editor = field.currentEditor() {
      if editor.string != query { editor.string = query }
    } else if field.stringValue != query {
      field.stringValue = query
    }
    if !expanded { field.endSearchEditing() }
  }

  static func dismantleNSView(_ field: ActivitySearchTextField, coordinator: Coordinator) {
    field.endSearchEditing()
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var query: Binding<String>

    init(query: Binding<String>) {
      self.query = query
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      query.wrappedValue = field.stringValue
    }
  }
}

/// Give the panel the whole capsule's bounds, including the search and clear buttons.
private struct ActivitySearchRegion: NSViewRepresentable {
  func makeNSView(context: Context) -> ClickArea { ClickArea() }
  func updateNSView(_ view: ClickArea, context: Context) {}

  final class ClickArea: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      (window as? IslandPanel)?.activitySearchRegion = self
    }
  }
}

private struct StateChip: View {
  let group: PRGroup
  let count: Int
  var capped = false
  let selected: Bool
  let dimmed: Bool
  let action: () -> Void
  let isolate: (() -> Void)?
  @State private var hovered = false

  var body: some View {
    let capsule = Capsule(style: .circular)
    Button(action: action) {
      HStack(spacing: 5) {
        GlyphView(glyph: group.glyph, size: 11)
        Text(group.label).lineLimit(1).fixedSize()
        Text(capped ? "\(count)+" : "\(count)").monospacedDigit().opacity(0.7)
          .lineLimit(1).fixedSize()
          .contentTransition(.numericText(value: Double(count)))
      }
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(group.color)
      .padding(.horizontal, 8).padding(.vertical, 4)
      .background(
        capsule.fill(group.color.opacity(hovered ? 0.2 : 0.11))
      )
      .overlay {
        if selected {
          capsule.strokeBorder(group.color.opacity(0.9), lineWidth: 1)
        }
      }
      .opacity(dimmed && !hovered ? 0.58 : 1)
      .contentShape(capsule)
    }
    .buttonStyle(.plain)
    .overlay {
      if let isolate {
        StateChipSecondaryClick(action: isolate)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
    }
    .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
    .help(helpText)
    .accessibilityLabel("\(group.label), \(count)")
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    .accessibilityActions {
      if let isolate {
        Button("Show only \(group.label)", action: isolate)
      }
    }
  }

  private var helpText: String {
    let state = group.label.lowercased()
    let toggle = selected ? "Click to remove \(state)." : "Click to include \(state)."
    return isolate == nil ? toggle : "\(toggle) Right-click to show only \(state)."
  }
}

/// Handles a secondary click before the island's context menu sees it.
private struct StateChipSecondaryClick: NSViewRepresentable {
  let action: () -> Void

  func makeNSView(context: Context) -> ClickArea { ClickArea() }

  func updateNSView(_ view: ClickArea, context: Context) { view.action = action }

  static func dismantleNSView(_ view: ClickArea, coordinator: ()) { view.stopMonitoring() }

  final class ClickArea: NSView {
    var action: (() -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      stopMonitoring()
      guard window != nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) {
        [weak self] event in
        guard let self, let window, event.window === window, let action,
          event.type == .rightMouseDown || event.modifierFlags.contains(.control)
        else { return event }
        let point = convert(event.locationInWindow, from: nil)
        let radius = bounds.height / 2
        guard visibleRect.contains(point),
          NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).contains(point)
        else { return event }
        (window as? IslandPanel)?.activitySearchField?.endSearchEditing()
        action()
        return nil
      }
    }

    func stopMonitoring() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }
}

/// A PR's right-click menu: open or copy it, and for a merged PR, its share card.
private struct PRContextMenu: View {
  let pr: PullRequest
  @Environment(IslandStore.self) private var store: IslandStore?

  var body: some View {
    Button("Open on GitHub") { NSWorkspace.shared.open(pr.url) }
    Button("Copy link") {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(pr.url.absoluteString, forType: .string)
    }
    if let store {
      Divider()
      ShareCardActions(store: store, pr: pr)
    }
  }
}

/// "on #4340" for a PR built on another, or a restack hint once that one merged.
private struct StackLabel: View {
  let link: PRStacks.Link?

  var body: some View {
    if let parent = link?.parent {
      Text(verbatim: "on #\(parent.number)")
    } else if let merged = link?.mergedParent {
      Text("restack: #\(merged.number) merged").foregroundStyle(Palette.attention)
    }
  }
}

/// The elbow joining a stacked PR to the one it sits on, one step in per level.
private struct StackConnector: View {
  let depth: Int

  var body: some View {
    GeometryReader { geometry in
      let x = geometry.size.width - 8
      Path { path in
        path.move(to: CGPoint(x: x, y: -10))
        path.addLine(to: CGPoint(x: x, y: geometry.size.height / 2 - 3))
        path.addQuadCurve(
          to: CGPoint(x: x + 5, y: geometry.size.height / 2),
          control: CGPoint(x: x, y: geometry.size.height / 2))
        path.addLine(to: CGPoint(x: geometry.size.width + 4, y: geometry.size.height / 2))
      }
      .stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }
    .frame(width: CGFloat(depth) * 14)
  }
}

struct PRRow: View {
  let pr: PullRequest
  /// On a folded stack: the PRs it holds, counted in place of "on #436".
  var pile: [PullRequest]?
  /// What a click does instead of opening the PR, such as unfolding its stack.
  var tap: (() -> Void)?
  @State private var hovered = false
  /// The pointer is on the PR's number, its link to GitHub.
  @State private var numberHovered = false
  @Environment(\.openPullRequest) private var open
  @Environment(\.stackLinks) private var stacks
  @Environment(IslandStore.self) private var store

  var body: some View {
    Button {
      // ⌘-click opens GitHub, as a link would.
      if NSEvent.modifierFlags.contains(.command) {
        NSWorkspace.shared.open(pr.url)
      } else if let tap {
        tap()
      } else {
        open(pr)
      }
    } label: {
      HStack(spacing: 10) {
        if pile == nil, let depth = stacks[pr.id]?.depth, depth > 0 {
          StackConnector(depth: min(depth, 3))
        }
        if let pile {
          StackIcon(pile: pile).frame(width: 18)
        } else {
          GlyphView(glyph: pr.glyph, size: 15).foregroundStyle(pr.glyphColor)
            .frame(width: 18)
        }
        VStack(alignment: .leading, spacing: 3) {
          Text(pr.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            PRNumber(number: pr.number, link: numberHovered)
            if pile == nil { StackLabel(link: stacks[pr.id]) }
            Text("·")
            Text(pr.stateLabel.text).foregroundStyle(pr.stateLabel.color)
            Text("·")
            Text(Format.age(pr.mergedAt ?? pr.updatedAt))
          }
          .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
        }
        Spacer(minLength: 8)
        if let position = pr.queuePosition, pr.state == "OPEN" {
          Text(verbatim: "#\(position) in queue").font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Palette.merging)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Palette.merging.opacity(0.14)))
        }
        if pr.state == "OPEN" { PreviewChip(pr: pr) }
        if pr.state == "OPEN" { CheckBadge(pr: pr) }
      }
      .padding(.vertical, 7).padding(.horizontal, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(.white.opacity(hovered ? 0.07 : 0))
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(PressableStyle())
    .overlayPreferenceValue(PRNumberBounds.self) {
      PRNumberLink(url: pr.url, bounds: $0, hovered: $numberHovered)
    }
    .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
    .onAppear {
      if store.previewHover == pr.id {
        hovered = true
        numberHovered = true
      }
    }
    .help("Show \(pr.repository) #\(pr.number). ⌘-click opens it on GitHub.")
    .contextMenu { PRContextMenu(pr: pr) }
    .accessibilityLabel("\(pr.title), \(pr.repository) number \(pr.number), \(pr.stateLabel.text)")
    .prChecksControl(pr)
  }
}

/// A PR's number after the GitHub mark, as a link to the PR on GitHub, the same mark that
/// opens it from its page. Both brighten with the pointer on them.
struct PRNumber: View {
  let number: Int
  let link: Bool

  var body: some View {
    HStack(spacing: 4) {
      GlyphView(glyph: .github, size: 10.5)
      Text(verbatim: "#\(number)").monospacedDigit()
    }
    .foregroundStyle(.white.opacity(link ? 0.9 : 0.45))
    .anchorPreference(key: PRNumberBounds.self, value: .bounds) { $0 }
  }
}

/// Where a row's or card's number is, so its link can sit over it.
struct PRNumberBounds: PreferenceKey {
  static let defaultValue: Anchor<CGRect>? = nil
  static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
    value = value ?? nextValue()
  }
}

/// Opens a PR on GitHub from its number. It sits over the number, above the row's own
/// button: a button inside another button's label doesn't get its clicks.
private struct PRNumberLink: View {
  let url: URL
  let bounds: Anchor<CGRect>?
  @Binding var hovered: Bool

  var body: some View {
    GeometryReader { proxy in
      if let bounds {
        let rect = proxy[bounds].insetBy(dx: -3, dy: -3)
        Color.clear
          .contentShape(Rectangle())
          .frame(width: rect.width, height: rect.height)
          .offset(x: rect.minX, y: rect.minY)
          .onTapGesture { NSWorkspace.shared.open(url) }
          .onHover { inside in
            withAnimation(.easeOut(duration: 0.1)) { hovered = inside }
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
          }
          .help("Open on GitHub")
          .accessibilityElement()
          .accessibilityLabel("Open on GitHub")
          .accessibilityAddTraits(.isLink)
      }
    }
  }
}

/// PRs as a board: one column per state, each scrolling on its own.
private struct BoardView: View {
  let store: IslandStore
  @Binding var contentHeight: CGFloat
  let heightLimit: CGFloat
  @State private var heights: [PRGroup: CGFloat] = [:]
  @State private var expanded: Set<PRGroup> = []

  var body: some View {
    Group {
      if store.github != nil && store.sections.isEmpty {
        ActivityEmptyState(store: store)
          .padding(activityListInsets)
          .onGeometryChange(for: CGFloat.self) {
            $0.size.height
          } action: {
            contentHeight = $0
          }
      } else {
        HStack(alignment: .top, spacing: 10) {
          ForEach(columns) { section in
            let piles = PRStacks.piles(section.pullRequests, links: store.stackLinks)
            let visible = piles.prefix(
              expanded.contains(section.group) ? piles.count : activityPreviewLimit)
            // Even one card from each of these piles fills a tall column.
            let fixedHeight = CGFloat(visible.count) * 60 >= heightLimit ? heightLimit : nil
            MeasuredColumn(fixedHeight: fixedHeight) {
              column(section, piles: visible, hidden: piles.count - visible.count)
                .padding(.top, 10).padding(.bottom, 4)
            } onHeight: { height in
              var next = heights
              next[section.group] = height
              heights = next
              report(next)
            }
            .frame(maxWidth: .infinity)
            .transition(.opacity)
          }
        }
        .padding(.horizontal, 16)
      }
    }
    .animation(Motion.snappy, value: store.sections)
    .onChange(of: store.sections.map(\.group)) { report(heights) }
  }

  private var columns: [PRSection] {
    store.sections.sorted {
      (PRGroup.boardOrder.firstIndex(of: $0.group) ?? 0)
        < (PRGroup.boardOrder.firstIndex(of: $1.group) ?? 0)
    }
  }

  /// The tallest visible column sets the island height. With no columns the empty state
  /// reports its own height, so this must not overwrite it with zero.
  private func report(_ heights: [PRGroup: CGFloat]) {
    let visible = Set(store.sections.map(\.group))
    guard let tallest = heights.filter({ visible.contains($0.key) }).values.max() else { return }
    contentHeight = tallest
  }

  private func column(_ section: PRSection, piles: ArraySlice<[PullRequest]>, hidden: Int)
    -> some View
  {
    LazyVStack(alignment: .leading, spacing: 8) {
      BoardColumnHeader(section: section)
        .padding(.horizontal, 4).padding(.top, 4)
      ForEach(piles, id: \.first?.id) { pile in
        if pile.count > 1, let bottom = pile.first {
          StackPile(pile: pile, fanned: !store.foldedStacks.contains(bottom.id)) {
            withAnimation(Motion.snappy) { store.toggleStack(bottom.id) }
          }
          .transition(.opacity)
        } else if let pr = pile.first {
          PRCard(pr: pr).transition(.opacity)
        }
      }
      if hidden > 0 || store.canLoadMorePRs(in: section.group) {
        MorePRsRow(store: store, group: section.group, hasHiddenPRs: hidden > 0) {
          withAnimation(Motion.snappy) { _ = expanded.insert(section.group) }
        }
      }
    }
  }
}

private struct BoardColumnHeader: View {
  let section: PRSection

  var body: some View {
    let repositories = Dictionary(grouping: section.pullRequests, by: \.repository)
    let ordered = repositories.keys.sorted { lhs, rhs in
      let leftCount = repositories[lhs]?.count ?? 0
      let rightCount = repositories[rhs]?.count ?? 0
      return leftCount == rightCount ? lhs < rhs : leftCount > rightCount
    }
    let badges = HStack(spacing: 4) {
      ForEach(ordered, id: \.self) { repo in
        let pulls = repositories[repo] ?? []
        HStack(spacing: 4) {
          RepoAvatar(url: pulls.lazy.compactMap(\.ownerAvatar).first, size: 12)
          Text("\(pulls.count)").monospacedDigit()
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(section.group.color)
        .padding(.horizontal, 5).padding(.vertical, 3)
        .background(Capsule().fill(section.group.color.opacity(0.13)))
        .help("\(repo) · \(pulls.count) \(section.group.label.lowercased())")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          "\(repo), \(pulls.count) \(section.group.label.lowercased()) pull requests")
      }
    }
    HStack(spacing: 6) {
      HStack(spacing: 6) {
        GlyphView(glyph: section.group.glyph, size: 12).foregroundStyle(section.group.color)
        Text(section.group.label).font(.system(size: 11.5, weight: .semibold))
        Text("\(section.pullRequests.count)").font(.system(size: 11, weight: .semibold))
          .monospacedDigit().foregroundStyle(.white.opacity(0.35))
      }
      .fixedSize(horizontal: true, vertical: false)
      ViewThatFits(in: .horizontal) {
        badges.fixedSize(horizontal: true, vertical: false)
        ScrollView(.horizontal) { badges }
          .scrollIndicators(.hidden)
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .frame(height: 20)
  }
}

private struct PRCard: View {
  let pr: PullRequest
  /// On a folded pile: the PRs it holds, counted in place of "on #436".
  var pile: [PullRequest]?
  /// What a click does instead of opening the PR, such as fanning out its pile.
  var tap: (() -> Void)?
  @State private var hovered = false
  /// The pointer is on the PR's number, its link to GitHub.
  @State private var numberHovered = false
  @Environment(\.openPullRequest) private var open
  @Environment(\.stackLinks) private var stacks
  @Environment(IslandStore.self) private var store

  var body: some View {
    Button {
      if NSEvent.modifierFlags.contains(.command) {
        NSWorkspace.shared.open(pr.url)
      } else if let tap {
        tap()
      } else {
        open(pr)
      }
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        // Its text shares one baseline; the picture centres on the letters.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          RepoAvatar(url: pr.ownerAvatar, size: 14)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 3.8 }
          Text(verbatim: pr.repository.split(separator: "/").last.map(String.init) ?? "")
            .lineLimit(1)
          Spacer(minLength: 4)
          if let pile {
            StackCount(pile: pile)
          }
          PRNumber(number: pr.number, link: numberHovered)
          if pile == nil { StackLabel(link: stacks[pr.id]) }
        }
        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
        Text(pr.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 6) {
          Text(pr.stateLabel.text).foregroundStyle(pr.stateLabel.color).lineLimit(1)
          Spacer(minLength: 4)
          if pr.state == "OPEN" { PreviewChip(pr: pr) }
          if pr.state == "OPEN" { CheckBadge(pr: pr) }
        }
        .font(.system(size: 10.5, weight: .medium))
      }
      .padding(10)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(.white.opacity(hovered ? 0.085 : 0.045))
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(PressableStyle())
    .overlayPreferenceValue(PRNumberBounds.self) {
      PRNumberLink(url: pr.url, bounds: $0, hovered: $numberHovered)
    }
    .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
    .onAppear {
      if store.previewHover == pr.id {
        hovered = true
        numberHovered = true
      }
    }
    .help("Show \(pr.repository) #\(pr.number). ⌘-click opens it on GitHub.")
    .contextMenu { PRContextMenu(pr: pr) }
    .accessibilityLabel("\(pr.title), \(pr.repository) number \(pr.number), \(pr.stateLabel.text)")
    .prChecksControl(pr)
  }
}

/// A stack's PRs in one board column, as a pile with its top PR in front and the cards below
/// peeking out. A click fans the cards out from under it, top PR first; a click on the count
/// above them folds them back. The cards stay the same views throughout, so they slide
/// rather than swap.
private struct StackPile: View {
  let pile: [PullRequest]
  let fanned: Bool
  let toggle: () -> Void

  var body: some View {
    let cards = Array(pile.reversed())
    VStack(alignment: .leading, spacing: fanned ? 6 : 0) {
      if fanned {
        FoldStack(pile: pile, action: toggle).transition(.opacity)
      }
      ForEach(Array(cards.enumerated()), id: \.element.id) { index, pr in
        if index == 0 {
          PRCard(pr: pr, pile: fanned ? nil : pile, tap: fanned ? nil : toggle)
            // Cards are see-through; a solid back keeps the ones below from showing through.
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black))
            .zIndex(Double(cards.count))
        } else {
          let peeking = index <= 2
          PRCard(pr: pr)
            // Folded, only the card's bottom edge shows, solid and a step narrower per card.
            .overlay {
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: index == 1 ? 0.07 : 0.045))
                .opacity(fanned ? 0 : 1)
            }
            .frame(height: fanned ? nil : (peeking ? 4.5 : 0), alignment: .bottom)
            .clipped()
            .padding(.horizontal, fanned ? 0 : CGFloat(index) * 5)
            .opacity(fanned || peeking ? 1 : 0)
            .allowsHitTesting(fanned)
            .zIndex(Double(cards.count - index))
        }
      }
    }
    .help(fanned ? "" : "A stack of \(pile.count) PRs. Click to see them all.")
  }
}

/// A stack in the list. Folded, only its top PR shows, with the stack's count; unfolded, the
/// rows below it open above it, bottom PR first. The rows stay the same views either way, so
/// they open and close rather than swap.
private struct ListStack: View {
  let pile: [PullRequest]
  let unfolded: Bool
  let toggle: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      if unfolded {
        FoldStack(pile: pile, action: toggle).transition(.opacity)
      }
      ForEach(pile) { pr in
        let top = pr.id == pile.last?.id
        PRRow(pr: pr, pile: unfolded || !top ? nil : pile, tap: unfolded ? nil : toggle)
          .frame(height: unfolded || top ? nil : 0, alignment: .top)
          .clipped()
          .opacity(unfolded || top ? 1 : 0)
          .allowsHitTesting(unfolded || top)
      }
    }
  }
}

/// A folded stack's icon in the list: a stack coloured by its worst PR, with its count on the
/// lower corner.
private struct StackIcon: View {
  let pile: [PullRequest]

  var body: some View {
    Image(systemName: "square.stack.3d.up.fill").font(.system(size: 14, weight: .medium))
      .foregroundStyle(StackCount.color(pile))
      // On the stack's lower corner in grey, outlined in black so it reads over any colour.
      .overlay(alignment: .bottomTrailing) {
        Text("\(pile.count)").font(.system(size: 10, weight: .medium)).monospacedDigit()
          .foregroundStyle(Color(white: 0.6))
          .shadow(color: .black, radius: 0, x: 1, y: 0).shadow(
            color: .black, radius: 0, x: -1, y: 0
          )
          .shadow(color: .black, radius: 0, x: 0, y: 1).shadow(
            color: .black, radius: 0, x: 0, y: -1
          )
          .fixedSize()
          .offset(x: 2, y: 3)
      }
      .help("A stack of \(pile.count) PRs. Click to open it.")
  }
}

/// Above an unfolded stack: its count and a chevron that folds it again.
private struct FoldStack: View {
  let pile: [PullRequest]
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        StackCount(pile: pile)
        Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold))
          .foregroundStyle(.white.opacity(0.4))
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8).padding(.vertical, 3).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("Fold the stack")
  }
}

/// The stack icon and how many PRs the stack holds, coloured by its worst PR, so a folded
/// pile can't hide a failure.
private struct StackCount: View {
  let pile: [PullRequest]

  var body: some View {
    // The icon sits inside the text, on the same baseline as the number beside it.
    Text("\(Image(systemName: "square.stack.3d.up")) \(pile.count)").monospacedDigit()
      .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Self.color(pile))
      .help("A stack of \(pile.count) PRs")
  }

  /// Red when any PR failed, has conflicts or was asked for changes; amber while any still
  /// runs checks or waits on a review; green when all are ready or merging; grey otherwise.
  static func color(_ pile: [PullRequest]) -> Color {
    let statuses = pile.map(\.status)
    if statuses.contains(where: { [.failed, .conflicts, .changesRequested].contains($0) }) {
      return Palette.failed
    }
    if statuses.contains(where: { [.checking, .review, .waiting, .behind, .blocked].contains($0) })
    {
      return Palette.attention
    }
    if statuses.allSatisfy({ [.ready, .queued, .merged].contains($0) }) { return Palette.open }
    return .white.opacity(0.45)
  }
}

/// A subtle press response for list rows.
struct PressableStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .opacity(configuration.isPressed ? 0.8 : 1)
      .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
  }
}
