import AppKit
import SwiftUI

// Notch detection and the non-activating panel pattern are adapted from Agents Island (MIT).
// The original license is reproduced in THIRD_PARTY_NOTICES.md.
struct IslandMetrics {
  var notchWidth: CGFloat
  var notchHeight: CGFloat
  var hasNotch: Bool

  static func detect(_ screen: NSScreen) -> IslandMetrics {
    if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea,
      let right = screen.auxiliaryTopRightArea
    {
      return IslandMetrics(
        notchWidth: screen.frame.width - left.width - right.width,
        notchHeight: screen.safeAreaInsets.top, hasNotch: true)
    }
    return IslandMetrics(notchWidth: 0, notchHeight: 0, hasNotch: false)
  }

  var closedWidth: CGFloat { hasNotch ? notchWidth + 196 : 280 }
  var closedHeight: CGFloat { hasNotch ? max(36, notchHeight) : 42 }
  var topGap: CGFloat { hasNotch ? 0 : 8 }

  @MainActor func expandedHeight(for store: IslandStore) -> CGFloat {
    if store.tab == .agents { return 540 }
    let merged = min(5, (store.github?.pullRequests ?? []).filter { $0.state == "MERGED" }.count)
    let eventCount = min(5, store.events.count)
    let progressing = store.openPRs.count - store.attention.count
    let sections = [store.attention.count, progressing, merged, eventCount].filter { $0 > 0 }.count
    let rows = store.openPRs.count + merged
    let desired =
      notchHeight + 135 + CGFloat(rows * 66 + eventCount * 46 + sections * 24)
      + (store.githubError == nil ? 0 : 70)
    return min(540, max(260, desired))
  }
}

final class IslandPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

@MainActor final class IslandPanelController {
  let panel: IslandPanel
  let store: IslandStore
  private var metrics = IslandMetrics(notchWidth: 0, notchHeight: 0, hasNotch: false)
  private var mouseMonitor: Any?
  private var localMouseMonitor: Any?
  private var timer: Timer?
  private var observers: [NSObjectProtocol] = []
  private var mouseWasInside = false

  init(store: IslandStore) {
    self.store = store
    panel = IslandPanel(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isFloatingPanel = true
    panel.becomesKeyOnlyIfNeeded = true
    panel.level = .statusBar
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.isMovable = false
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]
    reposition()
    mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) {
      [weak self] _ in
      Task { @MainActor in self?.trackPointer() }
    }
    localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [
      .mouseMoved, .leftMouseDown, .keyDown,
    ]) { [weak self] event in
      if event.type == .keyDown, event.keyCode == 53, self?.panel.isKeyWindow == true {
        self?.store.dismiss()
        return nil
      }
      self?.trackPointer()
      return event
    }
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification,
        object: nil, queue: .main
      ) { [weak self] _ in Task { @MainActor in self?.reposition() } })
    observers.append(
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.activeSpaceDidChangeNotification,
        object: nil, queue: .main
      ) { [weak self] _ in Task { @MainActor in self?.updateVisibility() } })
    observers.append(
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.sessionDidResignActiveNotification,
        object: nil, queue: .main
      ) { [weak self] _ in Task { @MainActor in self?.panel.orderOut(nil) } })
    observers.append(
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.sessionDidBecomeActiveNotification,
        object: nil, queue: .main
      ) { [weak self] _ in Task { @MainActor in self?.updateVisibility() } })
    // Handles a stationary pointer while the shape grows or shrinks. No accessibility permission is needed.
    timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.trackPointer() }
    }
    updateVisibility()
  }

  private var screen: NSScreen? {
    if let selected = store.settings.displayID,
      let screen = NSScreen.screens.first(where: {
        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
          == selected
      })
    {
      return screen
    }
    return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
      ?? NSScreen.screens.first
  }

  func reposition() {
    guard let screen else { return }
    metrics = IslandMetrics.detect(screen)
    panel.contentView = NSHostingView(rootView: IslandView(store: store, metrics: metrics))
    panel.setFrameOrigin(
      NSPoint(
        x: screen.frame.midX - panel.frame.width / 2, y: screen.frame.maxY - panel.frame.height))
    updateVisibility()
  }

  func updateVisibility() {
    guard let screen else { return }
    // macOS expands visibleFrame to the top edge in full screen. Auto-hide-menu-bar users can override this.
    let fullscreen = screen.visibleFrame.maxY >= screen.frame.maxY - 1
    if !store.settings.showInFullscreen && fullscreen {
      panel.orderOut(nil)
    } else {
      panel.orderFrontRegardless()
    }
  }

  private func trackPointer() {
    guard !CommandLine.arguments.contains("--snapshot") else { return }
    guard panel.isVisible else { return }
    let point = NSEvent.mouseLocation
    let width = store.expanded ? 460.0 : metrics.closedWidth
    let height = store.expanded ? metrics.expandedHeight(for: store) : metrics.closedHeight
    let rect = NSRect(
      x: panel.frame.midX - width / 2, y: panel.frame.maxY - metrics.topGap - height,
      width: width, height: height)
    let inside = NSBezierPath(
      roundedRect: rect, xRadius: store.expanded ? 26 : 20,
      yRadius: store.expanded ? 26 : 20
    ).contains(point)
    panel.ignoresMouseEvents = !inside
    if inside != mouseWasInside {
      mouseWasInside = inside
      store.setHovered(inside)
    }
  }

  func show() {
    store.expanded = true
    panel.orderFrontRegardless()
  }

  func capture(to url: URL) throws {
    guard let view = panel.contentView else { return }
    view.layoutSubtreeIfNeeded()
    let width = store.expanded ? 460.0 : metrics.closedWidth
    let height = store.expanded ? metrics.expandedHeight(for: store) : metrics.closedHeight
    let y = view.isFlipped ? metrics.topGap - 16 : view.bounds.maxY - metrics.topGap - height - 16
    let rect = NSRect(
      x: (view.bounds.width - width) / 2 - 16, y: y,
      width: width + 32, height: height + 32
    ).intersection(view.bounds)
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: rect) else {
      throw CocoaError(.fileWriteUnknown)
    }
    view.cacheDisplay(in: rect, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
      throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url, options: .atomic)
  }
}
