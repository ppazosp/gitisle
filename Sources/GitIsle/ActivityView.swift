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
            text: store.activityWindow == .all
              ? "You're all caught up" : "No PR activity \(windowPhrase)")
        }
        ForEach(store.repositories) { section in
          if section.id != store.repositories.first?.id {
            Rectangle().fill(Palette.hairline).frame(height: 1).padding(.horizontal, 8)
          }
          RepositoryCard(
            section: section, collapsed: store.collapsedRepositories.contains(section.id)
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
    store.activityWindow == .today ? "today" : "in the last 7 days"
  }

  @ViewBuilder private var notices: some View {
    if let error = store.githubError {
      Notice(text: error)
    }
    if store.github?.isLimited == true {
      Notice(
        text:
          "Showing the first 100 PRs in each group. Narrow the watched repositories in Settings.")
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
  let toggle: () -> Void
  @State private var hovered = false

  /// Merged PRs are history; a few are enough next to open work.
  private var visible: [PullRequest] {
    var merged = 0
    return section.pullRequests.filter { pr in
      guard pr.group == .merged else { return true }
      merged += 1
      return merged <= 5
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      Button(action: toggle) {
        HStack(spacing: 9) {
          RepoAvatar(url: section.avatar)
          (Text(verbatim: "\(section.owner)/").foregroundStyle(.white.opacity(0.45))
            + Text(verbatim: section.name).foregroundStyle(.white))
            .font(.system(size: 13, weight: .semibold)).lineLimit(1)
          Spacer(minLength: 12)
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
      }
      .buttonStyle(.plain)
      .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
      .accessibilityLabel(
        "\(section.repository), \(section.pullRequests.count) pull requests, "
          + (collapsed ? "collapsed" : "expanded"))
      // Rows stay in place and are revealed by a clipped height, so they never slide
      // over the header while the section opens or closes.
      VStack(spacing: 0) {
        ForEach(visible) { pr in
          PRRow(pr: pr).transition(.opacity)
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
            if let reason = pr.reason {
              Text("·")
              Text(reason.text).foregroundStyle(reason.color)
            }
            Text("·")
            Text(Format.age(pr.mergedAt ?? pr.updatedAt))
          }
          .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
        }
        Spacer(minLength: 8)
        if let position = pr.queuePosition, pr.state == "OPEN" { QueueBadge(position: position) }
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

  var body: some View {
    Group {
      if store.github != nil && store.sections.isEmpty {
        EmptyState(glyph: .checkFill, text: "No PRs here")
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

  /// The tallest visible column sets the island height.
  private func report(_ heights: [PRGroup: CGFloat]) {
    let visible = Set(store.sections.map(\.group))
    contentHeight = heights.filter { visible.contains($0.key) }.values.max() ?? 0
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
      ForEach(section.pullRequests.prefix(section.group == .merged ? 8 : 40)) { pr in
        PRCard(pr: pr).transition(.opacity)
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
          if let reason = pr.reason {
            Text(reason.text).foregroundStyle(reason.color).lineLimit(1)
          } else {
            Text(Format.age(pr.mergedAt ?? pr.updatedAt)).foregroundStyle(.white.opacity(0.4))
          }
          Spacer(minLength: 4)
          if let position = pr.queuePosition, pr.state == "OPEN" { QueueBadge(position: position) }
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
