import AppKit
import IslandCore
import SwiftUI

/// An image of a merged PR to post: what it changed, how long it took, and what it passed.
/// Rendered from SwiftUI at twice its 1200 × 630 size, the shape link previews use.
struct ShareCard: View {
  let pr: PullRequest
  let details: PullRequestDetails

  static let size = CGSize(width: 1200, height: 630)

  var body: some View {
    ZStack {
      Color.black
      RadialGradient(
        colors: [Palette.open.opacity(0.22), .clear], center: .bottomLeading, startRadius: 0,
        endRadius: 620)
      RadialGradient(
        colors: [Palette.merged.opacity(0.3), .clear], center: .bottomTrailing, startRadius: 0,
        endRadius: 660)
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 14) {
          Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 46, height: 46)
          Text("GitIsle").font(.system(size: 26, weight: .semibold))
          Spacer()
          Text(verbatim: "\(pr.repository) #\(pr.number)").font(.system(size: 22, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
        }
        Spacer(minLength: 24)
        HStack(spacing: 12) {
          HStack(spacing: 8) {
            GlyphView(glyph: .merge, size: 20)
            Text("Merged")
          }
          .font(.system(size: 22, weight: .semibold)).foregroundStyle(Palette.merged)
          .padding(.horizontal, 16).padding(.vertical, 8)
          .background(Capsule().fill(Palette.merged.opacity(0.18)))
          if let open = openFor {
            Text("after \(open)").font(.system(size: 22)).foregroundStyle(.white.opacity(0.55))
          }
        }
        Text(pr.title).font(.system(size: 54, weight: .semibold)).tracking(-1.2)
          .lineLimit(2).minimumScaleFactor(0.7).padding(.top, 22)
        if let author = details.author ?? pr.author {
          Text("by \(author)").font(.system(size: 24)).foregroundStyle(.white.opacity(0.5))
            .padding(.top, 10)
        }
        Spacer(minLength: 24)
        HStack(alignment: .bottom, spacing: 44) {
          Stat(value: "+\(details.additions.formatted())", label: "added", color: Palette.open)
          Stat(value: "−\(details.deletions.formatted())", label: "removed", color: Palette.failed)
          Stat(
            value: details.changedFiles.formatted(),
            label: details.changedFiles == 1 ? "file" : "files")
          Stat(
            value: details.commitCount.formatted(),
            label: details.commitCount == 1 ? "commit" : "commits")
          if passed > 0 { Stat(value: passed.formatted(), label: "checks passed") }
          if approvals > 0 {
            Stat(value: approvals.formatted(), label: approvals == 1 ? "approval" : "approvals")
          }
          Spacer(minLength: 0)
          Text("gitisle.ppazosp.dev").font(.system(size: 18)).foregroundStyle(.white.opacity(0.35))
        }
      }
      .padding(64)
    }
    .foregroundStyle(.white)
    .frame(width: Self.size.width, height: Self.size.height)
    .environment(\.colorScheme, .dark)
  }

  private var passed: Int { details.checks.count { $0.outcome == .passed } }
  private var approvals: Int { details.reviews.count { $0.state == "APPROVED" } }

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
