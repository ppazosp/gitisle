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
      || CommandLine.arguments.contains("--banner") || CommandLine.arguments.contains("--event")
      || CommandLine.arguments.contains("--story") || CommandLine.arguments.contains("--share-card")
      || CommandLine.arguments.contains("--showcase") || CommandLine.arguments.contains("--tour")
    let model = IslandStore(demo: demo)
    _store = State(initialValue: model)
    delegate.store = model
  }

  var body: some Scene {
    // GitIsle lives in the notch only; its menu is a right-click on the island.
    // SwiftUI needs a scene, and an empty settings scene shows nothing.
    Settings { EmptyView() }
  }

}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  var store: IslandStore?
  var island: IslandPanelController?
  private var settingsObserver: NSObjectProtocol?
  private var openSettingsObserver: NSObjectProtocol?

  /// The notification delegate must exist before launch finishes, so a click that launches
  /// GitIsle still reaches it and opens the PR.
  func applicationWillFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self
  }

  /// Clicking a notification brings GitIsle forward; it has no window to show.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    false
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    guard let store else { return }
    if CommandLine.arguments.contains("--diagnose") {
      Task { await diagnose(store: store) }
      return
    }
    let arguments = CommandLine.arguments
    // Snapshots open the island unless they show it closed; `--expanded` opens it over a banner.
    if arguments.contains("--expanded")
      || (arguments.contains("--snapshot") && !arguments.contains("--collapsed")
        && !arguments.contains("--banner") && !arguments.contains("--event")
        && !arguments.contains("--story"))
    {
      store.expanded = true
    }
    // `--agents` is the earlier name for the statistics preview.
    if arguments.contains("--stats") || arguments.contains("--agents") { store.tab = .stats }
    if arguments.contains("--board") { store.activityLayout = .board }
    if let index = arguments.firstIndex(of: "--chart"), arguments.count > index + 1,
      let style = ChartStyle(rawValue: arguments[index + 1])
    {
      store.update {
        $0.githubChart = style
        $0.usageChart = style
        $0.usageMetric = style == .cumulative ? .cost : .tokens
      }
    }
    // `--display <id>` previews the island on another screen.
    if let index = arguments.firstIndex(of: "--display"), arguments.count > index + 1,
      let display = UInt32(arguments[index + 1])
    {
      store.update { $0.displayID = display }
    }
    if let index = arguments.firstIndex(of: "--states"), arguments.count > index + 1 {
      store.stateFilter = Set(
        arguments[index + 1].split(separator: ",").compactMap { PRGroup(rawValue: String($0)) })
    }
    if let index = arguments.firstIndex(of: "--repos"), arguments.count > index + 1, store.isDemo {
      store.repositoryFilter = Set(arguments[index + 1].split(separator: ",").map(String.init))
    }
    if arguments.contains("--repo-picker"), store.isDemo { store.repositoryPickerOpen = true }
    // `--dropdown <id>` opens a dropdown, such as `chart-github`, once its control is laid out.
    if let index = arguments.firstIndex(of: "--dropdown"), arguments.count > index + 1,
      store.isDemo
    {
      store.pendingDropdown = arguments[index + 1]
    }
    // `--hover <id>` shows an example PR's row and card as hovered.
    if let index = arguments.firstIndex(of: "--hover"), arguments.count > index + 1, store.isDemo {
      store.previewHover = arguments[index + 1]
    }
    // `--share-card <id> <file>` writes an example PR's share card and quits.
    if let index = arguments.firstIndex(of: "--share-card"), arguments.count > index + 2,
      store.isDemo,
      let pr = store.github?.pullRequests.first(where: { $0.id == arguments[index + 1] })
    {
      let url = URL(fileURLWithPath: arguments[index + 2])
      Task {
        guard let png = await store.shareCard(for: pr) else { exit(1) }
        do {
          try png.write(to: url)
          print("Share card: \(url.path)")
          exit(0)
        } catch { exit(1) }
      }
      return
    }
    // `--details <id>` opens an example PR's page, for example `--details demo2`.
    if let index = arguments.firstIndex(of: "--details"), arguments.count > index + 1, store.isDemo,
      let pr = store.github?.pullRequests.first(where: { $0.id == arguments[index + 1] })
    {
      store.openDetails(pr)
      // `--file <path>` opens one of its files to the diff.
      if let file = arguments.firstIndex(of: "--file"), arguments.count > file + 1 {
        store.openFile(arguments[file + 1])
      }
    }
    if arguments.contains("--banner"),
      let pr = store.github?.pullRequests.first(where: {
        $0.state == "MERGED"
      })
    {
      store.showEvent(
        IslandEvent(
          id: "demo-banner", title: "\(pr.repository) #\(pr.number) · Merged", detail: pr.title,
          url: pr.url, occurredAt: Date(), kind: .merged, repository: pr.repository), extra: 1)
    }
    if arguments.contains("--update"), store.isDemo { store.updater.preview() }
    // `--story <kind>` is one PR's life for the website: the banner, with the live bar only
    // while that PR merges.
    if let index = arguments.firstIndex(of: "--story"), arguments.count > index + 1,
      let kind = PRStatus(rawValue: arguments[index + 1])
    {
      store.previewStory(kind)
    }
    // `--event <kind>` previews one announcement's banner, for example `--event draft`.
    if let index = arguments.firstIndex(of: "--event"), arguments.count > index + 1,
      let kind = PRStatus(rawValue: arguments[index + 1])
    {
      store.previewEvent(kind)
    }
    if arguments.contains("--showcase") { store.runShowcase() }
    // `--tour` plays every state of the island; `--tour pages` plays a PR's page.
    if let index = arguments.firstIndex(of: "--tour") {
      if arguments.count > index + 1, arguments[index + 1] == "pages" {
        store.runPagesTour()
      } else {
        store.runTour()
      }
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
    // New installs start with setup; `--onboarding [step]` previews it.
    if !store.isDemo && !store.settings.onboardingCompleted {
      store.startOnboarding()
    } else if let index = arguments.firstIndex(of: "--onboarding") {
      store.startOnboarding()
      if arguments.count > index + 1, let step = OnboardingStep(name: arguments[index + 1]) {
        store.onboardingStep = step
      }
    }
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
