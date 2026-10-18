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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            .transition(.opacity)
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
          // The columns' shape from what the list already knows, so loading doesn't jump.
          LoadingColumns(pr: pr) { measured($0) }
            .transition(.opacity)
        }
      }
      .frame(maxHeight: .infinity, alignment: .top)
      // Placeholders fade into the page as it arrives; its rows then come in one by one.
      .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: details != nil)
    }
    // Back from a file, the page returns to its columns' height; they don't measure again.
    .onChange(of: store.openFilePath) { _, path in
      if path == nil, let tallest = columnHeights.max(), tallest > 0 {
        bodyHeight = tallest
        report()
      }
    }
  }

  @State private var columnHeights: [CGFloat] = [0, 0]

  /// The page is as tall as its taller column, up to the island's limit; past that, each
  /// column scrolls on its own.
  private func measured(_ height: CGFloat, column: Int? = nil) {
    if let column {
      columnHeights[column] = height
      if store.openFilePath == nil { bodyHeight = columnHeights.max() ?? height }
    } else {
      bodyHeight = height
    }
    report()
  }

  private func report() { contentHeight = headingHeight + 1 + bodyHeight }

  /// Drawn from the list's copy of the PR first, then its page once read, so it doesn't jump.
  private var heading: some View {
    let head = details?.headRefName ?? pr.headRefName ?? ""
    let base = details?.baseRefName ?? pr.baseRefName ?? ""
    let additions = details?.additions ?? pr.additions
    let deletions = details?.deletions ?? pr.deletions
    let commits = details?.commitCount ?? pr.commitCount
    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 10) {
        RepoAvatar(
          url: details?.authorAvatar ?? pr.authorAvatar, size: 22, circular: true,
          name: details?.author ?? pr.author
        )
        .help(details?.author ?? pr.author ?? "")
        Text(pr.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
      HStack(spacing: 14) {
        if !head.isEmpty {
          // Each branch shortens on its own, sharing the room, so the arrow always shows.
          HStack(spacing: 5) {
            GlyphView(glyph: .branch, size: 12)
            BranchChip(name: head)
            Image(systemName: "arrow.right").font(.system(size: 8.5, weight: .bold))
              .foregroundStyle(.white.opacity(0.35))
            BranchChip(name: base)
          }
          .help("\(head) into \(base)")
        }
        if let created = details?.createdAt ?? pr.createdAt {
          Meta(glyph: .clock) { Text(Format.age(created)) }.help("Opened")
        }
        if let additions, let deletions {
          (Text("+\(additions)").foregroundStyle(Palette.open)
            + Text(" −\(deletions)").foregroundStyle(Palette.failed))
            .font(.system(size: 11, design: .monospaced)).fixedSize()
        }
        if let commits { Meta(glyph: .commit) { Text("\(commits)") }.help("Commits") }
        if let details {
          Meta(glyph: .comment) { Text("\(details.commentCount)") }.help("Comments")
            .transition(.opacity)
        }
        Spacer(minLength: 8)
        if let details { Reviewers(details: details).fixedSize().transition(.opacity) }
      }
      .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: details != nil)
      // As tall as the reviewers' faces, so the line doesn't grow when they load.
      .frame(minHeight: 20)
      .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
      StackStrip(store: store, pr: pr)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// A branch name, monospaced and shortened in the middle when the line is tight.
private struct BranchChip: View {
  let name: String

  var body: some View {
    Text(verbatim: name).font(.system(size: 11, design: .monospaced)).lineLimit(1)
      .truncationMode(.middle)
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
    // Newest review first, then those still asked; the first face sits on top.
    let newest = details.reviews.sorted {
      ($0.submittedAt ?? .distantPast) > ($1.submittedAt ?? .distantPast)
    }
    let people: [(name: String, avatar: URL?, color: Color, label: String)] =
      newest.map { review in
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
          ForEach(Array(people.prefix(5).enumerated()), id: \.offset) { index, person in
            // On white, as GitHub shows them: bots' logos are often dark and see-through.
            RepoAvatar(url: person.avatar, size: 18, circular: true, name: person.name)
              .background(Circle().fill(person.avatar == nil ? .clear : .white))
              .background(Circle().fill(.black).padding(-1.5))
              .overlay(alignment: .bottomTrailing) {
                Circle().fill(person.color).frame(width: 7, height: 7)
                  .background(Circle().fill(.black).padding(-1.5))
                  .offset(x: 2, y: 2)
              }
              .help("\(person.name) · \(person.label)")
              .zIndex(Double(-index))
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
      // Like the rest of the island, without a scroll bar over the rows.
      .scrollIndicators(.never)
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
      ForEach(
        Array(FileTree.rows(details.files, folded: store.foldedFolders).enumerated()), id: \.offset
      ) { index, row in
        Group {
          switch row.kind {
          case .folder(let name, let path, let folded):
            FolderRow(name: name, folded: folded, depth: row.depth) {
              withAnimation(Motion.snappy) { store.toggleFolder(path) }
            }
          case .file(let file):
            FileRow(file: file, depth: row.depth) {
              withAnimation(Motion.snappy) { store.openFile(file.path) }
            }
          }
        }
        .arriving(index)
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

/// How far each level of the file tree steps in.
private let treeIndent: CGFloat = 14

/// A folder in the file tree; click it to fold or unfold what's inside.
private struct FolderRow: View {
  let name: String
  let folded: Bool
  let depth: Int
  let action: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "chevron.right").font(.system(size: 8.5, weight: .bold))
          .foregroundStyle(.white.opacity(hovered ? 0.7 : 0.4))
          .rotationEffect(.degrees(folded ? 0 : 90)).frame(width: 10)
        Image(systemName: "folder").font(.system(size: 11.5))
          .foregroundStyle(.white.opacity(0.45))
        Text(name).font(.system(size: 12)).foregroundStyle(.white.opacity(0.62))
          .lineLimit(1).truncationMode(.middle)
        Spacer(minLength: 0)
      }
      .padding(.leading, CGFloat(depth) * treeIndent)
      .frame(height: PRDetailsView.rowHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovered = $0 }
    .help(name)
  }
}

private struct FileRow: View {
  let file: PullRequestDetails.FileChange
  let depth: Int
  let action: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: file.symbol).font(.system(size: 12, weight: .medium))
          .foregroundStyle(file.color).frame(width: 14)
        Text(file.name).foregroundStyle(.white.opacity(0.9))
          .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
        Spacer(minLength: 8)
        (Text("+\(file.additions)").foregroundStyle(Palette.open)
          + Text(" −\(file.deletions)").foregroundStyle(Palette.failed))
          .font(.system(size: 10.5, design: .monospaced)).fixedSize()
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.white.opacity(hovered ? 0.7 : 0.3))
      }
      // A file's icon lines up with its sibling folders' icons, past their chevrons.
      .padding(.leading, CGFloat(depth) * treeIndent + 16)
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
      ForEach(Array(checks.enumerated()), id: \.element.id) { index, check in
        CheckRow(check: check).arriving(index)
      }
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
  /// One column or side by side; the choice stays for the next file.
  @AppStorage("diffLayout") private var layout: DiffLayout = .unified

  enum DiffLayout: String {
    case unified, split
  }

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
        HStack(spacing: 2) {
          LayoutButton(systemImage: "rectangle", label: "One column", on: layout == .unified) {
            layout = .unified
          }
          LayoutButton(
            systemImage: "rectangle.split.2x1", label: "Side by side", on: layout == .split
          ) {
            layout = .split
          }
        }
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
      .scrollIndicators(.never)
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
        DiffLines(lines: Diff.lines(patch), split: layout == .split)
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

/// One file's diff, as one column of old and new lines, or side by side with the old file on
/// the left and the new on the right. Inside a changed line, the words that changed stand out.
private struct DiffLines: View {
  let lines: [Diff.Line]
  let split: Bool

  var body: some View {
    let marks = Diff.highlights(lines)
    LazyVStack(alignment: .leading, spacing: 0) {
      if split {
        ForEach(Array(Diff.split(lines).enumerated()), id: \.offset) { _, row in
          if let hunk = row.hunk {
            HunkRow(line: lines[hunk])
          } else {
            HStack(alignment: .top, spacing: 0) {
              half(row.left, number: \.oldNumber, marks: marks)
              Rectangle().fill(Palette.hairline).frame(width: 1)
              half(row.right, number: \.newNumber, marks: marks)
            }
            .fixedSize(horizontal: false, vertical: true)
          }
        }
      } else {
        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
          if line.kind == .hunk {
            HunkRow(line: line)
          } else {
            CodeLine(
              line: line, number: line.newNumber ?? line.oldNumber, segments: marks[index])
          }
        }
      }
    }
    .textSelection(.enabled)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.hairline))
  }

  /// One side of a side-by-side row; empty where the other side has no counterpart.
  @ViewBuilder private func half(
    _ index: Int?, number: KeyPath<Diff.Line, Int?>, marks: [Int: [Diff.Segment]]
  ) -> some View {
    if let index {
      let line = lines[index]
      CodeLine(line: line, number: line[keyPath: number], segments: marks[index])
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DiffStyle.background(line.kind))
    } else {
      Color.white.opacity(0.025).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

/// "@@ -52,9 +52,21 @@ func name(" across the diff's width: only context, so one line.
private struct HunkRow: View {
  let line: Diff.Line

  var body: some View {
    Text(line.text).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
      .font(.system(size: 11, design: .monospaced))
      .padding(.leading, 66).padding(.vertical, 2).padding(.trailing, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(DiffStyle.background(.hunk))
  }
}

/// A line of code with its number and sign. Code wraps rather than scrolling sideways.
private struct CodeLine: View {
  let line: Diff.Line
  let number: Int?
  let segments: [Diff.Segment]?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 0) {
      Text(number.map(String.init) ?? "")
        .foregroundStyle(.white.opacity(0.3)).frame(width: 40, alignment: .trailing)
        .padding(.trailing, 12)
      Text(DiffStyle.sign(line.kind)).foregroundStyle(DiffStyle.signColor(line.kind))
        .frame(width: 14)
      Text(code).foregroundStyle(DiffStyle.textColor(line.kind))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.system(size: 11, design: .monospaced))
    .padding(.vertical, 2).padding(.trailing, 10)
    .background(DiffStyle.background(line.kind))
  }

  /// The line, with the words that changed on a stronger tint.
  private var code: AttributedString {
    guard let segments else { return AttributedString(line.text.isEmpty ? " " : line.text) }
    var result = AttributedString()
    for segment in segments {
      var piece = AttributedString(segment.text)
      if segment.changed { piece.backgroundColor = DiffStyle.mark(line.kind) }
      result += piece
    }
    return result
  }
}

