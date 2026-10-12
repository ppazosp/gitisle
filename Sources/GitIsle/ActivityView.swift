import AppKit
import IslandCore
import SwiftUI

struct ActivityView: View {
  let store: IslandStore
  @Binding var contentHeight: CGFloat

  var body: some View {
    switch store.activityLayout {
    case .list: list
    case .board: BoardView(store: store, contentHeight: $contentHeight)
    }
  }

  private var list: some View {
    MeasuredColumn {
      VStack(alignment: .leading, spacing: 0) {
        notices
        if store.github != nil && store.repositories.isEmpty {
          EmptyState(
            glyph: .checkFill,
            text: !store.stateFilter.isEmpty || store.needsYouOnly
              ? "No PRs match these filters"
              : store.activityWindow == .month
                ? "You're all caught up" : "No PR activity \(windowPhrase)")
        }
        ForEach(store.repositories) { section in
          if section.id != store.repositories.first?.id {
            Rectangle().fill(Palette.hairline).frame(height: 1).padding(.horizontal, 8)
          }
          RepositoryCard(
            section: section, collapsed: store.collapsedRepositories.contains(section.id),
            showsEverything: !store.stateFilter.isEmpty || store.needsYouOnly,
          ) {
            withAnimation(Motion.snappy) { store.toggleCollapsed(section.id) }
          }
          .transition(.opacity)
        }
      }
      .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)
    } onHeight: {
      contentHeight = $0
    }
    .animation(Motion.snappy, value: store.repositories)
  }

  private var windowPhrase: String {
    store.activityWindow == .today ? "today" : "in the last \(store.activityWindow.days) days"
  }

  @ViewBuilder private var notices: some View {
    if let error = store.githubError {
      Notice(text: error)
    }
    if store.github?.isLimited == true {
      Notice(
        text:
          "Showing the first 400 PRs in each group. Narrow the watched repositories in Settings.")
    }
  }
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

private struct EmptyState: View {
  let glyph: Glyph
  let text: String
  var body: some View {
    HStack(spacing: 8) {
      GlyphView(glyph: glyph, size: 14).foregroundStyle(Palette.open)
      Text(text).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6))
    }
    .frame(maxWidth: .infinity).padding(.vertical, 22)
  }
}

/// A repository with its PRs. The header summarizes PR states and toggles the list.
private struct RepositoryCard: View {
  let section: RepoSection
  let collapsed: Bool
  /// A state filter is a request to see those PRs, so nothing is shortened.
  let showsEverything: Bool
  let toggle: () -> Void
  @State private var hovered = false
  @State private var showsAllMerged = false

  /// Merged PRs are history; a few are enough next to open work until asked for more.
  private var visible: [PullRequest] {
    guard !showsEverything, !showsAllMerged else { return section.pullRequests }
    var merged = 0
    return section.pullRequests.filter { pr in
      guard pr.group == .merged else { return true }
      merged += 1
      return merged <= 5
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 9) {
        RepoAvatar(url: section.avatar)
        (Text(verbatim: "\(section.owner)/").foregroundStyle(.white.opacity(0.45))
          + Text(verbatim: section.name).foregroundStyle(.white))
          .font(.system(size: 13, weight: .semibold)).lineLimit(1)
        Spacer(minLength: 12)
        if section.needsYou > 0 {
          HStack(spacing: 4) {
            GlyphView(glyph: .eye, size: 11)
            Text("\(section.needsYou)").monospacedDigit()
          }
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Palette.attention)
          .padding(.horizontal, 7).padding(.vertical, 3)
          .background(Capsule().fill(Palette.attention.opacity(0.13)))
          .help("\(section.needsYou) need you")
        }
        ForEach(section.counts, id: \.group) { item in
          HStack(spacing: 4) {
            GlyphView(glyph: item.group.glyph, size: 11)
            Text("\(item.count)").monospacedDigit()
              .contentTransition(.numericText(value: Double(item.count)))
          }
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(item.group.color)
          .padding(.horizontal, 7).padding(.vertical, 3)
          .background(Capsule().fill(item.group.color.opacity(0.13)))
          .help("\(item.count) \(item.group.label.lowercased())")
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
      // Rows stay in place and are revealed by a clipped height, so they never slide
      // over the header while the section opens or closes.
      VStack(spacing: 0) {
        let visible = self.visible
        ForEach(visible) { pr in
          PRRow(pr: pr).transition(.opacity)
        }
        if visible.count < section.pullRequests.count {
          ShowMoreButton(hidden: section.pullRequests.count - visible.count) {
            withAnimation(Motion.snappy) { showsAllMerged = true }
          }
          .padding(.horizontal, 8).padding(.top, 2)
        }
      }
      .padding(.bottom, 8)
      .fixedSize(horizontal: false, vertical: true)
      .frame(height: collapsed ? 0 : nil, alignment: .top)
      .opacity(collapsed ? 0 : 1)
      .clipped()
      .allowsHitTesting(!collapsed)
      .accessibilityHidden(collapsed)
    }
  }
}

