import AppKit
import Foundation
import IslandCore
import Observation
import SwiftUI
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
      if !expanded { showingSettings = false }
      // Expanding shows the full context, so a pending banner has done its job.
      if expanded, recentEvent != nil {
        notificationTask?.cancel()
        recentEvent = nil
      }
    }
  }
  var tab: IslandTab = .activity
  /// Settings replace the expanded content. They save as they change, so collapsing the island
  /// never loses an edit.
  var showingSettings = false
  /// First-run setup, shown in the expanded island until it is finished or skipped.
  var showingOnboarding = false
  var onboardingStep: OnboardingStep = .welcome
  /// The GitHub CLI's state, checked during setup.
  var githubConnection: GitHubConnection?
  /// A menu opened from the island draws outside its shape; leaving the shape for it
  /// must not collapse the island.
  @ObservationIgnored var menuOpen = false
  /// A recorded tour drives the island itself; the pointer must not open or close it.
  @ObservationIgnored private var touring = false
  var activityWindow: ActivityWindow = .month {
    didSet { if activityWindow != oldValue { regroup() } }
  }
  var usageDays = 1
  var hovered = false
  var persistenceError: String?
  var isDemo: Bool

  // Derived once per GitHub snapshot so rendering never re-filters the PR list.
  private(set) var openPRs: [PullRequest] = []
  private(set) var attention: [PullRequest] = []
  /// Your PRs that are merging, and your PRs with checks running. These make the island live.
  private(set) var merging: [PullRequest] = []
  private(set) var checking: [PullRequest] = []
  private(set) var repositories: [RepoSection] = []
  /// State columns for the board layout, after the repository filter.
  private(set) var sections: [PRSection] = []
  /// Every repository with PRs in the snapshot, for the filter menu.
  private(set) var repositoryChoices: [(name: String, avatar: URL?)] = []
  var repositoryFilter: String? = UserDefaults.standard.string(forKey: "repositoryFilter") {
    didSet {
      guard repositoryFilter != oldValue else { return }
      if !isDemo { UserDefaults.standard.set(repositoryFilter, forKey: "repositoryFilter") }
      regroup()
    }
  }
  /// PR counts per state after the repository and time filters, for the state filter bar.
  private(set) var stateCounts: [StateCount] = []
  /// PRs that need you after the repository and time filters, for the filter bar.
  private(set) var needsYouCount = 0
  /// Shows only PRs that need you; combines with `stateFilter`.
  var needsYouOnly = false {
    didSet { if needsYouOnly != oldValue { regroup() } }
  }
  /// PR states selected in the filter bar. Empty shows every state.
  var stateFilter: Set<PRGroup> = [] {
    didSet { if stateFilter != oldValue { regroup() } }
  }
  var activityLayout: ActivityLayout =
    ActivityLayout(rawValue: UserDefaults.standard.string(forKey: "activityLayout") ?? "") ?? .list
  {
    didSet {
      if !isDemo { UserDefaults.standard.set(activityLayout.rawValue, forKey: "activityLayout") }
    }
  }
  /// Repositories collapsed in the activity list, remembered across launches.
  private(set) var collapsedRepositories: Set<String> =
    Set(UserDefaults.standard.stringArray(forKey: "collapsedRepositories") ?? [])

  /// The island's laid-out size, reported by the view and used for pointer hit-testing.
  @ObservationIgnored var islandSize: CGSize = .zero

  @ObservationIgnored private let githubService = GitHubService()
  let updater = Updater()
  @ObservationIgnored private let usageService: UsageService
  @ObservationIgnored private var loops: [Task<Void, Never>] = []
  @ObservationIgnored private var hoverTask: Task<Void, Never>?
  @ObservationIgnored private var notificationTask: Task<Void, Never>?
  @ObservationIgnored private var lastGitHubRefresh = Date.distantPast
  @ObservationIgnored private var lastActiveRefresh = Date.distantPast
  /// GitHub asked us to wait (rate limit); no GitHub refresh until then.
  @ObservationIgnored private var githubPausedUntil: Date?
  /// Little of the hourly budget is left, so refresh slowly until it resets.
  @ObservationIgnored private var githubBudgetLow = false
  /// The Mac is asleep, its screens are off, or the session is locked: nobody is looking.
  @ObservationIgnored private var away = false
  @ObservationIgnored private var systemObservers: [NSObjectProtocol] = []
  @ObservationIgnored private var lastUsageRefresh = Date.distantPast
  @ObservationIgnored private var lastStatsRefresh = Date.distantPast
  @ObservationIgnored private var statsRefreshing = false

  enum IslandTab: String, CaseIterable {
    case activity = "Activity"
    case stats = "Stats"
  }

  enum ActivityLayout: String {
    case list, board
  }

  /// `idle` blends into the notch; `live` shows work in progress; `banner` announces a change.
  enum Presentation: Equatable {
    case idle, live, banner, expanded
  }

  var isLive: Bool { !merging.isEmpty || !checking.isEmpty }

  /// The PR the live state is about: the first one merging, else the first running checks.
  var livePullRequest: PullRequest? { merging.first ?? checking.first }

  var presentation: Presentation {
    if expanded { return .expanded }
    if recentEvent != nil { return .banner }
    return isLive ? .live : .idle
  }

  init(demo: Bool = false) {
    isDemo = demo
    settings = demo ? AppSettings() : AppSettings.load(from: AppFiles.settings)
    usageService = UsageService(cacheRoot: AppFiles.directory.appendingPathComponent("usage-cache"))
    if demo {
      // Previews must not depend on this Mac's remembered choices.
      repositoryFilter = nil
      activityLayout = .list
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
    attention = open.filter(\.needsYou)
    let mine = open.filter { $0.author != nil && $0.author == github?.login }
    merging = mine.filter(\.isMerging).sorted {
      ($0.queuePosition ?? .max, $1.updatedAt) < ($1.queuePosition ?? .max, $0.updatedAt)
    }
    checking = mine.filter { pr in
      !pr.isMerging && pr.status != .failed
        && ((pr.checkSummary?.pending ?? 0) > 0 || pr.checks == "PENDING")
    }
    .sorted { $0.updatedAt > $1.updatedAt }
    var avatars: [String: URL] = [:]
    for pr in all where pr.group != nil {
      if avatars[pr.repository] == nil || pr.ownerAvatar != nil {
        avatars[pr.repository] = pr.ownerAvatar
      }
    }
    let names = Set(all.filter { $0.group != nil }.map(\.repository)).sorted {
      $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }
    let choices = names.map { (name: $0, avatar: avatars[$0]) }
    if choices.map(\.name) != repositoryChoices.map(\.name)
      || choices.map(\.avatar) != repositoryChoices.map(\.avatar)
    {
      repositoryChoices = choices
    }
    let scoped = repositoryFilter.map { name in all.filter { $0.repository == name } } ?? all
    let fresh = PRGrouping.repositories(
      scoped, window: activityWindow, states: stateFilter, needsYouOnly: needsYouOnly)
    if fresh != repositories { repositories = fresh }
    let unfiltered = PRGrouping.sections(scoped, window: activityWindow)
    // Each filter counts what the other one leaves, so an empty combination is never offered.
    let counts = unfiltered.map { section in
      StateCount(
        group: section.group,
        count: needsYouOnly
          ? section.pullRequests.count(where: \.needsYou) : section.pullRequests.count)
    }
    if counts != stateCounts { stateCounts = counts }
    let attention =
      unfiltered
      .filter { stateFilter.isEmpty || stateFilter.contains($0.group) }
      .reduce(0) { $0 + $1.pullRequests.count(where: \.needsYou) }
    if attention != needsYouCount { needsYouCount = attention }
    let columns = unfiltered.compactMap { section -> PRSection? in
      guard stateFilter.isEmpty || stateFilter.contains(section.group) else { return nil }
      guard needsYouOnly else { return section }
      let shown = section.pullRequests.filter(\.needsYou)
      return shown.isEmpty ? nil : PRSection(group: section.group, pullRequests: shown)
    }
    if columns != sections { sections = columns }
  }

  func toggleState(_ group: PRGroup) {
    if stateFilter.remove(group) == nil { stateFilter.insert(group) }
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
    observeSystem()
    updater.start()
    // One loop for GitHub, so a full refresh and an active one never overlap. Discovery finds
    // new PRs and refreshes quiet ones; in between, active PRs refresh on their own schedule.
    loops.append(
      Task { [weak self] in
        while !Task.isCancelled {
          guard let self else { return }
          if canRefreshGitHub {
            let discovery =
              githubBudgetLow
              ? max(settings.githubRefreshSeconds, 300) : settings.githubRefreshSeconds
            if Date().timeIntervalSince(lastGitHubRefresh) >= discovery {
              await refreshGitHub()
            } else if !githubBudgetLow,
              Date().timeIntervalSince(lastActiveRefresh) >= settings.activeRefreshSeconds
            {
              await refreshActive()
            }
          }
          do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
      })
    loops.append(
      Task { [weak self] in
        while !Task.isCancelled {
          guard let self else { return }
          // A new day changes what "today" means, so refresh right after midnight too.
          if Date().timeIntervalSince(lastUsageRefresh) > 120
            || !Calendar.current.isDateInToday(lastUsageRefresh)
          {
            await refreshUsage()
          }
          do { try await Task.sleep(for: .seconds(10)) } catch { return }
        }
      })
    loops.append(
      Task { [weak self] in
        while !Task.isCancelled {
          guard let self else { return }
          if Date().timeIntervalSince(lastStatsRefresh) > 600
            || !Calendar.current.isDateInToday(lastStatsRefresh)
          {
            await refreshStats()
          }
          do { try await Task.sleep(for: .seconds(30)) } catch { return }
        }
      })
  }

  private var canRefreshGitHub: Bool {
    !away && (githubPausedUntil.map { Date() >= $0 } ?? true)
  }

  /// Pauses GitHub refreshes while nobody is looking, and catches up right after.
  private func observeSystem() {
    let center = NSWorkspace.shared.notificationCenter
    let pause: [Notification.Name] = [
      NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
      NSWorkspace.sessionDidResignActiveNotification,
    ]
    let resume: [Notification.Name] = [
      NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
      NSWorkspace.sessionDidBecomeActiveNotification,
    ]
    for name in pause {
      systemObservers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          Task { @MainActor in self?.away = true }
        })
    }
    for name in resume {
      systemObservers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          Task { @MainActor in
            guard let self, self.away else { return }
            self.away = false
            self.lastGitHubRefresh = .distantPast
          }
        })
    }
  }

  /// Slows down when GitHub's budget runs low, and waits when GitHub says to.
  private func pace(after error: Error? = nil) async {
    if let budget = await githubService.budget {
      githubBudgetLow = budget.remaining < 300
      if budget.remaining == 0 { githubPausedUntil = budget.resetAt }
    }
    guard let error, error.localizedDescription.localizedCaseInsensitiveContains("rate limit")
    else { return }
    // A secondary limit asks for a short wait; the hourly one lasts until its reset.
    let reset = await githubService.budget?.resetAt
    githubPausedUntil = max(Date().addingTimeInterval(120), reset ?? .distantPast)
  }

  func stop() {
    for loop in loops { loop.cancel() }
    loops = []
    updater.stop()
    for observer in systemObservers {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
    systemObservers = []
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
      await pace()
      guard
        (try? RepositorySelection(text: settings.repositories).fingerprint) == selection.fingerprint
      else { return }
      try apply(fresh)
      githubError = nil
    } catch {
      githubError = error.localizedDescription
      await pace(after: error)
    }
  }

  /// Refreshes the active PRs by ID, between full refreshes. Quiet when nothing changed.
  func refreshActive() async {
    guard !githubRefreshing, !isDemo, githubError == nil, let current = github else { return }
    let ids = current.pullRequests.filter { $0.isActive() }.map(\.id)
    lastActiveRefresh = Date()
    guard !ids.isEmpty else { return }
    do {
      let updated = try await githubService.pullRequests(ids: ids, login: current.login)
      await pace()
      // A full refresh may have landed meanwhile; merge into the latest snapshot.
      guard let latest = github, latest.login == current.login,
        latest.selection == current.selection
      else { return }
      var byID = Dictionary(latest.pullRequests.map { ($0.id, $0) }) { first, _ in first }
      var changed = false
      for var pr in updated {
        // Review requests come from search; keep what the last full refresh found.
        pr.reviewRequested = byID[pr.id]?.reviewRequested ?? false
        if byID[pr.id] != pr {
          byID[pr.id] = pr
          changed = true
        }
      }
      guard changed else { return }
      var next = latest
      next.pullRequests = byID.values.sorted { $0.updatedAt > $1.updatedAt }
      try apply(next)
    } catch { await pace(after: error) }
  }

  /// Records a new snapshot: finds what changed, saves, and announces it.
  private func apply(_ fresh: GitHubSnapshot) throws {
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
    let announced = changes.filter { settings.announcedKinds.contains($0.kind.rawValue) }
    if settings.bannersEnabled,
      let latest = announced.min(by: { $0.kind.bannerPriority < $1.kind.bannerPriority })
    {
      showEvent(latest, extra: announced.count - 1)
    }
    for event in announced { notify(event) }
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

  /// Applies and saves settings edited in the island. Only changes to what is fetched start a
  /// refetch; display preferences apply as they are.
  func applySettings(_ proposed: AppSettings) {
    do {
      _ = try RepositorySelection(text: proposed.repositories)
      guard !proposed.codexHome.isEmpty, !proposed.claudeHome.isEmpty else {
        throw ProcessFailure.failed("Choose a home directory for each agent.")
      }
      let previous = settings
      settings = proposed
      saveSettings()
      if proposed.repositories != previous.repositories {
        lastGitHubRefresh = .distantPast
        lastStatsRefresh = .distantPast
      }
      if proposed.codexHome != previous.codexHome || proposed.claudeHome != previous.claudeHome {
        lastUsageRefresh = .distantPast
      }
      NotificationCenter.default.post(name: .islandSettingsChanged, object: nil)
    } catch { persistenceError = error.localizedDescription }
  }

  /// Applies a display preference, such as a chart style, and saves it without refetching.
  func update(_ change: (inout AppSettings) -> Void) {
    change(&settings)
    guard !isDemo else { return }
    do { try settings.save(to: AppFiles.settings) } catch {
      persistenceError = error.localizedDescription
    }
  }

  func saveSettings() {
    guard !isDemo else { return }
    do {
      _ = try RepositorySelection(text: settings.repositories)
      try settings.save(to: AppFiles.settings)
      persistenceError = nil
    } catch { persistenceError = error.localizedDescription }
  }

  func setHovered(_ inside: Bool) {
    hovered = inside
    if touring { return }
    hoverTask?.cancel()
    // While something is live or announced, a click opens that PR, so expanding needs a
    // longer, deliberate hover; otherwise it would replace the island under the click.
    let busy = presentation == .live || presentation == .banner
    let delay =
      inside ? (busy ? max(settings.hoverDelay + 0.6, 0.8) : settings.hoverDelay) : 0.15
    hoverTask = Task { [weak self] in
      guard let self else { return }
      do { try await Task.sleep(for: .seconds(delay)) } catch { return }
      // A menu opened from the island draws outside it, so leaving for the menu keeps it open.
      // Setup opens the island by itself, so it stays until finished or skipped.
      if !Task.isCancelled, inside || (!menuOpen && !showingOnboarding) { expanded = inside }
    }
  }

  func startOnboarding() {
    hoverTask?.cancel()
    showingSettings = false
    onboardingStep = .welcome
    showingOnboarding = true
    expanded = true
  }

  /// Finishing and skipping both end setup for good; Settings can run it again.
  func finishOnboarding() {
    update { $0.onboardingCompleted = true }
    showingOnboarding = false
    githubConnection = nil
  }

  func checkGitHubConnection() async {
    let connection = await GitHubConnection.check()
    let wasConnected = githubConnection.map { if case .connected = $0 { true } else { false } }
    githubConnection = connection
    // The first time setup sees an account, load its pull requests behind it.
    if case .connected = connection, wasConnected != true { await refreshGitHub() }
  }

  func openSettings() {
    hoverTask?.cancel()
    showingSettings = true
    expanded = true
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

  /// Example data only: plays each kind of announcement in turn, to preview the banners.
  func runShowcase() {
    guard isDemo else { return }
    let prs = github?.pullRequests ?? []
    func event(_ kind: PRStatus, _ id: String) -> IslandEvent? {
      guard let pr = prs.first(where: { $0.id == id }) else { return nil }
      return IslandEvent(
        id: "showcase-\(kind.rawValue)", title: "\(pr.repository) #\(pr.number) · \(kind.label)",
        detail: pr.title, url: pr.url, occurredAt: Date(), kind: kind)
    }
    let sequence = [
      event(.merged, "demo6"), event(.failed, "demo2"), event(.review, "demo1"),
      event(.queued, "demo3"),
    ].compactMap { $0 }
    loops.append(
      Task { [weak self] in
        while !Task.isCancelled {
          for item in sequence {
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            self?.showEvent(item)
            // Each banner holds for 5 seconds; wait for it to collapse before the next.
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
          }
        }
      })
  }

  /// Example data only: drives the island through every state with its real animations,
  /// for recording a product video. Runs once, about 24 seconds.
  func runTour() {
    guard isDemo else { return }
    let prs = github?.pullRequests ?? []
    func event(_ kind: PRStatus, _ id: String) -> IslandEvent? {
      guard let pr = prs.first(where: { $0.id == id }) else { return nil }
      return IslandEvent(
        id: "tour-\(kind.rawValue)", title: "\(pr.repository) #\(pr.number) · \(kind.label)",
        detail: pr.title, url: pr.url, occurredAt: Date(), kind: kind)
    }
    let merged = event(.merged, "demo6")
    let failed = event(.failed, "demo2")
    touring = true
    loops.append(
      Task { [weak self] in
        @MainActor func step(_ seconds: Double, _ change: () -> Void) async throws {
          try await Task.sleep(for: .seconds(seconds))
          withAnimation(Motion.morph, change)
        }
        do {
          // Live pill, then a merge banner that grows out of it.
          if let merged { try await step(3.0) { self?.showEvent(merged) } }
          try await step(3.2) { self?.recentEvent = nil }
          // Open the island on the PR list, filter to what needs you, then back.
          try await step(1.4) {
            self?.tab = .activity
            self?.activityLayout = .list
            self?.expanded = true
          }
          try await step(2.6) { self?.needsYouOnly = true }
          try await step(1.8) { self?.needsYouOnly = false }
          // The board, then stats.
          try await step(1.4) { self?.activityLayout = .board }
          try await step(2.8) {
            self?.tab = .stats
            self?.activityLayout = .list
          }
          try await step(3.0) { self?.expanded = false }
          if let failed { try await step(1.6) { self?.showEvent(failed) } }
          try await step(3.2) { self?.recentEvent = nil }
        } catch {}
        self?.touring = false
      })
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
    if settings.notificationSound { content.sound = .default }
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: event.id, content: content, trigger: nil))
  }

  private func loadDemo() {
    let now = Date()
    let link = URL(string: "https://github.com/ppazosp/gitisle")!
    let hour = 3600.0
    let prs = [
      PullRequest(
        id: "demo1", number: 428, repository: "orbit/web", title: "Speed up cold start",
        url: link, reviewRequested: true, checks: "SUCCESS",
        checkSummary: CheckSummary(passed: 6, failed: 0, pending: 0),
        updatedAt: now.addingTimeInterval(-0.4 * hour), author: "teammate"),
      PullRequest(
        id: "demo2", number: 431, repository: "orbit/web", title: "Add keyboard shortcuts",
        url: link, checks: "FAILURE", checkSummary: CheckSummary(passed: 4, failed: 1, pending: 0),
        updatedAt: now.addingTimeInterval(-1.2 * hour), author: "maya"),
      PullRequest(
        id: "demo3", number: 433, repository: "orbit/api", title: "Cache workspace metadata",
        url: link, checks: "PENDING", checkSummary: CheckSummary(passed: 3, failed: 0, pending: 2),
        autoMerge: true, queuePosition: 2, mergingSince: now.addingTimeInterval(-95),
        updatedAt: now.addingTimeInterval(-0.1 * hour),
        author: "maya"),
      PullRequest(
        id: "demo4", number: 436, repository: "orbit/web", title: "Polish onboarding animations",
        url: link, reviewDecision: "REVIEW_REQUIRED", mergeStateStatus: "BLOCKED",
        checks: "PENDING", checkSummary: CheckSummary(passed: 2, failed: 0, pending: 3),
        updatedAt: now.addingTimeInterval(-2 * hour), author: "maya"),
      PullRequest(
        id: "demo5", number: 437, repository: "orbit/api", title: "Sketch the usage dashboard",
        url: link, isDraft: true, checks: "SUCCESS",
        checkSummary: CheckSummary(passed: 5, failed: 0, pending: 0),
        updatedAt: now.addingTimeInterval(-26 * hour), author: "maya"),
      PullRequest(
        id: "demo6", number: 425, repository: "orbit/web", title: "Ship the notch island",
        url: link, state: "MERGED", checks: "SUCCESS",
        checkSummary: CheckSummary(passed: 6, failed: 0, pending: 0),
        updatedAt: now.addingTimeInterval(-3 * hour), mergedAt: now.addingTimeInterval(-3 * hour),
        author: "maya"),
    ]
    setGitHub(GitHubSnapshot(login: "maya", pullRequests: prs))
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
          dailyCost: window.map {
            DailyValue(day: $0.day, value: $0.value / 1_000_000 * (provider == .codex ? 4.1 : 6.3))
          },
          partial: false, updatedAt: now)
      }
    }
    githubStats = GitHubStats(
      login: "maya",
      windows: [
        .init(days: 1, opened: 3, merged: 2, reviewed: 1),
        .init(days: 7, opened: 14, merged: 11, reviewed: 6),
        .init(days: 30, opened: 52, merged: 44, reviewed: 23),
      ],
      daily: series(4.2).map { DailyValue(day: $0.day, value: ($0.value / 120_000).rounded()) })
  }
}