private enum DiffStyle {
  static func sign(_ kind: Diff.Line.Kind) -> String {
    switch kind {
    case .added: "+"
    case .removed: "−"
    case .context, .hunk: ""
    }
  }

  static func signColor(_ kind: Diff.Line.Kind) -> Color {
    kind == .added ? Palette.open : kind == .removed ? Palette.failed : .clear
  }

  static func textColor(_ kind: Diff.Line.Kind) -> Color {
    switch kind {
    case .hunk: .white.opacity(0.45)
    case .added: Color(red: 0.75, green: 0.95, blue: 0.78)
    case .removed: Color(red: 1, green: 0.78, blue: 0.76)
    case .context: .white.opacity(0.85)
    }
  }

  static func background(_ kind: Diff.Line.Kind) -> Color {
    switch kind {
    case .hunk: Palette.update.opacity(0.08)
    case .added: Palette.open.opacity(0.12)
    case .removed: Palette.failed.opacity(0.12)
    case .context: .white.opacity(0.02)
    }
  }

  /// Behind the words that changed inside a changed line.
  static func mark(_ kind: Diff.Line.Kind) -> Color {
    kind == .added ? Palette.open.opacity(0.4) : Palette.failed.opacity(0.42)
  }
}

/// The two columns while the page loads: their headers with what the list already knows, and
/// faint rows where files and checks will be.
private struct LoadingColumns: View {
  let pr: PullRequest
  let onHeight: (CGFloat) -> Void

