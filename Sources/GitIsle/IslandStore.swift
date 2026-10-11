import AppKit
import Foundation
import IslandCore
import Observation
import UserNotifications

@MainActor @Observable
final class IslandStore {
  var settings: AppSettings
  private(set) var github: GitHubSnapshot?
  var githubError: String?
  var githubRefreshing = false
  var githubStats: GitHubStats?
  var githubStatsError: String?
  var usage: [AgentProvider: [UsageSummary]] = [:]
  var usageErrors: [AgentProvider: String] = [:]
  var usageRefreshing = false
  var events: [IslandEvent] = []
  var recentEvent: IslandEvent?
  /// Other changes that arrived with `recentEvent`.
  var recentEventExtra = 0
  var expanded = false {
    didSet {
      // Expanding shows the full context, so a pending banner has done its job.
      if expanded, recentEvent != nil {
        notificationTask?.cancel()
        recentEvent = nil
      }
    }
  }
  var tab: IslandTab = .activity
  var activityWindow: ActivityWindow = .all {
    didSet { if activityWindow != oldValue { regroup() } }
  }
  var usageDays = 1
  var hovered = false
  var persistenceError: String?
  var isDemo: Bool

  // Derived once per GitHub snapshot so rendering never re-filters the PR list.
  private(set) var openPRs: [PullRequest] = []
  private(set) var attention: [PullRequest] = []
  private(set) var merging: [PullRequest] = []
  private(set) var repositories: [RepoSection] = []
  /// Repositories collapsed in the activity list, remembered across launches.
  private(set) var collapsedRepositories: Set<String> =
    Set(UserDefaults.standard.stringArray(forKey: "collapsedRepositories") ?? [])

  /// The island's laid-out size, reported by the view and used for pointer hit-testing.
  @ObservationIgnored var islandSize: CGSize = .zero

  @ObservationIgnored private let githubService = GitHubService()
  @ObservationIgnored private let usageService: UsageService
  @ObservationIgnored private var loops: [Task<Void, Never>] = []
  @ObservationIgnored private var hoverTask: Task<Void, Never>?
  @ObservationIgnored private var notificationTask: Task<Void, Never>?
  @ObservationIgnored private var lastGitHubRefresh = Date.distantPast
  @ObservationIgnored private var lastUsageRefresh = Date.distantPast
  @ObservationIgnored private var lastStatsRefresh = Date.distantPast
  @ObservationIgnored private var statsRefreshing = false

  enum IslandTab: String, CaseIterable {
    case activity = "Activity"
    case stats = "Stats"
  }

  enum Presentation: Equatable {
    case compact, banner, expanded
  }

  var presentation: Presentation {
    if expanded { return .expanded }
    return recentEvent == nil ? .compact : .banner
  }

  init(demo: Bool = false) {
    isDemo = demo
    settings = demo ? AppSettings() : AppSettings.load(from: AppFiles.settings)
    usageService = UsageService(cacheRoot: AppFiles.directory.appendingPathComponent("usage-cache"))
    if demo {
      loadDemo()
      return
    }
    do {
      try AppFiles.prepare()
      if let data = try? Data(contentsOf: AppFiles.snapshot) {
        github = try? JSONDecoder().decode(GitHubSnapshot.self, from: data)
      }
      if let data = try? Data(contentsOf: AppFiles.events) {
        events = (try? JSONDecoder().decode([IslandEvent].self, from: data)) ?? []
      }
    } catch { persistenceError = error.localizedDescription }
    regroup()
  }

  private func setGitHub(_ snapshot: GitHubSnapshot?) {
    github = snapshot
    regroup()
  }

  private func regroup() {
    let all = github?.pullRequests ?? []
    let open = all.filter { $0.state == "OPEN" }
    openPRs = open
    attention = open.filter { $0.group == .needsYou }
    merging = open.filter(\.isMerging).sorted {
      ($0.queuePosition ?? .max, $1.updatedAt) < ($1.queuePosition ?? .max, $0.updatedAt)
    }
    let fresh = PRGrouping.repositories(all, window: activityWindow)
    if fresh != repositories { repositories = fresh }
  }

  func toggleCollapsed(_ repository: String) {
    if collapsedRepositories.remove(repository) == nil { collapsedRepositories.insert(repository) }
    guard !isDemo else { return }
    UserDefaults.standard.set(collapsedRepositories.sorted(), forKey: "collapsedRepositories")
  }

  var cached: Bool {
    githubError != nil
      || (github.map { Date().timeIntervalSince($0.fetchedAt) > settings.githubRefreshSeconds * 2 }
        ?? false)
  }

