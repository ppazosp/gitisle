import AppKit
import IslandCore
import SwiftUI

extension EnvironmentValues {
  /// What clicking a PR in a list does: open its page in the island. ⌘-click and banners still
  /// open GitHub.
  @Entry var openPullRequest: (PullRequest) -> Void = { NSWorkspace.shared.open($0.url) }
  /// Each open PR's place in its stack, by ID.
  @Entry var stackLinks: [String: PRStacks.Link] = [:]
}

/// One PR's page, in place of Activity: why it's blocked, what failed and why, who's reviewing,
/// and what changed.
struct PRDetailsView: View {
  let store: IslandStore
  let pr: PullRequest
  @Binding var contentHeight: CGFloat

  private var details: PullRequestDetails? { store.pullRequestDetails[pr.id] }

  var body: some View {
    MeasuredColumn {
      VStack(alignment: .leading, spacing: 18) {
        heading
        StackStrip(store: store, pr: pr)
        if let details {
          PreviewsSection(details: details)
          ChecksSection(details: details)
          ReviewsSection(details: details)
          FilesSection(details: details)
          DescriptionSection(markdown: details.body)
          CommentsSection(details: details)
        } else if let error = store.detailsError {
          Text(error).font(.system(size: 11.5)).foregroundStyle(Palette.attention)
            .textSelection(.enabled)
        } else {
          HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading the pull request…").font(.system(size: 12)).foregroundStyle(
              .white.opacity(0.5))
          }
          .frame(maxWidth: .infinity).padding(.vertical, 24)
        }
      }
      .padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
    } onHeight: {
      contentHeight = $0
    }
    // Descriptions and comments come from anyone who can open a PR, so a link in them opens
    // only as a web page, never a file or another app's URL scheme.
    .environment(
      \.openURL, OpenURLAction { url in url.scheme == "https" ? .systemAction : .discarded })
  }

  private var heading: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        GlyphView(glyph: pr.glyph, size: 15).foregroundStyle(pr.glyphColor)
        Text(pr.title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
          .textSelection(.enabled)
      }
      HStack(spacing: 6) {
        Text(pr.stateLabel.text).foregroundStyle(pr.stateLabel.color)
          .padding(.horizontal, 7).padding(.vertical, 2)
          .background(Capsule().fill(pr.stateLabel.color.opacity(0.14)))
        if let author = details?.author ?? pr.author { Text("by \(author)") }
        if let created = details?.createdAt { Text("· opened \(Format.age(created)) ago") }
        if let details, !details.headRefName.isEmpty {
          Text("·")
          Text(verbatim: "\(details.headRefName) → \(details.baseRefName)")
            .font(.system(size: 10.5, design: .monospaced)).lineLimit(1).truncationMode(.middle)
        }
      }
      .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
      if let details {
        HStack(spacing: 8) {
          (Text("+\(details.additions)").foregroundStyle(Palette.open)
            + Text(" −\(details.deletions)").foregroundStyle(Palette.failed))
            .monospacedDigit()
          Text("· \(details.changedFiles) \(details.changedFiles == 1 ? "file" : "files")")
          Text("· \(details.commitCount) \(details.commitCount == 1 ? "commit" : "commits")")
        }
        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
      }
    }
  }
}

/// The PRs this one sits on and those built on it, bottom first; click one to open it.
private struct StackStrip: View {
  let store: IslandStore
  let pr: PullRequest

