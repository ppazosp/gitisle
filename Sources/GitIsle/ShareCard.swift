import AppKit
import IslandCore
import SwiftUI

/// An image of a PR to post: whose repository, who wrote it, its state, and how much it changed.
/// Rendered from SwiftUI at twice its 1200 × 630 size, the shape link previews use.
struct ShareCard: View {
  let pr: PullRequest
  let details: PullRequestDetails
  /// The repository owner's and the author's pictures, read before rendering since an image
  /// renderer can't wait for them.
  var repoImage: NSImage?
  var authorImage: NSImage?

  static let size = CGSize(width: 1200, height: 630)
  /// The palm tree without the icon's backing, which the app bundle carries; builds run
  /// outside the bundle use the app icon.
  @MainActor static let logo =
    Bundle.main.image(forResource: "Logo") ?? NSApp.applicationIconImage ?? NSImage()

  /// "5,159": the card is posted for anyone to read, so it doesn't follow this Mac's locale.
  static func count(_ value: Int) -> String {
    value.formatted(.number.locale(Locale(identifier: "en_US")))
  }

  var body: some View {
    ZStack {
      Color.black
      ZStack { background }
        .frame(width: Self.size.width, height: Self.size.height).clipped()
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 16) {
          picture(repoImage, size: 52, circular: false, fallback: pr.repository)
          let parts = pr.repository.split(separator: "/").map(String.init)
          (Text(verbatim: parts.count == 2 ? "\(parts[0])/" : "").foregroundStyle(
            .white.opacity(0.5))
            + Text(verbatim: parts.last ?? pr.repository))
            .font(.system(size: 30, weight: .semibold))
          Text(verbatim: "#\(pr.number)").font(.system(size: 30, weight: .medium))
            .foregroundStyle(.white.opacity(0.4))
          Spacer()
          let tag = stateTag
          HStack(spacing: 8) {
            GlyphView(glyph: tag.glyph, size: 20)
            Text(tag.label)
          }
          .font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
          .padding(.horizontal, 18).padding(.vertical, 9)
          .background(Capsule().fill(tag.color))
        }
        Spacer(minLength: 24)
        Text(pr.title).font(.system(size: 58, weight: .bold)).tracking(-1.4)
          .lineLimit(2).minimumScaleFactor(0.6)
        HStack(spacing: 14) {
          let author = details.author ?? pr.author ?? ""
          picture(authorImage, size: 40, circular: true, fallback: author)
          Text(author).font(.system(size: 26, weight: .medium))
          if let timing {
            Text("· \(timing)").font(.system(size: 24)).foregroundStyle(.white.opacity(0.5))
          }
        }
        .padding(.top, 22)
        Spacer(minLength: 24)
        HStack(alignment: .lastTextBaseline, spacing: 56) {
          Stat(
            value: "+\(Self.count(details.additions))", label: "lines added", color: Palette.open)
          Stat(
            value: "−\(Self.count(details.deletions))", label: "lines removed",
            color: Palette.failed
          )
          Stat(
            value: Self.count(details.changedFiles),
            label: details.changedFiles == 1 ? "file touched" : "files touched")
          Spacer(minLength: 0)
          // GitIsle signs the card once, with its logo.
          Image(nsImage: Self.logo).resizable().interpolation(.high)
            .aspectRatio(contentMode: .fit).frame(width: 112, height: 112)
            .padding(.vertical, -26)
        }
      }
      .padding(64)
    }
    .foregroundStyle(.white)
    .frame(width: Self.size.width, height: Self.size.height)
    .clipped()
    .environment(\.colorScheme, .dark)
  }

  @ViewBuilder private func picture(
    _ image: NSImage?, size: CGFloat, circular: Bool, fallback: String
  ) -> some View {
    let shape = RoundedRectangle(
      cornerRadius: circular ? size / 2 : size * 0.24, style: .continuous)
    if let image {
      Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
        .clipShape(shape)
    } else {
      Text(String(fallback.first ?? "?").uppercased())
        .font(.system(size: size * 0.48, weight: .semibold))
        .frame(width: size, height: size)
        .background(shape.fill(.white.opacity(0.14)))
    }
  }

  /// Contribution-graph tiles in GitHub's greens, a pattern of its own for each PR, fading in
  /// behind the words.
  @ViewBuilder private var background: some View {
    Canvas { context, size in
      var seed: UInt64 = 0xA076_1D64_78BD_642F &+ UInt64(pr.number)
      func next() -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(seed >> 33) / Double(UInt64(1) << 31)
      }
      let cell: CGFloat = 26
      for column in 0..<Int(size.width / cell) + 1 {
        for row in 0..<Int(size.height / cell) + 1 {
          let level = next()
          let opacity = level < 0.45 ? 0.05 : level < 0.7 ? 0.14 : level < 0.88 ? 0.26 : 0.42
          context.fill(
            Path(
              roundedRect: CGRect(
                x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell - 5,
                height: cell - 5), cornerRadius: 4),
            with: .color(Palette.open.opacity(opacity)))
        }
      }
    }
    LinearGradient(
      colors: [.black.opacity(0.92), .black.opacity(0.55)], startPoint: .leading,
      endPoint: .trailing)
  }

  /// The PR's state as GitHub colours it: merged, merging, open, draft, or closed.
  private var stateTag: (glyph: Glyph, label: String, color: Color) {
    switch pr.group {
    case .merged: (.merge, "Merged", Palette.merged)
    case .merging: (.mergeQueue, "Merging", Palette.merging)
    case .draft: (.draft, "Draft", Palette.draft)
    case .open: (.pullRequest, "Open", Palette.open)
    case nil: (.closed, "Closed", Palette.failed)
    }
  }

  /// "merged after 3h 12m", from opening to merging, or "opened 2h ago" for one still open.
  private var timing: String? {
    guard let created = details.createdAt ?? pr.createdAt else { return nil }
    if let merged = pr.mergedAt {
      let seconds = merged.timeIntervalSince(created)
      return "merged after "
        + (seconds < 86_400 * 2 ? Format.duration(seconds) : "\(Int(seconds / 86_400)) days")
    }
    let age = Format.age(created)
    return age == "now" ? "opened just now" : "opened \(age) ago"
  }

  /// The card as a PNG, at twice its size.
  @MainActor func png() -> Data? {
    let renderer = ImageRenderer(content: self)
    renderer.scale = 2
    guard let image = renderer.cgImage else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
  }
}

private struct Stat: View {
  let value: String
  let label: String
  var color: Color = .white

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(value).font(.system(size: 40, weight: .semibold)).monospacedDigit().foregroundStyle(
        color)
      Text(label).font(.system(size: 19)).foregroundStyle(.white.opacity(0.5))
    }
  }
}

/// "Copy card" and "Save card…" for a PR, in a menu or a context menu.
struct ShareCardActions: View {
  let store: IslandStore
  let pr: PullRequest

  var body: some View {
    Button("Copy share card") { Task { await store.copyShareCard(for: pr) } }
    Button("Save share card…") { Task { await store.saveShareCard(for: pr) } }
  }
}
