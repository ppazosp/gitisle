import AppKit
import Darwin
import IslandCore
import SwiftUI
import UserNotifications

@main struct GitIsleApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @State private var store: IslandStore

  init() {
    let demo =
      CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--snapshot")
      || CommandLine.arguments.contains("--banner")
    let model = IslandStore(demo: demo)
    _store = State(initialValue: model)
    delegate.store = model
  }

  var body: some Scene {
    MenuBarExtra {
      Button("Show GitIsle") { delegate.island?.show() }
      Button("Refresh GitHub") { Task { await store.refreshGitHub() } }.disabled(
        store.githubRefreshing || store.isDemo)
      Button("Settings…") {
        NotificationCenter.default.post(name: .islandOpenSettings, object: nil)
      }
      .keyboardShortcut(",")
      Divider()
      Text("\(store.openPRs.count) open PRs · \(store.attention.count) need you")
      Divider()
      Button("Quit GitIsle") { NSApp.terminate(nil) }.keyboardShortcut("q")
    } label: {
      Image(nsImage: Glyph.pullRequest.image(size: 16)).accessibilityLabel("GitIsle")
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  var store: IslandStore?
  var island: IslandPanelController?
  private var settingsObserver: NSObjectProtocol?
  private var openSettingsObserver: NSObjectProtocol?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    guard let store else { return }
    if CommandLine.arguments.contains("--diagnose") {
      Task { await diagnose(store: store) }
      return
    }
    UNUserNotificationCenter.current().delegate = self
    let arguments = CommandLine.arguments
    if (arguments.contains("--expanded") || arguments.contains("--snapshot"))
      && !arguments.contains("--collapsed") && !arguments.contains("--banner")
    {
      store.expanded = true
    }
    // `--agents` is the earlier name for the statistics preview.
    if arguments.contains("--stats") || arguments.contains("--agents") { store.tab = .stats }
    if arguments.contains("--banner"),
      let pr = store.github?.pullRequests.first(where: {
        $0.state == "MERGED"
      })
    {
      store.showEvent(
        IslandEvent(
          id: "demo-banner", title: "\(pr.repository) #\(pr.number) · Merged", detail: pr.title,
          url: pr.url, occurredAt: Date(), kind: .merged), extra: 1)
    }
    island = IslandPanelController(store: store)
    settingsObserver = NotificationCenter.default.addObserver(
      forName: .islandSettingsChanged, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.island?.reposition() }
    }
    openSettingsObserver = NotificationCenter.default.addObserver(
      forName: .islandOpenSettings, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.store?.openSettings() }
    }
    if arguments.contains("--settings") { store.openSettings() }
    store.start()
    if let position = CommandLine.arguments.firstIndex(of: "--snapshot"),
      CommandLine.arguments.count > position + 1
    {
      let url = URL(fileURLWithPath: CommandLine.arguments[position + 1])
      Task {
        try? await Task.sleep(for: .seconds(1))
        do {
          try island?.capture(to: url)
          print("Snapshot: \(url.path)")
          exit(0)
        } catch {
          print(error.localizedDescription)
          exit(1)
        }
      }
    }
  }

  func applicationWillTerminate(_ notification: Notification) { store?.stop() }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if let link = response.notification.request.content.userInfo["url"] as? String,
      let url = URL(string: link), url.scheme == "https", url.host == "github.com"
    {
      Task { @MainActor in NSWorkspace.shared.open(url) }
    }
    completionHandler()
  }

  private func diagnose(store: IslandStore) async {
    await store.refreshGitHub()
    await store.refreshUsage()
    await store.refreshStats()
    let report: [String: Any] = [
      "githubConnected": store.githubError == nil && store.github != nil,
      "pullRequests": store.openPRs.count,
      "githubStatsDays": store.githubStats?.windows.map(\.days) ?? [],
      "pullRequestsWithCheckCounts": store.openPRs.count { $0.checkSummary != nil },
      "usageProviders": store.usage.keys.map(\.rawValue).sorted(),
      "usageMetrics": store.usage.map { provider, summaries -> [String: Any] in
        let today = summaries.first { $0.days == 1 }
        return [
          "provider": provider.rawValue, "todayTokens": today?.tokens as Any? ?? NSNull(),
          "modelCount": today?.models.count ?? 0, "partialHistory": today?.partial ?? true,
        ]
      },
      "errors": [store.githubError, store.githubStatsError].compactMap { $0 }
        + Array(store.usageErrors.values),
    ]
    if let data = try? JSONSerialization.data(
      withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    {
      print(String(decoding: data, as: UTF8.self))
    }
    exit(
      store.githubError == nil && store.githubStatsError == nil && store.usageErrors.isEmpty
        ? 0 : 1)
  }
}
