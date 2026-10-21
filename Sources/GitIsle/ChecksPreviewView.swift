import AppKit
import IslandCore
import SwiftUI

extension View {
  /// Previews `pr`'s checks, or its merge queue run's, while the pointer rests here in the open
  /// island.
  /// `liveBar` marks the live bar's rings, which a tour previews.
  func checksHover(_ pr: PullRequest, queue: Bool, liveBar: Bool = false) -> some View {
    modifier(ChecksHover(pr: pr, queue: queue, liveBar: liveBar))
  }
}

private struct ChecksHover: ViewModifier {
  let pr: PullRequest
  let queue: Bool
  let liveBar: Bool
  @Environment(IslandStore.self) private var store
  @State private var frame: CGRect = .zero

  func body(content: Content) -> some View {
    content
      .onGeometryChange(for: CGRect.self) {
        $0.frame(in: .named(ChecksPreview.space))
      } action: {
        frame = $0
        openPending()
      }
      .onHover { inside in
        // The closed island opens on hover; the preview belongs to the open one.
        guard store.expanded else { return }
        store.hoverChecks(pr, queue: queue, anchor: frame, inside: inside)
      }
      .onChange(of: store.pendingChecks) { openPending() }
  }

  /// Opens the preview a tour asked for, once this ring is laid out.
  private func openPending() {
    guard liveBar, frame != .zero,
      store.pendingChecks == ChecksPreview.key(pr.id, queue: queue)
    else { return }
    store.pendingChecks = nil
    store.hoverChecks(pr, queue: queue, anchor: frame, inside: true)
  }
}

/// The checks behind a ring: failures first, then what's running, then the rest, each with
/// how long it has taken. A click opens a check's log.
struct ChecksPopover: View {
  let store: IslandStore
  let preview: ChecksPreview

  static let width: CGFloat = 300
  /// More scroll, so the preview never covers too much of the island.
  static let rows = 10

  var body: some View {
    let checks = store.checkLists[preview.key]
    VStack(alignment: .leading, spacing: 0) {
      header(checks)
      if let checks, !checks.isEmpty {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
              CheckLine(check: check)
            }
          }
        }
        .scrollIndicators(.automatic)
        .frame(height: CGFloat(min(checks.count, Self.rows)) * CheckLine.height)
      } else {
        HStack(spacing: 8) {
          if checks == nil && !store.checkListErrors.contains(preview.key) {
            RunningRing(size: 11)
          }
          Text(
            store.checkListErrors.contains(preview.key)
              ? "Couldn't read the checks" : checks == nil ? "Reading the checks…" : "No checks"
          )
          .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
      }
    }
    .padding(Dropdown.padding)
    .frame(width: Self.width, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.popover))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline)
    )
    .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    .onHover { store.hoverChecksPreview($0) }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(preview.queue ? "Merge queue checks" : "Checks")
  }

  private func header(_ checks: [Check]?) -> some View {
    HStack(spacing: 6) {
      Text(preview.queue ? "Merge queue" : "Checks")
        .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
      Spacer(minLength: 8)
      if let checks, !checks.isEmpty {
        let done = checks.count { $0.outcome != .running }
        Text("\(done) of \(checks.count) done")
          .font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.white.opacity(0.35))
          .contentTransition(.numericText(value: Double(done)))
      }
    }
    .padding(.horizontal, 8)
    .frame(height: 22)
  }
}

/// One check: its state, its job's name, and how long it ran or has been running.
private struct CheckLine: View {
  let check: Check
  @State private var hovered = false

  static let height: CGFloat = 26

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
          .foregroundStyle(.white.opacity(check.outcome == .skipped ? 0.45 : 0.9))
          .lineLimit(1).truncationMode(.middle)
        Spacer(minLength: 8)
        if check.outcome == .running, let started = check.startedAt {
          // Counts up on its own while it runs.
          Text(started, style: .timer).font(.system(size: 11)).monospacedDigit()
            .foregroundStyle(Palette.merging.opacity(0.8)).fixedSize()
        } else if let seconds = check.duration {
          Text(Format.duration(seconds)).font(.system(size: 11)).monospacedDigit()
            .foregroundStyle(.white.opacity(0.4))
        }
      }
      .padding(.horizontal, 8)
      .frame(height: Self.height)
      .background(
        RoundedRectangle(cornerRadius: 7).fill(
          .white.opacity(hovered && check.url != nil ? 0.07 : 0))
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(check.url == nil)
    .onHover { hovered = $0 }
    .help(check.url == nil ? check.title : "\(check.title) · open the log")
  }
}
