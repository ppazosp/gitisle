import AppKit
import IslandCore
import SwiftUI

struct ActivityView: View {
  let store: IslandStore

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      notices
      if store.github != nil && store.sections.isEmpty {
        EmptyState(
          glyph: .checkFill,
          text: store.activityWindow == .all
            ? "You're all caught up" : "No PR activity \(windowPhrase)")
      }
      ForEach(store.sections) { section in
        SectionHeader(
          title: section.group.label, count: section.pullRequests.count,
          glyph: section.group.glyph, color: section.group.color)
        ForEach(section.pullRequests.prefix(section.group == .merged ? 6 : 40)) { pr in
          PRRow(pr: pr)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
      }
      SectionHeader(
        title: "Sessions", count: store.workingCount > 0 ? store.workingCount : nil,
        glyph: nil)
      if store.visibleSessions.isEmpty {
        Text("No recent Codex or Claude Code sessions on this Mac.")
          .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.4))
          .padding(.horizontal, 8).padding(.vertical, 8)
      }
      ForEach(store.visibleSessions) { session in
        SessionRow(session: session)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .animation(Motion.snappy, value: store.sections)
    .animation(Motion.snappy, value: store.visibleSessions)
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
      .padding(.top, 10)
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
            Text(verbatim: "\(pr.repository) #\(pr.number)")
            if let detail {
              Text("·")
              Text(detail.text).foregroundStyle(detail.color)
            }
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
    .accessibilityLabel("\(pr.title), \(pr.repository) number \(pr.number), \(pr.status.label)")
  }

  /// The reason a PR is in its section, when the section alone does not say it.
  private var detail: (text: String, color: Color)? {
    switch pr.group {
    case .needsYou: (pr.status.label, pr.status.color)
    case .merging: pr.queuePosition == nil ? ("Auto-merge", Palette.merging) : nil
    case .open:
      [.checking, .unknown].contains(pr.status) ? nil : (pr.status.label, .white.opacity(0.45))
    default: nil
    }
  }
}

struct SessionRow: View {
  let session: AgentSession
  @State private var hovered = false

  var body: some View {
    Button {
      NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.directory)
    } label: {
      HStack(spacing: 10) {
        GlyphView(glyph: session.provider.glyph, size: 14)
          .foregroundStyle(session.provider.tint)
          .frame(width: 26, height: 26)
          .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.surface))
          .opacity(session.isActive ? 1 : 0.6)
        VStack(alignment: .leading, spacing: 3) {
          Text(session.title ?? session.project)
            .font(.system(size: 12.5, weight: .medium)).lineLimit(1)
            .foregroundStyle(.white.opacity(session.isActive ? 1 : 0.65))
          Text(meta).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        phase
      }
      .padding(.vertical, 6).padding(.horizontal, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(.white.opacity(hovered ? 0.07 : 0))
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(PressableStyle())
    .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
    .help("Show \(session.project) in Finder")
  }

  private var meta: String {
    var parts = [session.title == nil ? session.source : session.project]
    if let branch = session.branch { parts.append(branch) }
    parts.append(session.activity)
    return parts.joined(separator: " · ")
  }

  @ViewBuilder private var phase: some View {
    HStack(spacing: 6) {
      switch session.phase {
      case .working:
        PulseDot(color: Palette.open)
        Text(Format.age(session.updatedAt)).foregroundStyle(.white.opacity(0.5))
      case .waiting:
        PulseDot(color: Palette.attention)
        Text("Needs you").foregroundStyle(Palette.attention)
      default:
        Text("\(session.phase.label) · \(Format.age(session.updatedAt))")
          .foregroundStyle(.white.opacity(0.35))
      }
    }
    .font(.system(size: 10.5, weight: .medium)).monospacedDigit()
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
