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

/// One PR's page, in place of Activity: who opened it and who's reviewing, then the files it
/// changes beside its checks. A file opens to its diff.
struct PRDetailsView: View {
  let store: IslandStore
  let pr: PullRequest
  @Binding var contentHeight: CGFloat
  @State private var headingHeight: CGFloat = 0
  @State private var bodyHeight: CGFloat = 0

  /// Files and checks share one row height, so the two columns line up.
  static let rowHeight: CGFloat = 28
  static let columnHeaderHeight: CGFloat = 36

  private var details: PullRequestDetails? { store.pullRequestDetails[pr.id] }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      heading
        .padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 12)
        .onGeometryChange(for: CGFloat.self) {
          $0.size.height
        } action: {
          headingHeight = $0
          report()
        }
      Rectangle().fill(Palette.hairline).frame(height: 1).padding(.horizontal, 28)
      Group {
        if let details {
          if let path = store.openFilePath,
            let file = details.files.first(where: { $0.path == path })
          {
            FileDiffView(store: store, file: file) { measured($0) }
          } else {
            GeometryReader { proxy in
              HStack(alignment: .top, spacing: 0) {
                FilesColumn(store: store, pr: pr, details: details) { measured($0, column: 0) }
                  .frame(width: proxy.size.width * 0.57)
                Rectangle().fill(Palette.hairline).frame(width: 1)
                ChecksColumn(details: details) { measured($0, column: 1) }
              }
            }
          }
        } else if let error = store.detailsError {
          Text(error).font(.system(size: 11.5)).foregroundStyle(Palette.attention)
            .textSelection(.enabled).padding(.horizontal, 28).padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) {
              $0.size.height
            } action: {
              measured($0)
            }
        } else {
          HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading the pull request…").font(.system(size: 12))
              .foregroundStyle(.white.opacity(0.5))
          }
          .frame(maxWidth: .infinity).padding(.vertical, 24)
          .onGeometryChange(for: CGFloat.self) {
            $0.size.height
          } action: {
            measured($0)
          }
        }
      }
      .frame(maxHeight: .infinity, alignment: .top)
    }
  }

  @State private var columnHeights: [CGFloat] = [0, 0]

  /// The page is as tall as its taller column, up to the island's limit; past that, each
  /// column scrolls on its own.
  private func measured(_ height: CGFloat, column: Int? = nil) {
    if let column {
      columnHeights[column] = height
      bodyHeight = columnHeights.max() ?? height
    } else {
      bodyHeight = height
    }
    report()
  }

  private func report() { contentHeight = headingHeight + 1 + bodyHeight }

  private var heading: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 10) {
        RepoAvatar(
          url: details?.authorAvatar, size: 22, circular: true, name: details?.author ?? pr.author
        )
        .help(details?.author ?? pr.author ?? "")
        Text(pr.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
          .textSelection(.enabled)
      }
      HStack(spacing: 14) {
        if let details, !details.headRefName.isEmpty {
          Meta(glyph: .branch) {
            Text(verbatim: "\(details.headRefName) → \(details.baseRefName)")
              .font(.system(size: 11, design: .monospaced)).lineLimit(1)
              .truncationMode(.middle)
          }
          .help("\(details.headRefName) into \(details.baseRefName)")
        }
        if let created = details?.createdAt {
          Meta(glyph: .clock) { Text(Format.age(created)) }.help("Opened")
        }
        if let details {
          (Text("+\(details.additions)").foregroundStyle(Palette.open)
            + Text(" −\(details.deletions)").foregroundStyle(Palette.failed))
            .font(.system(size: 11, design: .monospaced))
          Meta(glyph: .commit) { Text("\(details.commitCount)") }
            .help("Commits")
          Meta(glyph: .comment) { Text("\(details.commentCount)") }.help("Comments")
          Spacer(minLength: 8)
          Reviewers(details: details)
        }
      }
      .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
      StackStrip(store: store, pr: pr)
    }
  }
}

/// An icon and a value in the line under the title.
private struct Meta<Value: View>: View {
  var glyph: Glyph?
  var systemImage: String?
  @ViewBuilder let value: Value

  var body: some View {
    HStack(spacing: 5) {
      if let glyph {
        GlyphView(glyph: glyph, size: 12)
      } else if let systemImage {
        Image(systemName: systemImage).font(.system(size: 10.5, weight: .medium))
      }
      value
    }
    .fixedSize()
  }
}

