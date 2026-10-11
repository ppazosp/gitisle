import AppKit
import IslandCore
import SwiftUI

struct IslandView: View {
  @Bindable var store: IslandStore
  let metrics: IslandMetrics
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        if store.expanded { expandedContent } else { compactContent }
      }
      .frame(
        width: store.expanded ? 460 : metrics.closedWidth,
        height: store.expanded ? metrics.expandedHeight(for: store) : metrics.closedHeight,
        alignment: .top
      )
      .background(.black)
      .clipShape(RoundedRectangle(cornerRadius: store.expanded ? 26 : 20, style: .continuous))
      .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
      .foregroundStyle(.white)
      .preferredColorScheme(.dark)
      .animation(reduceMotion ? nil : .snappy(duration: 0.23), value: store.expanded)
      .padding(.top, metrics.topGap)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var compactContent: some View {
    Button {
      store.expanded = true
    } label: {
      HStack(spacing: 8) {
        Image(systemName: store.recentEvent == nil ? "arrow.triangle.pull" : "arrow.triangle.merge")
          .foregroundStyle(store.recentEvent?.kind == .merged ? .purple : .white)
        Text(
          store.recentEvent.map { $0.kind == .merged ? "Merged" : $0.kind.label }
            ?? (store.githubError != nil
              ? "Offline"
              : store.github == nil ? "Connecting" : "\(store.attention.count) need you")
        )
        .font(.system(size: 11, weight: .medium)).lineLimit(1)
        if metrics.hasNotch {
          Spacer().frame(width: metrics.notchWidth)
        } else {
          Spacer(minLength: 8)
        }
        Circle().fill(store.workingCount > 0 ? Color.green : Color.secondary).frame(
          width: 5, height: 5)
        Text(
          store.workingCount > 0 ? "\(store.workingCount) working" : "\(store.openPRs.count) PRs"
        )
        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
      }
      .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: metrics.closedHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      "GitIsle: \(store.attention.count) pull requests need attention. Expand island.")
  }

  private var expandedContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("GitIsle").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        Spacer()
        SettingsLink { Image(systemName: "gearshape").frame(width: 32, height: 28) }.buttonStyle(
          .plain
        )
        .accessibilityLabel("GitIsle settings")
        Button {
          store.dismiss()
        } label: {
          Image(systemName: "minus").frame(width: 32, height: 28)
        }
        .buttonStyle(.plain).accessibilityLabel("Collapse island")
      }
      .padding(.top, metrics.hasNotch ? metrics.notchHeight + 4 : 12)
      HStack(spacing: 22) {
        ForEach(IslandStore.IslandTab.allCases, id: \.self) { tab in
          Button {
            store.tab = tab
          } label: {
            HStack(spacing: 6) {
              Text(tab.rawValue).font(.system(size: 13, weight: .medium))
              Text("\(tab == .github ? store.openPRs.count : store.workingCount)").font(
                .system(size: 11)
              ).foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .foregroundStyle(store.tab == tab ? .white : .gray)
            .overlay(alignment: .bottom) {
              if store.tab == tab { Rectangle().fill(.white).frame(height: 1) }
            }
          }.buttonStyle(.plain).accessibilityAddTraits(store.tab == tab ? .isSelected : [])
        }
        Spacer()
        if store.githubRefreshing || store.usageRefreshing { ProgressView().controlSize(.mini) }
      }
      Divider().overlay(.white.opacity(0.12))
      ScrollView {
        if store.tab == .github { githubContent } else { agentsContent }
      }
      .scrollIndicators(.hidden)
      .frame(maxHeight: .infinity)
      Divider().overlay(.white.opacity(0.12))
      HStack {
        if store.isDemo {
          Text("Example data")
        } else if let github = store.github {
          Text(
            store.cached
              ? "Cached · \(github.fetchedAt.formatted(.relative(presentation: .named)))"
              : "Updated \(github.fetchedAt.formatted(.relative(presentation: .named)))")
        } else {
          Text("Waiting for GitHub")
        }
        Spacer()
        Button("Refresh") {
          Task {
            await store.refreshGitHub()
            await store.refreshUsage()
          }
        }
        .buttonStyle(.plain).disabled(
          store.githubRefreshing || store.usageRefreshing || store.isDemo)
      }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 12)
    }
    .padding(.horizontal, 20)
  }

  private var githubContent: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let error = store.githubError {
        Text(error).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled)
          .padding(.vertical, 10)
      }
      if store.github?.isLimited == true {
        Text(
          "Showing the first 100 PRs in each group. Narrow the watched repositories in Settings."
        )
        .font(.system(size: 11)).foregroundStyle(.orange).padding(.top, 8)
      }
      if store.github != nil && store.openPRs.isEmpty {
        Label("You're all caught up", systemImage: "checkmark.circle")
          .font(.system(size: 14)).foregroundStyle(.secondary).padding(.vertical, 30)
      }
      if !store.attention.isEmpty {
        sectionLabel("Needs your attention")
        ForEach(store.attention) { PRRow(pr: $0) }
      }
      let progressing = store.openPRs.filter { !$0.status.needsAttention }
      if !progressing.isEmpty {
        sectionLabel("In progress")
        ForEach(progressing) { PRRow(pr: $0) }
      }
      let merged = (store.github?.pullRequests ?? []).filter { $0.state == "MERGED" }.prefix(5)
      if !merged.isEmpty {
        sectionLabel("Recently merged")
        ForEach(Array(merged)) { PRRow(pr: $0) }
      }
      if !store.events.isEmpty {
        sectionLabel("Recent changes")
        ForEach(Array(store.events.prefix(5))) { event in
          Button {
            NSWorkspace.shared.open(event.url)
          } label: {
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: event.kind.symbol).foregroundStyle(event.kind.color)
              VStack(alignment: .leading, spacing: 3) {
                Text(event.title).lineLimit(2)
                Text(event.occurredAt, style: .relative).foregroundStyle(.secondary)
              }
            }.font(.system(size: 11)).padding(.vertical, 6).frame(
              maxWidth: .infinity, alignment: .leading)
          }.buttonStyle(.plain)
        }
      }
    }
    .padding(.bottom, 10)
  }

  private var agentsContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      sectionLabel("On this Mac")
      if store.agents.isEmpty {
        Text("No recent agent activity. Start a local Codex or Claude Code session.")
          .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 14)
      }
      ForEach(Array(store.agents.prefix(8))) { session in
        Button {
          NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.directory)
        } label: {
          HStack(alignment: .top, spacing: 10) {
            Circle().fill(
              session.phase == .working ? .green : session.phase == .waiting ? .orange : .gray
            )
            .frame(width: 6, height: 6).padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(session.source).fontWeight(.medium)
                Spacer()
                Text(session.phase.label).foregroundStyle(.secondary)
              }
              Text("\(session.project) · \(session.activity)").foregroundStyle(.secondary)
                .lineLimit(1)
              Text([session.model, session.branch].compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.secondary).lineLimit(1)
            }.font(.system(size: 11))
          }.padding(.vertical, 5).contentShape(Rectangle())
        }.buttonStyle(.plain)
      }
      Divider().padding(.top, 6)
      HStack {
        Text("Usage history").font(.system(size: 12, weight: .medium))
        Spacer()
        Picker("Period", selection: $store.usageDays) {
          Text("Today").tag(1)
          Text("7 days").tag(7)
          Text("30 days").tag(30)
        }.labelsHidden().pickerStyle(.segmented).frame(width: 204)
      }.padding(.vertical, 8)
      ForEach(AgentProvider.allCases, id: \.self) { provider in
        UsageBlock(
          provider: provider, summary: store.usage[provider]?.first { $0.days == store.usageDays },
          error: store.usageErrors[provider])
      }
      Text(
        "Tokens are recorded locally. Costs are estimates at API prices, separate from your subscription bill. Activity reflects local events; older sessions show an unknown state."
      )
      .font(.system(size: 10)).foregroundStyle(.secondary).padding(.vertical, 8)
    }.padding(.bottom, 8)
  }

  private func sectionLabel(_ label: String) -> some View {
    Text(label).font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 14).padding(
      .bottom, 3)
  }
}