/// State filters for Activity, shared by the list and the board. Pressing a state shows
/// only PRs in it; pressing again clears it, and several states combine.
struct StateFilterBar: View {
  let store: IslandStore

  var body: some View {
    HStack(spacing: 6) {
      NeedsYouChip(
        count: store.needsYouCount, selected: store.needsYouOnly
      ) {
        withAnimation(Motion.morph) { store.needsYouOnly.toggle() }
      }
      Rectangle().fill(Palette.hairline).frame(width: 1, height: 16).padding(.horizontal, 2)
      ForEach(PRGroup.boardOrder, id: \.self) { group in
        let count = store.stateCounts.first { $0.group == group }?.count ?? 0
        let selected = store.stateFilter.contains(group)
        // Merged history is capped at the newest 400; say so rather than undercount.
        let capped =
          group == .merged && store.github?.mergedLimited == true && store.activityWindow == .month
        StateChip(
          group: group, count: count, capped: capped, selected: selected,
          dimmed: !store.stateFilter.isEmpty && !selected
        ) {
          withAnimation(Motion.morph) { store.toggleState(group) }
        }
        .disabled(count == 0 && !selected)
        .opacity(count == 0 && !selected ? 0.35 : 1)
      }
      Spacer(minLength: 4)
      if !store.stateFilter.isEmpty || store.needsYouOnly {
        Button {
          withAnimation(Motion.morph) {
            store.stateFilter = []
            store.needsYouOnly = false
          }
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
    .animation(Motion.snappy, value: store.needsYouOnly)
  }
}

/// Shows only PRs waiting on you, within whichever states are selected.
private struct NeedsYouChip: View {
  let count: Int
  let selected: Bool
  let action: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        GlyphView(glyph: .eye, size: 11)
        Text("Needs you").lineLimit(1).fixedSize()
        Text("\(count)").monospacedDigit().opacity(0.7)
          .contentTransition(.numericText(value: Double(count)))
      }
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(Palette.attention)
      .padding(.horizontal, 8).padding(.vertical, 4)
      .background(
        Capsule().fill(Palette.attention.opacity(selected ? 0.28 : hovered ? 0.2 : 0.11))
      )
      .overlay(
        Capsule().inset(by: 0.5).stroke(
          Palette.attention.opacity(selected ? 0.9 : 0), lineWidth: 1)
      )
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(count == 0 && !selected)
    .opacity(count == 0 && !selected ? 0.35 : 1)
    .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
    .help(selected ? "Show every PR" : "Show only PRs waiting on you")
    .accessibilityLabel("Needs you, \(count)")
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }
}

private struct StateChip: View {
  let group: PRGroup
  let count: Int
  var capped = false
  let selected: Bool
  let dimmed: Bool
  let action: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        GlyphView(glyph: group.glyph, size: 11)
        Text(group.label).lineLimit(1).fixedSize()
        Text(capped ? "\(count)+" : "\(count)").monospacedDigit().opacity(0.7)
          .contentTransition(.numericText(value: Double(count)))
      }
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(group.color)
      .padding(.horizontal, 8).padding(.vertical, 4)
      .background(
        Capsule().fill(group.color.opacity(selected ? 0.28 : hovered ? 0.2 : 0.11))
      )
      .overlay(
        Capsule().inset(by: 0.5).stroke(group.color.opacity(selected ? 0.9 : 0), lineWidth: 1)
      )
      .opacity(dimmed && !hovered ? 0.45 : 1)
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
    .help(
      selected
        ? "Stop filtering by \(group.label.lowercased())" : "Filter by \(group.label.lowercased())"
    )
    .accessibilityLabel("\(group.label), \(count)")
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }
}