  var body: some View {
    let link = store.stackLinks[pr.id]
    let chain = PRStacks.chain(of: pr, links: store.stackLinks)
    if chain.count > 1 || link?.mergedParent != nil {
      VStack(alignment: .leading, spacing: 7) {
        if chain.count > 1 {
          DetailsHeader(title: "Stack", trailing: "\(chain.count) PRs")
          ScrollView(.horizontal) {
            HStack(spacing: 6) {
              ForEach(Array(chain.enumerated()), id: \.element.id) { index, member in
                if index > 0 {
                  Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
                }
                StackChip(pr: member, current: member.id == pr.id) {
                  withAnimation(Motion.snappy) { store.openDetails(member) }
                }
              }
            }
          }
          .scrollIndicators(.never)
        }
        if let merged = link?.mergedParent {
          Text(
            "#\(merged.number) merged, but this PR still targets its branch. Retarget it or rebase it onto \(merged.baseRefName ?? "the base branch")."
          )
          .font(.system(size: 11)).foregroundStyle(Palette.attention)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }
}

private struct StackChip: View {
  let pr: PullRequest
  let current: Bool
  let action: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        GlyphView(glyph: pr.glyph, size: 11).foregroundStyle(pr.glyphColor)
        Text(verbatim: "#\(pr.number)").monospacedDigit()
        if pr.state == "OPEN", let summary = pr.checkSummary, summary.failed > 0 {
          GlyphView(glyph: .failFill, size: 10).foregroundStyle(Palette.failed)
        }
      }
      .font(.system(size: 11, weight: current ? .semibold : .medium))
      .foregroundStyle(.white.opacity(current ? 1 : 0.7))
      .padding(.horizontal, 8).padding(.vertical, 4)
      .background(Capsule().fill(.white.opacity(current ? 0.16 : hovered ? 0.11 : 0.06)))
      .overlay(Capsule().strokeBorder(.white.opacity(current ? 0.25 : 0)))
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(current)
    .onHover { hovered = $0 }
    .help(pr.title)
  }
}

/// A section's title, with an optional summary on the right.
private struct DetailsHeader: View {
  let title: String
  var trailing: String?

  var body: some View {
    HStack {
      Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6)
        .foregroundStyle(.white.opacity(0.45))
      Spacer()
      if let trailing {
        Text(trailing).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
      }
    }
  }
}

private struct ChecksSection: View {
  let details: PullRequestDetails
  @State private var showsPassed = false

  var body: some View {
    let checks = details.sortedChecks
    let failed = checks.filter { $0.outcome == .failed && !$0.isSummary }
    let summaries = checks.filter { $0.outcome == .failed && $0.isSummary }
    let running = checks.filter { $0.outcome == .running }
    let done = checks.filter { $0.outcome == .passed || $0.outcome == .skipped }
    VStack(alignment: .leading, spacing: 8) {
      DetailsHeader(title: "Checks", trailing: summary(checks))
      if checks.isEmpty {
        Text("No checks on the latest commit.").font(.system(size: 11.5))
          .foregroundStyle(.white.opacity(0.45))
      }
      ForEach(failed) { FailedCheckRow(check: $0) }
      if !summaries.isEmpty {
        Text("\(summaries.map(\.shortTitle).joined(separator: ", ")) failed as a result")
          .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
      }
      ForEach(running) { CheckLine(check: $0) }
      if !done.isEmpty {
        Button {
          withAnimation(Motion.snappy) { showsPassed.toggle() }
        } label: {
          HStack(spacing: 6) {
            GlyphView(glyph: .checkFill, size: 12).foregroundStyle(Palette.open)
            Text("\(done.count) passed").foregroundStyle(.white.opacity(0.6))
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
              .foregroundStyle(.white.opacity(0.35))
              .rotationEffect(.degrees(showsPassed ? 180 : 0))
          }
          .font(.system(size: 11.5)).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if showsPassed { ForEach(done) { CheckLine(check: $0) } }
      }
    }
  }

  private func summary(_ checks: [Check]) -> String? {
    let failed = checks.count { $0.outcome == .failed }
    let running = checks.count { $0.outcome == .running }
    let passed = checks.count { $0.outcome == .passed }
    let parts = [
      failed > 0 ? "\(failed) failed" : nil, running > 0 ? "\(running) running" : nil,
      passed > 0 ? "\(passed) passed" : nil,
    ].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}

/// A failed check with the errors it reported and a link to its log.
private struct FailedCheckRow: View {
  let check: Check

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      CheckLine(check: check)
      if let summary = check.summary, !summary.isEmpty {
        Text(summary).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
          .textSelection(.enabled).padding(.leading, 22)
      }
      ForEach(Array(check.errors.prefix(3).enumerated()), id: \.offset) { _, error in
        VStack(alignment: .leading, spacing: 2) {
          if let location = error.location {
            Text(location).font(.system(size: 10, design: .monospaced))
              .foregroundStyle(.white.opacity(0.45))
          }
          Text(error.headline).font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white.opacity(0.85)).lineLimit(3).textSelection(.enabled)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.failed.opacity(0.08)))
        .padding(.leading, 22)
      }
      if check.errors.count > 3 {
        Text("\(check.errors.count - 3) more in the log").font(.system(size: 10.5))
          .foregroundStyle(.white.opacity(0.4)).padding(.leading, 22)
      }
    }
  }
}