  var body: some View {
    let files = min(pr.changedFiles ?? 4, 12)
    let checks = min(pr.checkSummary?.total ?? 4, 12)
    GeometryReader { proxy in
      HStack(alignment: .top, spacing: 0) {
        VStack(spacing: 0) {
          ColumnHeader(systemImage: "doc", title: "Files") {
            if let count = pr.changedFiles { Text("\(count)").monospacedDigit() }
          }
          ForEach(0..<files, id: \.self) { PlaceholderRow(index: $0) }
        }
        .padding(.leading, 28).padding(.trailing, 18)
        .frame(width: proxy.size.width * 0.57)
        Rectangle().fill(Palette.hairline).frame(width: 1)
        VStack(spacing: 0) {
          ColumnHeader(systemImage: "checkmark.circle", title: "Checks") {
            if let summary = pr.checkSummary {
              HStack(spacing: 8) {
                if summary.failed > 0 {
                  HStack(spacing: 4) {
                    GlyphView(glyph: .failFill, size: 12).foregroundStyle(Palette.failed)
                    Text("\(summary.failed)")
                  }
                }
                if summary.pending > 0 {
                  HStack(spacing: 4) {
                    RunningRing(size: 11)
                    Text("\(summary.pending)")
                  }
                }
                if summary.passed > 0 {
                  HStack(spacing: 4) {
                    GlyphView(glyph: .checkFill, size: 12).foregroundStyle(Palette.open)
                    Text("\(summary.passed)")
                  }
                }
              }
              .monospacedDigit()
            }
          }
          ForEach(0..<checks, id: \.self) { PlaceholderRow(index: $0 + 3) }
        }
        .padding(.leading, 18).padding(.trailing, 28)
      }
    }
    .onAppear {
      onHeight(
        PRDetailsView.columnHeaderHeight + CGFloat(max(files, checks)) * PRDetailsView.rowHeight
          + 10)
    }
  }
}