/// Everyone reviewing, as faces: a green dot approved, red asked for changes, amber still asked.
private struct Reviewers: View {
  let details: PullRequestDetails

  var body: some View {
    let reviewed = Set(details.reviews.map(\.author))
    let people: [(name: String, avatar: URL?, color: Color, label: String)] =
      details.reviews.map { review in
        let (label, color) = Self.describe(review.state)
        return (review.author, review.avatar, color, label)
      }
      + details.requestedReviewers.filter { !reviewed.contains($0.name) }.map {
        ($0.name, $0.avatar, Palette.attention, "review requested")
      }
    if !people.isEmpty {
      HStack(spacing: 6) {
        GlyphView(glyph: .eye, size: 13)
        HStack(spacing: -5) {
          ForEach(Array(people.prefix(5).enumerated()), id: \.offset) { _, person in
            RepoAvatar(url: person.avatar, size: 18, circular: true, name: person.name)
              .background(Circle().fill(.black).padding(-1.5))
              .overlay(alignment: .bottomTrailing) {
                Circle().fill(person.color).frame(width: 7, height: 7)
                  .background(Circle().fill(.black).padding(-1.5))
                  .offset(x: 2, y: 2)
              }
              .help("\(person.name) · \(person.label)")
          }
        }
        if people.count > 5 {
          Text("+\(people.count - 5)").font(.system(size: 10.5)).monospacedDigit()
        }
      }
    }
  }

  static func describe(_ state: String) -> (String, Color) {
    switch state {
    case "APPROVED": ("approved", Palette.open)
    case "CHANGES_REQUESTED": ("changes requested", Palette.failed)
    case "DISMISSED": ("dismissed", .white.opacity(0.35))
    default: ("commented", .white.opacity(0.5))
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
      VStack(alignment: .leading, spacing: 6) {
        if chain.count > 1 {
          HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up").font(.system(size: 11, weight: .medium))
              .foregroundStyle(.white.opacity(0.5)).help("Stack")
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
      .padding(.horizontal, 8).padding(.vertical, 3)
      .background(Capsule().fill(.white.opacity(current ? 0.16 : hovered ? 0.11 : 0.06)))
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(current)
    .onHover { hovered = $0 }
    .help(pr.title)
  }
}

/// A column's title with a rule to its counts, which stays put while the column scrolls.
private struct ColumnHeader<Trailing: View>: View {
  let systemImage: String
  let title: String
  @ViewBuilder let trailing: Trailing

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: systemImage).font(.system(size: 11, weight: .medium))
      Text(title)
      Rectangle().fill(Palette.hairline).frame(height: 1)
      trailing
    }
    .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.45))
    .frame(height: PRDetailsView.columnHeaderHeight)
  }
}

/// A column that scrolls once the island reaches its height, and reports how tall it wants to
/// be.
private struct Column<Header: View, Rows: View>: View {
  @ViewBuilder let header: Header
  @ViewBuilder let rows: Rows
  let onHeight: (CGFloat) -> Void

  var body: some View {
    VStack(spacing: 0) {
      header
      ScrollView {
        VStack(spacing: 0) { rows }
          .padding(.bottom, 10)
          .onGeometryChange(for: CGFloat.self) {
            $0.size.height
          } action: {
            onHeight($0 + PRDetailsView.columnHeaderHeight)
          }
      }
      .scrollIndicators(.automatic)
    }
  }
}

private struct FilesColumn: View {
  let store: IslandStore
  let pr: PullRequest
  let details: PullRequestDetails
  let onHeight: (CGFloat) -> Void

  var body: some View {
    Column {
      ColumnHeader(systemImage: "doc", title: "Files") {
        Text("\(details.changedFiles)").monospacedDigit()
      }
    } rows: {
      ForEach(details.files, id: \.path) { file in
        FileRow(file: file) { withAnimation(Motion.snappy) { store.openFile(file.path) } }
      }
      if details.changedFiles > details.files.count {
        // The page reads up to 100 files; GitHub lists the rest.
        Button {
          NSWorkspace.shared.open(pr.url.appending(path: "files"))
        } label: {
          HStack(spacing: 6) {
            Text("\(details.changedFiles - details.files.count) more on GitHub")
            Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold))
          }
          .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
          .frame(maxWidth: .infinity, minHeight: PRDetailsView.rowHeight, alignment: .leading)
          .padding(.leading, 23).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    } onHeight: {
      onHeight($0)
    }
    .padding(.leading, 28).padding(.trailing, 18)
    .frame(maxWidth: .infinity)
  }
}

