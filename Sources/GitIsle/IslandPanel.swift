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

  var closedWidth: CGFloat { hasNotch ? notchWidth + 224 : 300 }
  var closedHeight: CGFloat { hasNotch ? max(32, notchHeight) : 38 }
  var topGap: CGFloat { hasNotch ? 0 : 8 }
  /// Concave flare where a notch-attached island meets the top of the screen.
  var ear: CGFloat { hasNotch ? 10 : 0 }

  var bannerSize: CGSize { CGSize(width: max(closedWidth + 72, 400), height: closedHeight + 60) }
  // Wide and short: pull requests and sessions sit side by side.
  var expandedWidth: CGFloat { 860 }
  var maxExpandedHeight: CGFloat { 500 }

  func cornerRadius(for presentation: IslandStore.Presentation) -> CGFloat {
    switch presentation {
    case .compact: hasNotch ? 12 : closedHeight / 2
    case .banner: hasNotch ? 22 : 24
    case .expanded: 28
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

  init(store: IslandStore) {
    self.store = store
    panel = IslandPanel(
      contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
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
    let host = NSHostingView(rootView: IslandView(store: store, metrics: metrics))
    // The window keeps a fixed size; the island animates inside it without window resizes.
    host.sizingOptions = []
    panel.contentView = host
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
    let size = islandSize
    let rect = NSRect(
      x: panel.frame.midX - size.width / 2, y: panel.frame.maxY - metrics.topGap - size.height,
      width: size.width, height: size.height)
    let radius = metrics.cornerRadius(for: store.presentation)
    let inside = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).contains(point)
    panel.ignoresMouseEvents = !inside
    if inside != mouseWasInside {
      mouseWasInside = inside
      store.setHovered(inside)
    }
  }

  private var islandSize: CGSize {
    let measured = store.islandSize
    if measured.width > 0, measured.height > 0 { return measured }
    return CGSize(width: metrics.closedWidth, height: metrics.closedHeight)
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
