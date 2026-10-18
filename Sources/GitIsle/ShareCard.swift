import AppKit
import IslandCore
import SwiftUI

/// An image of a merged PR to post: whose repository, who wrote it, and how much it changed.
/// Rendered from SwiftUI at twice its 1200 × 630 size, the shape link previews use.
struct ShareCard: View {
  let pr: PullRequest
  let details: PullRequestDetails
  /// The repository owner's and the author's pictures, read before rendering since an image
  /// renderer can't wait for them.
  var repoImage: NSImage?
  var authorImage: NSImage?
  var backdrop: Backdrop = .aurora

  static let size = CGSize(width: 1200, height: 630)

  enum Backdrop: String, CaseIterable {
    case aurora, merged, grid, diff, contributions, avatar
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
          HStack(spacing: 8) {
            GlyphView(glyph: .merge, size: 20)
            Text("Merged")
          }
          .font(.system(size: 22, weight: .semibold)).foregroundStyle(Palette.merged)
          .padding(.horizontal, 16).padding(.vertical, 8)
          .background(Capsule().fill(Palette.merged.opacity(0.18)))
        }
        Spacer(minLength: 24)
        Text(pr.title).font(.system(size: 58, weight: .bold)).tracking(-1.4)
          .lineLimit(2).minimumScaleFactor(0.6)
        HStack(spacing: 14) {
          let author = details.author ?? pr.author ?? ""
          picture(authorImage, size: 40, circular: true, fallback: author)
          Text(author).font(.system(size: 26, weight: .medium))
          if let open = openFor {
            Text("· merged after \(open)").font(.system(size: 24))
              .foregroundStyle(.white.opacity(0.5))
          }
        }
        .padding(.top, 22)
        Spacer(minLength: 24)
        HStack(alignment: .lastTextBaseline, spacing: 56) {
          Stat(
            value: "+\(details.additions.formatted())", label: "lines added", color: Palette.open)
          Stat(
            value: "−\(details.deletions.formatted())", label: "lines removed",
            color: Palette.failed
          )
          Stat(
            value: details.changedFiles.formatted(),
            label: details.changedFiles == 1 ? "file touched" : "files touched")
          Spacer(minLength: 0)
          Text("gitisle.ppazosp.dev").font(.system(size: 17)).foregroundStyle(.white.opacity(0.3))
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

  @ViewBuilder private var background: some View {
    switch backdrop {
    case .aurora:
      RadialGradient(
        colors: [Palette.open.opacity(0.22), .clear], center: .bottomLeading, startRadius: 0,
        endRadius: 620)
      RadialGradient(
        colors: [Palette.merged.opacity(0.3), .clear], center: .bottomTrailing, startRadius: 0,
        endRadius: 660)
    case .merged:
      LinearGradient(
        colors: [
          Color(red: 0.24, green: 0.12, blue: 0.45), Color(red: 0.06, green: 0.03, blue: 0.12),
        ],
        startPoint: .topTrailing, endPoint: .bottomLeading)
      RadialGradient(
        colors: [Palette.merged.opacity(0.45), .clear], center: .topTrailing, startRadius: 0,
        endRadius: 700)
    case .grid:
      Canvas { context, size in
        for x in stride(from: 0, through: size.width, by: 32) {
          for y in stride(from: 0, through: size.height, by: 32) {
            context.fill(
              Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)),
              with: .color(.white.opacity(0.13)))
          }
        }
      }
      RadialGradient(
        colors: [Palette.merged.opacity(0.35), .clear], center: .top, startRadius: 0,
        endRadius: 600)
      LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
    case .diff:
      // Faint diff lines across the card, added and removed in the PR's own proportion.
      Canvas { context, size in
        let share =
          Double(details.additions) / Double(max(1, details.additions + details.deletions))
        var y: CGFloat = 0
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15 &+ UInt64(pr.number)
        func next() -> Double {
          seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
          return Double(seed >> 33) / Double(UInt64(1) << 31)
        }
        while y < size.height {
          let roll = next()
          let color: Color =
            roll < share * 0.7 ? Palette.open : roll < 0.7 ? Palette.failed : .white
          let opacity = color == .white ? 0.06 : 0.24
          let indent = CGFloat(Int(next() * 4)) * 34
          let width = CGFloat(160 + next() * 620)
          context.fill(
            Path(
              roundedRect: CGRect(
                x: size.width - width - indent - 40, y: y, width: width, height: 12),
              cornerRadius: 6), with: .color(color.opacity(opacity)))
          y += 26
        }
      }
      LinearGradient(
        colors: [.black, .black.opacity(0.75), .black.opacity(0.2)], startPoint: .leading,
        endPoint: .trailing)
    case .contributions:
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
    case .avatar:
      // The repository's own picture, blown up and blurred, so each project gets its colours.
      if let image = repoImage ?? NSApp.applicationIconImage {
        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
          .frame(width: Self.size.width * 1.3, height: Self.size.height * 1.3)
          .blur(radius: 90).saturation(1.4).opacity(0.75)
      }
      LinearGradient(
        colors: [.black.opacity(0.35), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
    }
  }

  /// "3h 12m", from opening to merging.
  private var openFor: String? {
    guard let created = details.createdAt ?? pr.createdAt, let merged = pr.mergedAt else {
      return nil
    }
    let seconds = merged.timeIntervalSince(created)
    return seconds < 86_400 * 2
      ? Format.duration(seconds) : "\(Int(seconds / 86_400)) days"
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

/// "Copy card" and "Save card…" for a merged PR, in a menu or a context menu.
struct ShareCardActions: View {
  let store: IslandStore
  let pr: PullRequest

  var body: some View {
    Button("Copy share card") { Task { await store.copyShareCard(for: pr) } }
    Button("Save share card…") { Task { await store.saveShareCard(for: pr) } }
  }
}