private struct FileRow: View {
  let file: PullRequestDetails.FileChange
  let action: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        Image(systemName: file.symbol).font(.system(size: 12, weight: .medium))
          .foregroundStyle(file.color).frame(width: 14)
        (Text(file.folder).foregroundStyle(.white.opacity(0.35))
          + Text(file.name).foregroundStyle(.white.opacity(0.9)))
          .font(.system(size: 12)).lineLimit(1).truncationMode(.head)
        Spacer(minLength: 8)
        (Text("+\(file.additions)").foregroundStyle(Palette.open)
          + Text(" −\(file.deletions)").foregroundStyle(Palette.failed))
          .font(.system(size: 10.5, design: .monospaced)).fixedSize()
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.white.opacity(hovered ? 0.7 : 0.3))
      }
      .frame(height: PRDetailsView.rowHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovered = $0 }
    .help(file.path)
  }
}

extension PullRequestDetails.FileChange {
  var symbol: String {
    switch kind {
    case .added: "plus.square"
    case .removed: "minus.square"
    case .renamed: "arrow.right.square"
    case .modified: "dot.square"
    }
  }

  var color: Color {
    switch kind {
    case .added: Palette.open
    case .removed: Palette.failed
    case .renamed, .modified: Palette.merging
    }
  }
}

private struct ChecksColumn: View {
  let details: PullRequestDetails
  let onHeight: (CGFloat) -> Void

  var body: some View {
    let checks = details.sortedChecks
    Column {
      ColumnHeader(systemImage: "checkmark.circle", title: "Checks") {
        HStack(spacing: 8) {
          count(checks, .failed) {
            GlyphView(glyph: .failFill, size: 12).foregroundStyle(Palette.failed)
          }
          count(checks, .running) { RunningRing(size: 11) }
          count(checks, .passed) {
            GlyphView(glyph: .checkFill, size: 12).foregroundStyle(Palette.open)
          }
        }
        .monospacedDigit()
      }
    } rows: {
      if checks.isEmpty {
        Text("No checks on the latest commit").font(.system(size: 11.5))
          .foregroundStyle(.white.opacity(0.45))
          .frame(maxWidth: .infinity, minHeight: PRDetailsView.rowHeight, alignment: .leading)
      }
      ForEach(checks) { CheckRow(check: $0) }
    } onHeight: {
      onHeight($0)
    }
    .padding(.leading, 18).padding(.trailing, 28)
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder private func count<Icon: View>(
    _ checks: [Check], _ outcome: Check.Outcome, @ViewBuilder icon: () -> Icon
  ) -> some View {
    let total = checks.count { $0.outcome == outcome }
    if total > 0 {
      HStack(spacing: 4) {
        icon()
        Text("\(total)")
      }
    }
  }
}

/// A check's state, its job's name, and how long it ran. A failed one links to its log.
private struct CheckRow: View {
  let check: Check
  @State private var hovered = false

  var body: some View {
    Button {
      if let url = check.url { NSWorkspace.shared.open(url) }
    } label: {
      HStack(spacing: 9) {
        Group {
          switch check.outcome {
          case .failed: GlyphView(glyph: .failFill, size: 13).foregroundStyle(Palette.failed)
          case .running: RunningRing(size: 12)
          case .passed: GlyphView(glyph: .checkFill, size: 13).foregroundStyle(Palette.open)
          case .skipped:
            Circle().stroke(.white.opacity(0.3), lineWidth: 1.5).frame(width: 11, height: 11)
          }
        }
        .frame(width: 14)
        Text(check.shortTitle).font(.system(size: 12))
          .foregroundStyle(.white.opacity(check.outcome == .skipped ? 0.45 : 0.9)).lineLimit(1)
        Spacer(minLength: 8)
        if let time {
          Text(time).font(.system(size: 11)).monospacedDigit()
            .foregroundStyle(.white.opacity(0.4))
        }
        if check.outcome == .failed, check.url != nil {
          Image(systemName: "text.alignleft").font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.white.opacity(hovered ? 0.8 : 0.4))
        }
      }
      .frame(height: PRDetailsView.rowHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(check.url == nil)
    .onHover { hovered = $0 }
    .help(check.outcome == .failed ? "\(check.title) · open the log" : check.title)
  }

  private var time: String? {
    if check.outcome == .running, let started = check.startedAt {
      return Format.duration(Date().timeIntervalSince(started))
    }
    return check.duration.map(Format.duration)
  }
}

/// An amber ring with a moving arc, for a check still running.
struct RunningRing: View {
  var size: CGFloat = 12