/// A faint row standing in for a file or check that hasn't loaded.
private struct PlaceholderRow: View {
  let index: Int

  var body: some View {
    let widths: [CGFloat] = [0.62, 0.45, 0.7, 0.52, 0.38, 0.58, 0.66, 0.42]
    GeometryReader { proxy in
      HStack(spacing: 9) {
        RoundedRectangle(cornerRadius: 3.5).fill(.white.opacity(0.07)).frame(width: 14, height: 14)
        RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.07))
          .frame(width: proxy.size.width * widths[index % widths.count], height: 9)
        Spacer(minLength: 0)
      }
      .frame(maxHeight: .infinity)
    }
    .frame(height: PRDetailsView.rowHeight)
  }
}

extension View {
  /// Fades a row in and lifts it into place when it first shows, a beat after the one above.
  func arriving(_ index: Int) -> some View { modifier(Arriving(index: index)) }
}

private struct Arriving: ViewModifier {
  let index: Int
  @State private var shown = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .opacity(shown || reduceMotion ? 1 : 0)
      .offset(y: shown || reduceMotion ? 0 : 5)
      .onAppear {
        guard !shown else { return }
        // Long lists stop staggering after a dozen rows, so the last ones don't lag.
        withAnimation(.easeOut(duration: 0.26).delay(Double(min(index, 12)) * 0.025)) {
          shown = true
        }
      }
  }
}

/// A plain icon choosing how a diff is laid out, bright when chosen.
private struct LayoutButton: View {
  let systemImage: String
  let label: String
  let on: Bool
  let action: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage).font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(on ? 0.9 : hovered ? 0.6 : 0.35))
        .frame(width: 22, height: 20).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovered = $0 }
    .help(label)
  }
}