struct PRRow: View {
  let pr: PullRequest
  @State private var hovered = false
  var body: some View {
    Button {
      NSWorkspace.shared.open(pr.url)
    } label: {
      HStack(alignment: .center, spacing: 10) {
        Image(systemName: pr.status.symbol).foregroundStyle(pr.status.color).frame(width: 16)
        VStack(alignment: .leading, spacing: 4) {
          Text(pr.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
          Text("\(pr.repository) #\(pr.number)").font(.system(size: 10)).foregroundStyle(.secondary)
            .lineLimit(1)
          if pr.autoMerge, pr.state == "OPEN" {
            Text("Auto-merge enabled").font(.system(size: 10)).foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 6)
        Text(pr.queuePosition.map { "Queue #\($0)" } ?? pr.status.label).font(.system(size: 10))
          .foregroundStyle(pr.status.color).multilineTextAlignment(.trailing).frame(maxWidth: 100)
      }.padding(.vertical, 9).padding(.horizontal, 6).frame(
        maxWidth: .infinity, alignment: .leading
      )
      .contentShape(Rectangle()).background(
        hovered ? Color.white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }.buttonStyle(.plain).onHover { hovered = $0 }
      .help("Open \(pr.repository) #\(pr.number) on GitHub")
  }
}

struct UsageBlock: View {
  let provider: AgentProvider
  let summary: UsageSummary?
  let error: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        Text(provider.label).fontWeight(.medium)
        Spacer()
        if summary?.partial == true { Text("Partial history").foregroundStyle(.orange) }
      }
      if let error { Text(error).foregroundStyle(.orange).lineLimit(3) }
      if let summary {
        usageRow(
          "Recorded tokens",
          summary.tokens.map { $0.formatted(.number.notation(.compactName)) } ?? "Unavailable")
        usageRow("Input / output", "\(count(summary.inputTokens)) / \(count(summary.outputTokens))")
        usageRow(
          "Cache read / write",
          "\(count(summary.cachedTokens)) / \(count(summary.cacheCreationTokens))")
        usageRow(
          "Estimated API cost",
          summary.estimatedCost.map { $0.formatted(.currency(code: "USD")) } ?? "Unavailable")
        ForEach(Array(summary.models.prefix(5))) { model in
          HStack {
            Text(model.name).lineLimit(1).foregroundStyle(.secondary)
            Spacer()
            Text(count(model.tokens)).monospacedDigit()
          }
        }
      } else if error == nil {
        Text("Reading local history…").foregroundStyle(.secondary)
      }
    }.font(.system(size: 11)).padding(.vertical, 10)
  }
  private func count(_ value: Int?) -> String {
    value.map { $0.formatted(.number.notation(.compactName)) } ?? "—"
  }
  private func usageRow(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label).foregroundStyle(.secondary)
      Spacer()
      Text(value).monospacedDigit()
    }
  }
}

extension PRStatus {
  var color: Color {
    switch self {
    case .failed, .conflicts, .changesRequested: .red
    case .review, .waiting, .behind, .blocked: .orange
    case .ready: .green
    case .merged: .purple
    case .checking, .queued: .blue
    default: .gray
    }
  }
  var symbol: String {
    switch self {
    case .merged, .queued: "arrow.triangle.merge"
    case .failed, .conflicts, .changesRequested: "exclamationmark.circle"
    case .checking: "clock"
    case .ready: "checkmark.circle"
    default: "arrow.triangle.pull"
    }
  }
}