  var body: some View {
    ZStack {
      Circle().stroke(Palette.merging.opacity(0.3), lineWidth: 1.8)
      Circle().trim(from: 0, to: 0.3)
        .stroke(Palette.merging, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        .phaseAnimator([0.0, 1.0]) { ring, turn in
          ring.rotationEffect(.degrees(turn * 360))
        } animation: { turn in
          turn == 1 ? .linear(duration: 1.2) : nil
        }
    }
    .frame(width: size, height: size)
  }
}

/// One file's changes across the page's width, with a way back to the files.
private struct FileDiffView: View {
  let store: IslandStore
  let file: PullRequestDetails.FileChange
  let onHeight: (CGFloat) -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Button {
          withAnimation(Motion.snappy) { store.closeFile() }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
            Text("Files")
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.white.opacity(0.35))
          }
          .foregroundStyle(.white.opacity(0.5)).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Back to the files")
        Text(file.name).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
          .truncationMode(.middle).help(file.path)
        Rectangle().fill(Palette.hairline).frame(height: 1)
        (Text("+\(file.additions)").foregroundStyle(Palette.open)
          + Text(" −\(file.deletions)").foregroundStyle(Palette.failed))
          .font(.system(size: 11, design: .monospaced)).fixedSize()
      }
      .font(.system(size: 12))
      .frame(height: PRDetailsView.columnHeaderHeight)
      ScrollView {
        content
          .padding(.bottom, 12)
          .onGeometryChange(for: CGFloat.self) {
            $0.size.height
          } action: {
            onHeight($0 + PRDetailsView.columnHeaderHeight)
          }
      }
    }
    .padding(.horizontal, 28)
  }

  @ViewBuilder private var content: some View {
    if let patch = store.openFilePatch() {
      if patch.isEmpty {
        Text("GitHub shows no diff for this file. It may be binary or too large.")
          .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.45))
          .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
      } else {
        DiffLines(lines: Diff.lines(patch))
      }
    } else if let error = store.patchError {
      Text(error).font(.system(size: 11.5)).foregroundStyle(Palette.attention)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
    } else {
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text("Loading the changes…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
      }
      .frame(maxWidth: .infinity).padding(.vertical, 20)
    }
  }
}

private struct DiffLines: View {
  let lines: [Diff.Line]

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
        HStack(alignment: .firstTextBaseline, spacing: 0) {
          Text(line.kind == .hunk ? "" : "\((line.newNumber ?? line.oldNumber) ?? 0)")
            .foregroundStyle(.white.opacity(0.3)).frame(width: 40, alignment: .trailing)
            .padding(.trailing, 12)
          Text(sign(line.kind)).foregroundStyle(signColor(line.kind)).frame(width: 14)
          // Code wraps; a hunk's header is only context, so it keeps to one line.
          Text(line.text.isEmpty ? " " : line.text).foregroundStyle(textColor(line.kind))
            .lineLimit(line.kind == .hunk ? 1 : nil)
            .fixedSize(horizontal: false, vertical: line.kind != .hunk)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.vertical, 2).padding(.trailing, 10)
        .background(background(line.kind))
      }
    }
    .textSelection(.enabled)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.hairline))
  }

  private func sign(_ kind: Diff.Line.Kind) -> String {
    switch kind {
    case .added: "+"
    case .removed: "−"
    case .context, .hunk: ""
    }
  }

  private func signColor(_ kind: Diff.Line.Kind) -> Color {
    kind == .added ? Palette.open : kind == .removed ? Palette.failed : .clear
  }

  private func textColor(_ kind: Diff.Line.Kind) -> Color {
    switch kind {
    case .hunk: .white.opacity(0.45)
    case .added: Color(red: 0.75, green: 0.95, blue: 0.78)
    case .removed: Color(red: 1, green: 0.78, blue: 0.76)
    case .context: .white.opacity(0.85)
    }
  }

  private func background(_ kind: Diff.Line.Kind) -> Color {
    switch kind {
    case .hunk: Palette.update.opacity(0.08)
    case .added: Palette.open.opacity(0.12)
    case .removed: Palette.failed.opacity(0.12)
    case .context: .white.opacity(0.02)
    }
  }
}