/// A check's state, name, time, and a link to its log.
private struct CheckLine: View {
  let check: Check

  var body: some View {
    HStack(spacing: 8) {
      Group {
        switch check.outcome {
        case .failed: GlyphView(glyph: .failFill, size: 13).foregroundStyle(Palette.failed)
        case .running: ProgressView().controlSize(.mini).frame(width: 13, height: 13)
        case .passed: GlyphView(glyph: .checkFill, size: 13).foregroundStyle(Palette.open)
        case .skipped:
          Circle().stroke(.white.opacity(0.3), lineWidth: 1.5).frame(width: 11, height: 11)
        }
      }
      .frame(width: 14)
      Text(check.title).font(
        .system(size: 12, weight: check.outcome == .failed ? .semibold : .regular)
      )
      .foregroundStyle(.white.opacity(check.outcome == .skipped ? 0.5 : 0.9)).lineLimit(1)
      Spacer(minLength: 8)
      if let time {
        Text(time).font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.white.opacity(0.4))
      }
      if let url = check.url {
        LinkButton(title: "Log", url: url)
      }
    }
  }

  private var time: String? {
    if check.outcome == .running, let started = check.startedAt {
      return "running \(Format.duration(Date().timeIntervalSince(started)))"
    }
    return check.duration.map(Format.duration)
  }
}

private struct PreviewsSection: View {
  let details: PullRequestDetails

  var body: some View {
    if !details.previews.isEmpty {
      VStack(alignment: .leading, spacing: 7) {
        DetailsHeader(title: "Previews")
        ForEach(details.previews, id: \.name) { preview in
          HStack(spacing: 8) {
            GlyphView(glyph: .linkExternal, size: 12)
              .foregroundStyle(preview.state == .failed ? Palette.failed : Palette.update)
              .frame(width: 14)
            Text(preview.name).font(.system(size: 12, weight: .medium))
            Text(Self.label(preview.state)).font(.system(size: 11))
              .foregroundStyle(preview.state == .failed ? Palette.failed : .white.opacity(0.45))
            Spacer(minLength: 8)
            if let url = preview.url {
              Text(url.host() ?? "").font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35)).lineLimit(1).truncationMode(.middle)
              LinkButton(title: "Open", url: url)
            }
          }
        }
      }
    }
  }

  static func label(_ state: PreviewDeploy.State) -> String {
    switch state {
    case .ready: "Ready"
    case .building: "Building…"
    case .failed: "Failed"
    }
  }
}

private struct ReviewsSection: View {
  let details: PullRequestDetails

  var body: some View {
    let reviewers = Set(details.reviews.map(\.author))
    let waiting = details.requestedReviewers.filter { !reviewers.contains($0) }
    if !details.reviews.isEmpty || !waiting.isEmpty {
      VStack(alignment: .leading, spacing: 7) {
        DetailsHeader(title: "Reviews")
        ForEach(details.reviews, id: \.author) { review in
          let (label, color) = Self.describe(review.state)
          HStack(spacing: 8) {
            Text(review.author).font(.system(size: 12, weight: .medium))
            Text(label).font(.system(size: 11)).foregroundStyle(color)
            Spacer()
            if let submitted = review.submittedAt {
              Text(Format.age(submitted)).font(.system(size: 10.5)).foregroundStyle(
                .white.opacity(0.4))
            }
          }
        }
        ForEach(waiting, id: \.self) { reviewer in
          HStack(spacing: 8) {
            Text(reviewer).font(.system(size: 12, weight: .medium))
            Text("Review requested").font(.system(size: 11)).foregroundStyle(Palette.attention)
          }
        }
      }
    }
  }

