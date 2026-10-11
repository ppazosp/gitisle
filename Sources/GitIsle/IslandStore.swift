import AppKit
import Foundation
import IslandCore
import Observation
import UserNotifications

@MainActor @Observable
final class IslandStore {
  var settings: AppSettings
  var github: GitHubSnapshot?
  var githubError: String?
  var githubRefreshing = false
  var agents: [AgentSession] = []
  var usage: [AgentProvider: [UsageSummary]] = [:]
  var usageErrors: [AgentProvider: String] = [:]
  var usageRefreshing = false
  var events: [IslandEvent] = []
  var recentEvent: IslandEvent?
  var expanded = false
  var tab: IslandTab = .github
  var usageDays = 1
  var hovered = false
  var persistenceError: String?
  var isDemo: Bool

  @ObservationIgnored private let githubService = GitHubService()
  @ObservationIgnored private let agentReader = AgentLogReader()
  @ObservationIgnored private let usageService: UsageService
  @ObservationIgnored private var loops: [Task<Void, Never>] = []
  @ObservationIgnored private var hoverTask: Task<Void, Never>?
  @ObservationIgnored private var notificationTask: Task<Void, Never>?
  @ObservationIgnored private var lastGitHubRefresh = Date.distantPast
  @ObservationIgnored private var lastUsageRefresh = Date.distantPast

  enum IslandTab: String, CaseIterable {
    case github = "GitHub"
    case agents = "Agents"
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
  }

  var openPRs: [PullRequest] { (github?.pullRequests ?? []).filter { $0.state == "OPEN" } }
  var attention: [PullRequest] { openPRs.filter { $0.status.needsAttention } }
  var workingCount: Int { agents.filter(\.isActive).count }
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
          await refreshAgents()
          do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
      })
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
  }

  func stop() {
    for loop in loops { loop.cancel() }
    loops = []
    hoverTask?.cancel()
    notificationTask?.cancel()
  }

  func refreshAgents() async {
    let paths = (settings.codexHome, settings.claudeHome)
    let fresh = await agentReader.sessions(
      codexHome: URL(fileURLWithPath: NSString(string: paths.0).expandingTildeInPath),
      claudeHome: URL(fileURLWithPath: NSString(string: paths.1).expandingTildeInPath))
    guard settings.codexHome == paths.0, settings.claudeHome == paths.1 else { return }
    agents = fresh
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
      github = fresh
      githubError = nil
      if let latest = changes.first { showEvent(latest) }
      for event in changes { notify(event) }
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

  func showEvent(_ event: IslandEvent) {
    recentEvent = event
    notificationTask?.cancel()
    notificationTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(5)) } catch { return }
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
    let prs = [
      PullRequest(
        id: "demo1", number: 428, repository: "example/app", title: "Improve sandbox startup",
        url: URL(string: "https://github.com/ppazosp/gitisle")!, reviewRequested: true,
        checks: "SUCCESS"),
      PullRequest(
        id: "demo2", number: 431, repository: "example/app", title: "Add project shortcuts",
        url: URL(string: "https://github.com/ppazosp/gitisle")!, checks: "FAILURE"),
      PullRequest(
        id: "demo3", number: 433, repository: "example/tools", title: "Cache workspace metadata",
        url: URL(string: "https://github.com/ppazosp/gitisle")!, checks: "PENDING", autoMerge: true),
    ]
    github = GitHubSnapshot(login: "example", pullRequests: prs)
    agents = [
      AgentSession(
        id: "demo-codex", provider: .codex, source: "Codex desktop", directory: "/example/app",
        branch: "feat/startup", model: "GPT-6", phase: .working, activity: "Running checks",
        updatedAt: now),
      AgentSession(
        id: "demo-claude", provider: .claude, source: "Claude Code", directory: "/example/tools",
        branch: "feat/cache", model: "Sonnet", phase: .finished, activity: "Turn completed",
        updatedAt: now),
    ]
    for provider in AgentProvider.allCases {
      var summaries: [UsageSummary] = []
      for days: Int in [1, 7, 30] {
        let tokens = 760_000 * days
        let cost = 4.21 * Double(days)
        let model = UsageModel(
          name: provider == .codex ? "GPT-6" : "Sonnet", tokens: tokens, estimatedCost: cost)
        let summary = UsageSummary(
          provider: provider, days: days, tokens: 760_000 * days, inputTokens: 650_000 * days,
          outputTokens: 110_000 * days, cachedTokens: 420_000 * days, cacheCreationTokens: 0,
          estimatedCost: cost, models: [model], partial: false, updatedAt: now)
        summaries.append(summary)
      }
      usage[provider] = summaries
    }
  }
}