struct PRRow: View {
  let pr: PullRequest
  @State private var hovered = false

  var body: some View {
    Button {
      NSWorkspace.shared.open(pr.url)
    } label: {
      HStack(spacing: 10) {
        GlyphView(glyph: pr.glyph, size: 15).foregroundStyle(pr.glyphColor)
          .frame(width: 18)
        VStack(alignment: .leading, spacing: 3) {
          Text(pr.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
          HStack(spacing: 4) {
            Text(verbatim: "#\(pr.number)")
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
    .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
    .help("Open \(pr.repository) #\(pr.number) on GitHub")
    .accessibilityLabel("\(pr.title), \(pr.repository) number \(pr.number), \(pr.stateLabel.text)")
  }
}

/// PRs as a board: one column per state, each scrolling on its own.
private struct BoardView: View {
  let store: IslandStore
  @Binding var contentHeight: CGFloat
  @State private var heights: [PRGroup: CGFloat] = [:]
  @State private var expanded: Set<PRGroup> = []

  var body: some View {
    Group {
      if store.github != nil && store.sections.isEmpty {
        EmptyState(
          glyph: .checkFill,
          text: store.stateFilter.isEmpty && !store.needsYouOnly
            ? "No PRs here" : "No PRs match these filters"
        )
        .onGeometryChange(for: CGFloat.self) {
          $0.size.height
        } action: {
          contentHeight = $0
        }
      } else {
        HStack(alignment: .top, spacing: 10) {
          ForEach(columns) { section in
            MeasuredColumn {
              column(section).padding(.top, 10).padding(.bottom, 4)
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

  /// Long columns show their newest cards first; a state filter or "show more" lifts that.
  private func shortened(_ section: PRSection) -> Bool {
    store.stateFilter.isEmpty && !store.needsYouOnly && !expanded.contains(section.group)
  }

  private func column(_ section: PRSection) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        GlyphView(glyph: section.group.glyph, size: 12).foregroundStyle(section.group.color)
        Text(section.group.label).font(.system(size: 11.5, weight: .semibold))
        Text("\(section.pullRequests.count)").font(.system(size: 11, weight: .semibold))
          .monospacedDigit().foregroundStyle(.white.opacity(0.35))
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 4).padding(.top, 4)
      let limit = shortened(section) ? 8 : section.pullRequests.count
      ForEach(section.pullRequests.prefix(limit)) { pr in
        PRCard(pr: pr).transition(.opacity)
      }
      if section.pullRequests.count > limit {
        ShowMoreButton(hidden: section.pullRequests.count - limit) {
          withAnimation(Motion.snappy) { _ = expanded.insert(section.group) }
        }
      }
    }
  }
}

private struct PRCard: View {
  let pr: PullRequest
  @State private var hovered = false

  var body: some View {
    Button {
      NSWorkspace.shared.open(pr.url)
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 6) {
          RepoAvatar(url: pr.ownerAvatar, size: 14)
          Text(verbatim: pr.repository.split(separator: "/").last.map(String.init) ?? "")
            .lineLimit(1)
          Spacer(minLength: 4)
          Text(verbatim: "#\(pr.number)").monospacedDigit()
        }
        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
        Text(pr.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 6) {
          Text(pr.stateLabel.text).foregroundStyle(pr.stateLabel.color).lineLimit(1)
          Spacer(minLength: 4)
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
    .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
    .help("Open \(pr.repository) #\(pr.number) on GitHub")
    .accessibilityLabel("\(pr.title), \(pr.repository) number \(pr.number), \(pr.stateLabel.text)")
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
