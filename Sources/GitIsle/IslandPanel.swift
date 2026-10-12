import AppKit
import SwiftUI

// Notch detection and the non-activating panel pattern are adapted from Agents Island (MIT).
// The original license is reproduced in THIRD_PARTY_NOTICES.md.
struct IslandMetrics: Equatable {
  var notchWidth: CGFloat
  var notchHeight: CGFloat
  var hasNotch: Bool
  var screenHeight: CGFloat = 900

  static func detect(_ screen: NSScreen) -> IslandMetrics {
    if let width = hardwareNotchWidth(screen) {
      return IslandMetrics(
        notchWidth: width, notchHeight: screen.safeAreaInsets.top, hasNotch: true,
        screenHeight: screen.frame.height)
    }
    // A screen without a notch, such as an external display, gets one drawn: as wide as this
    // Mac's own notch (or a MacBook's, 185 pt) and as tall as the screen's menu bar, so the
    // island looks and behaves the same on every display.
    let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
    return IslandMetrics(
      notchWidth: NSScreen.screens.lazy.compactMap(hardwareNotchWidth).first ?? 185,
      notchHeight: menuBar >= 20 ? menuBar : 32, hasNotch: true,
      screenHeight: screen.frame.height)
  }

  private static func hardwareNotchWidth(_ screen: NSScreen) -> CGFloat? {
    guard screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea,
      let right = screen.auxiliaryTopRightArea
    else { return nil }
    return screen.frame.width - left.width - right.width
  }

  var closedWidth: CGFloat { hasNotch ? notchWidth + 150 : 200 }
  var closedHeight: CGFloat { hasNotch ? max(32, notchHeight) : 38 }
  var topGap: CGFloat { hasNotch ? 0 : 8 }
  /// Concave flare where a notch-attached island meets the top of the screen.
  var ear: CGFloat { hasNotch ? 10 : 0 }

  /// At rest the island is exactly the notch: invisible on a MacBook, a drawn notch elsewhere.
  var idleSize: CGSize {
    hasNotch ? CGSize(width: notchWidth, height: notchHeight) : CGSize(width: 130, height: 8)
  }

  func ear(for presentation: IslandStore.Presentation) -> CGFloat {
    presentation == .idle ? 0 : ear
  }

  /// Padding at each end of the live pill.
  var livePadding: CGFloat { hasNotch ? 12 : 16 }
  /// The middle of the live pill, where content never goes: the camera housing plus a margin
  /// either side, or a small gap without a notch.
  var liveGap: CGFloat { hasNotch ? notchWidth + 12 : 10 }
  /// The live pill fits its widest side. Both sides grow together so the pill stays centred on
  /// the notch, and it is never narrower than `closedWidth`.
  func liveWidth(side: CGFloat) -> CGFloat {
    max(closedWidth, 2 * (livePadding + side.rounded(.up)) + liveGap)
  }

  /// Banners grow downward only: as wide as the live pill under a notch. Without a notch the
  /// pill is too narrow for a title, so the banner keeps a readable minimum.
  func bannerSize(liveWidth: CGFloat) -> CGSize {
    CGSize(width: hasNotch ? liveWidth : max(liveWidth, 340), height: closedHeight + 50)
  }
  var expandedWidth: CGFloat { 640 }
  /// The board grows with its columns and never gets narrower than the list.
  func boardWidth(columns: Int) -> CGFloat {
    let column: CGFloat = 230
    let spacing: CGFloat = 10
    let content = CGFloat(columns) * column + CGFloat(max(0, columns - 1)) * spacing + 32
    return max(expandedWidth, content)
  }
  /// The usual limit before expanded content scrolls.
  var maxExpandedHeight: CGFloat { 560 }
  /// Stats may grow with the screen so its cards fit before it needs to scroll.
  var maxStatsHeight: CGFloat { min(860, max(maxExpandedHeight, screenHeight - 140)) }

  /// The transparent window holds the widest board and the tallest island, plus shadow.
  var panelSize: CGSize {
    CGSize(width: boardWidth(columns: 4) + 2 * ear + 80, height: maxStatsHeight + topGap + 60)
  }

  func cornerRadius(for presentation: IslandStore.Presentation) -> CGFloat {
    switch presentation {
    case .idle: hasNotch ? 8 : 4
    case .live: hasNotch ? 12 : closedHeight / 2
    case .banner: hasNotch ? 24 : 26
    case .expanded: 32
    }
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
  private var lastPointer: NSPoint?

  init(store: IslandStore) {
    self.store = store
    panel = IslandPanel(
      contentRect: NSRect(x: 0, y: 0, width: 1040, height: 660),
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
    // Menus (repository filter, chart style, display picker) open outside the island.
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
      ) { [weak self] _ in Task { @MainActor in self?.store.menuOpen = true } })
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main
      ) { [weak self] _ in Task { @MainActor in self?.menuClosed() } })
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
    let detected = IslandMetrics.detect(screen)
    // Rebuilding the view resets its state, so keep it unless the geometry changed.
    if detected == metrics, panel.contentView is NSHostingView<IslandView> {
      placePanel(on: screen)
      return
    }
    metrics = detected
    let host = NSHostingView(rootView: IslandView(store: store, metrics: metrics))
    // The window keeps a fixed size; the island animates inside it without window resizes.
    host.sizingOptions = []
    panel.contentView = host
    placePanel(on: screen)
  }

  private func placePanel(on screen: NSScreen) {
    let size = metrics.panelSize
    panel.setFrame(
      NSRect(
        x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
        width: size.width, height: size.height),
      display: false)
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

  /// Once a menu closes, collapse only if the pointer really is outside the island.
  private func menuClosed() {
    store.menuOpen = false
    trackPointer()
    if !mouseWasInside { store.setHovered(false) }
  }

  private func trackPointer() {
    guard !CommandLine.arguments.contains("--snapshot") else { return }
    guard panel.isVisible else { return }
    let point = NSEvent.mouseLocation
    let size = islandSize
    let rect = NSRect(
      x: panel.frame.midX - size.width / 2, y: panel.frame.maxY - metrics.topGap - size.height,
      width: size.width, height: size.height)
    let radius = metrics.cornerRadius(for: store.presentation)
    let inside = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).contains(point)
    let moved = point != lastPointer
    lastPointer = point
    panel.ignoresMouseEvents = !inside
    guard inside != mouseWasInside else { return }
    // When the island narrows under a still pointer (for example switching from the board
    // to the list), the island left the pointer, not the other way round. Stay open until
    // the pointer itself moves outside.
    if !inside && !moved && store.expanded { return }
    mouseWasInside = inside
    store.setHovered(inside)
  }

  private var islandSize: CGSize {
    let measured = store.islandSize
    if measured.width > 0, measured.height > 0 { return measured }
    return metrics.idleSize
  }

  func show() {
    store.expanded = true
    panel.orderFrontRegardless()
  }

  func capture(to url: URL) throws {
    guard let view = panel.contentView else { return }
    view.layoutSubtreeIfNeeded()
    let width = islandSize.width
    let height = islandSize.height
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