  static func describe(_ state: String) -> (String, Color) {
    switch state {
    case "APPROVED": ("Approved", Palette.open)
    case "CHANGES_REQUESTED": ("Changes requested", Palette.failed)
    case "DISMISSED": ("Dismissed", .white.opacity(0.4))
    default: ("Commented", .white.opacity(0.5))
    }
  }
}

private struct FilesSection: View {
  let details: PullRequestDetails
  @State private var showsAll = false

  var body: some View {
    if !details.files.isEmpty {
      let files = details.files.sorted { $0.additions + $0.deletions > $1.additions + $1.deletions }
      let shown = showsAll ? files : Array(files.prefix(6))
      VStack(alignment: .leading, spacing: 5) {
        DetailsHeader(title: "Files", trailing: "\(details.changedFiles) changed")
        ForEach(shown, id: \.path) { file in
          HStack(spacing: 8) {
            Text(file.path).font(.system(size: 11, design: .monospaced))
              .foregroundStyle(.white.opacity(0.8)).lineLimit(1).truncationMode(.head)
            Spacer(minLength: 8)
            (Text("+\(file.additions)").foregroundStyle(Palette.open)
              + Text(" −\(file.deletions)").foregroundStyle(Palette.failed))
              .font(.system(size: 10.5)).monospacedDigit()
          }
        }
        if details.changedFiles > shown.count {
          if files.count > shown.count {
            ShowMoreButton(hidden: files.count - shown.count) {
              withAnimation(Motion.snappy) { showsAll = true }
            }
          } else {
            Text("and \(details.changedFiles - shown.count) more").font(.system(size: 10.5))
              .foregroundStyle(.white.opacity(0.4))
          }
        }
      }
    }
  }
}

private struct DescriptionSection: View {
  let markdown: String
  @State private var expanded = false

  var body: some View {
    let text = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.isEmpty {
      VStack(alignment: .leading, spacing: 7) {
        DetailsHeader(title: "Description")
        Text(Self.rendered(text)).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
          .lineLimit(expanded ? nil : 8).textSelection(.enabled)
          .tint(Palette.update)
        if !expanded && text.split(whereSeparator: \.isNewline).count > 8 {
          Button("Show more") { withAnimation(Motion.snappy) { expanded = true } }
            .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
        }
      }
    }
  }

  /// Links, bold, and code render; block syntax shows as written.
  static func rendered(_ text: String) -> AttributedString {
    (try? AttributedString(
      markdown: text,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(text)
  }
}

private struct CommentsSection: View {
  let details: PullRequestDetails

  var body: some View {
    if !details.comments.isEmpty {
      VStack(alignment: .leading, spacing: 9) {
        DetailsHeader(
          title: "Comments",
          trailing: details.commentCount > details.comments.count
            ? "latest of \(details.commentCount)" : nil)
        ForEach(Array(details.comments.suffix(3).enumerated()), id: \.offset) { _, comment in
          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
              Text(comment.author).font(.system(size: 11.5, weight: .semibold))
              Text(Format.age(comment.createdAt)).font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.4))
            }
            Text(comment.body).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.75))
              .lineLimit(4).textSelection(.enabled)
          }
        }
      }
    }
  }
}

/// A small link that opens in the browser.
struct LinkButton: View {
  let title: String
  let url: URL
  @State private var hovered = false

  var body: some View {
    Button {
      NSWorkspace.shared.open(url)
    } label: {
      HStack(spacing: 3) {
        Text(title)
        Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold))
      }
      .font(.system(size: 10.5, weight: .medium))
      .foregroundStyle(.white.opacity(hovered ? 0.95 : 0.6))
      .padding(.horizontal, 7).padding(.vertical, 3)
      .background(Capsule().fill(.white.opacity(hovered ? 0.14 : 0.07)))
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { hovered = $0 }
    .help(url.absoluteString)
  }
}
