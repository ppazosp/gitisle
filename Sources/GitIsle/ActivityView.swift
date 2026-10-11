import AppKit
import IslandCore
import SwiftUI

struct ActivityView: View {
  let store: IslandStore
  @Binding var contentHeight: CGFloat

  var body: some View {
    MeasuredColumn {
      VStack(alignment: .leading, spacing: 10) {
        notices
        if store.github != nil && store.repositories.isEmpty {
          EmptyState(
            glyph: .checkFill,
            text: store.activityWindow == .all
              ? "You're all caught up" : "No PR activity \(windowPhrase)")
        }
        ForEach(store.repositories) { section in
          RepositoryCard(
            section: section, collapsed: store.collapsedRepositories.contains(section.id)
          ) {
            withAnimation(Motion.snappy) { store.toggleCollapsed(section.id) }
          }
          .transition(.opacity.combined(with: .move(edge: .top)))
        }
      }
      .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 18)
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
          GlyphView(glyph: .repo, size: 14).foregroundStyle(.white.opacity(0.5))
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
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
      .accessibilityLabel(
        "\(section.repository), \(section.pullRequests.count) pull requests, "
          + (collapsed ? "collapsed" : "expanded"))
      if !collapsed {
        VStack(spacing: 0) {
          Rectangle().fill(Palette.hairline).frame(height: 1).padding(.horizontal, 14)
          VStack(spacing: 0) {
            ForEach(visible) { pr in
              PRRow(pr: pr)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
          }
          .padding(.horizontal, 6).padding(.vertical, 6)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(.white.opacity(hovered ? 0.075 : 0.055))
    )
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            Text(state.text).foregroundStyle(state.color)
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
    .accessibilityLabel("\(pr.title), \(pr.repository) number \(pr.number), \(state.text)")
  }

  /// The PR's state, with the specific reason when it needs you.
  private var state: (text: String, color: Color) {
    switch pr.group {
    case .needsYou: (pr.status.label, pr.status.color)
    case .merging: (pr.queuePosition == nil ? "Auto-merge" : "Merging", Palette.merging)
    case .open:
      [.checking, .unknown].contains(pr.status)
        ? ("Open", Palette.open) : (pr.status.label, Palette.open)
    case .draft: ("Draft", Palette.draft)
    case .merged: ("Merged", Palette.merged)
    case nil: ("Closed", Palette.failed)
    }
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