  func start() {
    guard !isDemo, loops.isEmpty else { return }
    loops.append(
      Task { [weak self] in
        while !Task.isCancelled {
          guard let self else { return }
          if Date().timeIntervalSince(lastGitHubRefresh) >= settings.githubRefreshSeconds {
            await refreshGitHub()
          }
          do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
      })
    loops.append(
      Task { [weak self] in
        while !Task.isCancelled {
          guard let self else { return }
          if Date().timeIntervalSince(lastUsageRefresh) > 120 { await refreshUsage() }
          do { try await Task.sleep(for: .seconds(10)) } catch { return }
        }
      })
    loops.append(
      Task { [weak self] in
        while !Task.isCancelled {
          guard let self else { return }
          if Date().timeIntervalSince(lastStatsRefresh) > 600 { await refreshStats() }
          do { try await Task.sleep(for: .seconds(30)) } catch { return }
        }
      })
  }

  func stop() {
    for loop in loops { loop.cancel() }
    loops = []
    hoverTask?.cancel()
    notificationTask?.cancel()
  }

  func refreshStats() async {
    guard !isDemo, !statsRefreshing else { return }
    statsRefreshing = true
    defer {
      statsRefreshing = false
      lastStatsRefresh = Date()
    }
    do {
      githubStats = try await githubService.stats()
      githubStatsError = nil
    } catch { githubStatsError = error.localizedDescription }
  }

  func refreshGitHub() async {
    guard !githubRefreshing, !isDemo else { return }
    githubRefreshing = true
    defer {
      githubRefreshing = false
      lastGitHubRefresh = Date()
    }
    do {
      let selection = try RepositorySelection(text: settings.repositories)
      let fresh = try await githubService.fetch(selection: selection, previous: github)
      guard
        (try? RepositorySelection(text: settings.repositories).fingerprint) == selection.fingerprint
      else { return }
      let known = Set(events.map(\.id))
      let changes = GitHubChanges.events(previous: github, current: fresh).filter {
        !known.contains($0.id)
      }
      let newEvents = Array((changes + events).prefix(200))
      // Persist the notification ledger before emitting side effects; a restart never replays it.
      try JSONEncoder().encode(newEvents).write(to: AppFiles.events, options: .atomic)
      try JSONEncoder().encode(fresh).write(to: AppFiles.snapshot, options: .atomic)
      events = newEvents
      setGitHub(fresh)
      githubError = nil
      if let latest = changes.min(by: { $0.kind.bannerPriority < $1.kind.bannerPriority }) {
        showEvent(latest, extra: changes.count - 1)
      }
      for event in changes where event.notifiesSystem { notify(event) }
    } catch { githubError = error.localizedDescription }
  }

  func refreshUsage() async {
    guard !usageRefreshing, !isDemo else { return }
    usageRefreshing = true
    defer {
      usageRefreshing = false
      lastUsageRefresh = Date()
    }
    let paths = (settings.codexHome, settings.claudeHome)
    for provider in AgentProvider.allCases {
      do {
        let fresh = try await usageService.summaries(
          provider: provider,
          codexHome: NSString(string: paths.0).expandingTildeInPath,
          claudeHome: NSString(string: paths.1).expandingTildeInPath)
        guard settings.codexHome == paths.0, settings.claudeHome == paths.1 else { return }
        usage[provider] = fresh
        usageErrors[provider] = nil
      } catch { usageErrors[provider] = error.localizedDescription }
    }
  }

  func applySettings(_ proposed: AppSettings) {
    do {
      _ = try RepositorySelection(text: proposed.repositories)
      guard !proposed.codexHome.isEmpty, !proposed.claudeHome.isEmpty else {
        throw ProcessFailure.failed("Choose a home directory for each agent.")
      }
      settings = proposed
      saveSettings()
      NotificationCenter.default.post(name: .islandSettingsChanged, object: nil)
    } catch { persistenceError = error.localizedDescription }
  }

  func saveSettings() {
    guard !isDemo else { return }
    do {
      _ = try RepositorySelection(text: settings.repositories)
      try settings.save(to: AppFiles.settings)
      persistenceError = nil
      lastGitHubRefresh = .distantPast
      lastUsageRefresh = .distantPast
      lastStatsRefresh = .distantPast
    } catch { persistenceError = error.localizedDescription }
  }

  func setHovered(_ inside: Bool) {
    hovered = inside
    hoverTask?.cancel()
    hoverTask = Task { [weak self] in
      guard let self else { return }
      do { try await Task.sleep(for: .seconds(inside ? settings.hoverDelay : 0.25)) } catch {
        return
      }
      if !Task.isCancelled { expanded = inside }
    }
  }

  func dismiss() {
    hoverTask?.cancel()
    expanded = false
  }

  func showEvent(_ event: IslandEvent, extra: Int = 0) {
    recentEvent = event
    recentEventExtra = extra
    notificationTask?.cancel()
    notificationTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .seconds(5))
        // Keep the banner while the pointer rests on it.
        while self?.hovered == true { try await Task.sleep(for: .seconds(0.5)) }
      } catch { return }
      self?.recentEvent = nil
    }
  }

  func requestNotifications() async {
    do {
      settings.notificationsEnabled = try await UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .sound])
      saveSettings()
    } catch {
      persistenceError = error.localizedDescription
      settings.notificationsEnabled = false
    }
  }

  private func notify(_ event: IslandEvent) {
    guard settings.notificationsEnabled else { return }
    let content = UNMutableNotificationContent()
    content.title = event.title
    content.body = event.detail
    content.userInfo = ["url": event.url.absoluteString]
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: event.id, content: content, trigger: nil))
  }

  private func loadDemo() {
    let now = Date()
    let link = URL(string: "https://github.com/ppazosp/gitisle")!
    let hour = 3600.0
    let prs = [
      PullRequest(
        id: "demo1", number: 428, repository: "example/app", title: "Improve sandbox startup",
        url: link, reviewRequested: true, checks: "SUCCESS",
        checkSummary: CheckSummary(passed: 6, failed: 0, pending: 0),
        updatedAt: now.addingTimeInterval(-0.4 * hour), author: "teammate"),
      PullRequest(
        id: "demo2", number: 431, repository: "example/app", title: "Add project shortcuts",
        url: link, checks: "FAILURE", checkSummary: CheckSummary(passed: 4, failed: 1, pending: 0),
        updatedAt: now.addingTimeInterval(-1.2 * hour), author: "example"),
      PullRequest(
        id: "demo3", number: 433, repository: "example/tools", title: "Cache workspace metadata",
        url: link, checks: "PENDING", checkSummary: CheckSummary(passed: 3, failed: 0, pending: 2),
        autoMerge: true, queuePosition: 2, updatedAt: now.addingTimeInterval(-0.1 * hour),
        author: "example"),
      PullRequest(
        id: "demo4", number: 436, repository: "example/app", title: "Polish the island animations",
        url: link, reviewDecision: "REVIEW_REQUIRED", mergeStateStatus: "BLOCKED",
        checks: "PENDING", checkSummary: CheckSummary(passed: 2, failed: 0, pending: 3),
        updatedAt: now.addingTimeInterval(-2 * hour), author: "example"),
      PullRequest(
        id: "demo5", number: 437, repository: "example/tools", title: "Sketch the stats view",
        url: link, isDraft: true, checks: "SUCCESS",
        checkSummary: CheckSummary(passed: 5, failed: 0, pending: 0),
        updatedAt: now.addingTimeInterval(-26 * hour), author: "example"),
      PullRequest(
        id: "demo6", number: 425, repository: "example/app", title: "Native GitHub island",
        url: link, state: "MERGED", checks: "SUCCESS",
        checkSummary: CheckSummary(passed: 6, failed: 0, pending: 0),
        updatedAt: now.addingTimeInterval(-3 * hour), mergedAt: now.addingTimeInterval(-3 * hour),
        author: "example"),
    ]
    setGitHub(GitHubSnapshot(login: "example", pullRequests: prs))
    let calendar = Calendar.current
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    func series(_ seed: Double) -> [DailyValue] {
      (0..<30).reversed().map { offset in
        let day = calendar.date(byAdding: .day, value: -offset, to: now)!
        let wave = (sin(Double(offset) * 0.9 + seed) + 1.2) * (offset % 7 > 4 ? 0.3 : 1)
        return DailyValue(day: formatter.string(from: day), value: (wave * 900_000).rounded())
      }
    }
    for provider in AgentProvider.allCases {
      let daily = series(provider == .codex ? 0.4 : 2.1)
      usage[provider] = [1, 7, 30].map { days in
        let window = Array(daily.suffix(days))
        let tokens = Int(window.reduce(0) { $0 + $1.value })
        let cost = Double(tokens) / 1_000_000 * (provider == .codex ? 4.1 : 6.3)
        let models =
          provider == .codex
          ? [
            UsageModel(name: "gpt-6", tokens: tokens * 7 / 10, estimatedCost: cost * 0.8),
            UsageModel(name: "gpt-6-mini", tokens: tokens * 3 / 10, estimatedCost: cost * 0.2),
          ]
          : [
            UsageModel(
              name: "claude-opus-5-5", tokens: tokens * 6 / 10, estimatedCost: cost * 0.75),
            UsageModel(
              name: "claude-sonnet-5-5", tokens: tokens * 4 / 10, estimatedCost: cost * 0.25),
          ]
        return UsageSummary(
          provider: provider, days: days, tokens: tokens, inputTokens: tokens * 85 / 100,
          outputTokens: tokens * 15 / 100, cachedTokens: tokens * 55 / 100,
          cacheCreationTokens: tokens / 20, estimatedCost: cost, models: models, daily: window,
          partial: false, updatedAt: now)
      }
    }
    githubStats = GitHubStats(
      login: "example",
      windows: [
        .init(days: 1, opened: 3, merged: 2, reviewed: 1),
        .init(days: 7, opened: 14, merged: 11, reviewed: 6),
        .init(days: 30, opened: 52, merged: 44, reviewed: 23),
      ],
      daily: series(4.2).map { DailyValue(day: $0.day, value: ($0.value / 120_000).rounded()) })
  }
}
