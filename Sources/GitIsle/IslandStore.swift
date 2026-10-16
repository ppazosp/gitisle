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
      if !expanded {
        showingSettings = false
        repositoryPickerOpen = false
        detailsID = nil
      }
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
  /// The repositories the island is about: Activity, the live bar, banners, and notifications
  /// follow it. Empty means every repository.
  var repositoryFilter: Set<String> = IslandStore.savedRepositoryFilter() {
    didSet {
      guard repositoryFilter != oldValue else { return }
      if !isDemo {
        UserDefaults.standard.set(repositoryFilter.sorted(), forKey: "repositoryFilters")
      }
      regroup()
      repositoryFilterChanged()
    }
  }
  /// The repository picker is open over Activity.
  var repositoryPickerOpen = false
  /// The PR whose page replaces Activity, by ID.
  private(set) var detailsID: String? {
    didSet { if detailsID != oldValue { loadDetails() } }
  }
  /// Pages read so far, by PR ID; an open page keeps its own fresh.
  private(set) var pullRequestDetails: [String: PullRequestDetails] = [:]
  private(set) var detailsError: String?
  @ObservationIgnored private var detailsTask: Task<Void, Never>?

  var detailsPullRequest: PullRequest? {
    detailsID.flatMap { id in github?.pullRequests.first { $0.id == id } }
  }

  func openDetails(_ pr: PullRequest) {
    repositoryPickerOpen = false
    detailsID = pr.id
  }

  func closeDetails() { detailsID = nil }

  /// Reads the open page, then again every 10 seconds while the PR is active and every minute
  /// otherwise, for about a point each.
  private func loadDetails() {
    detailsTask?.cancel()
    detailsError = nil
    guard let id = detailsID else { return }
    if isDemo {
      pullRequestDetails[id] = demoDetails(id)
      return
    }
    detailsTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self, let pr = detailsPullRequest, pr.id == id else { return }
        do {
          let details = try await githubService.details(of: pr)
          guard !Task.isCancelled else { return }
          pullRequestDetails[id] = details
          detailsError = nil
        } catch {
          if pullRequestDetails[id] == nil { detailsError = error.localizedDescription }
        }
        await pace()
        let wait = pr.isActive() ? max(settings.activeRefreshSeconds, 10) : 60
        do { try await Task.sleep(for: .seconds(wait)) } catch { return }
      }
    }
  }

  private static func savedRepositoryFilter() -> Set<String> {
    let defaults = UserDefaults.standard
    if let saved = defaults.stringArray(forKey: "repositoryFilters") { return Set(saved) }
    // Earlier versions kept one repository.
    return defaults.string(forKey: "repositoryFilter").map { [$0] } ?? []
  }

  /// Whether the repository filter lets this repository through. Events saved before they
  /// named their repository always pass.
  func shows(_ repository: String?) -> Bool {
    guard let repository else { return true }
    return repositoryFilter.isEmpty || repositoryFilter.contains(repository)
  }

  /// Takes back what the filter now hides, and refreshes active PRs right away so the live bar
  /// is current. Every repository is already loaded, so nothing else needs reading.
  private func repositoryFilterChanged() {
    if let event = recentEvent, !shows(event.repository) {
      notificationTask?.cancel()
      recentEvent = nil
    }
    guard !isDemo else { return }
    let hidden = events.filter { !shows($0.repository) }.map(\.id)
    if !hidden.isEmpty {
      UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: hidden)
    }
    lastActiveRefresh = .distantPast
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
  /// When every search last ran in full; between those, a one-point check finds what changed.
  @ObservationIgnored private var lastFullRefresh = Date.distantPast
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
      repositoryFilter = []
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
    // The live bar follows the repository filter.
    let mine = open.filter {
      $0.author != nil && $0.author == github?.login && shows($0.repository)
    }
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
    // Chosen repositories stay listed even with no PRs right now, so they can be unchosen.
    let names = Set(all.filter { $0.group != nil }.map(\.repository)).union(repositoryFilter)
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    let choices = names.map { (name: $0, avatar: avatars[$0]) }
    if choices.map(\.name) != repositoryChoices.map(\.name)
      || choices.map(\.avatar) != repositoryChoices.map(\.avatar)
    {
      repositoryChoices = choices
    }
    let scoped = repositoryFilter.isEmpty ? all : all.filter { shows($0.repository) }
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
            // With nobody at the Mac, active PRs refresh once a minute; banners still land
            // within a minute, and the next keypress or mouse move brings the pace back.
            let active =
              Self.idleSeconds >= 300
              ? max(settings.activeRefreshSeconds, 60) : settings.activeRefreshSeconds
            if Date().timeIntervalSince(lastGitHubRefresh) >= discovery {
              await discover()
            } else if !githubBudgetLow, Date().timeIntervalSince(lastActiveRefresh) >= active {
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

  /// Seconds since the last keyboard, mouse, or trackpad input.
  private static var idleSeconds: TimeInterval {
    // ~0 is kCGAnyInputEventType: any kind of input.
    guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
    return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
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

  /// Every 10 minutes, and whenever there's nothing to compare against, every search runs in
  /// full. In between, a one-point check of the searches names the PRs that changed, and only
  /// those are read: most minutes cost one point instead of six to eight.
  private func discover() async {
    guard let current = github, current.searchFingerprint != nil,
      Date().timeIntervalSince(lastFullRefresh) < 600,
      (try? RepositorySelection(text: settings.repositories).fingerprint) == current.selection,
      await refreshChanged(current)
    else { return await refreshGitHub() }
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
      lastFullRefresh = Date()
      githubError = nil
    } catch {
      githubError = error.localizedDescription
      await pace(after: error)
    }
  }

  /// Reads only the PRs the one-point check says changed. False when the check can't stand in
  /// for a full refresh: a search found too many PRs, or the account changed.
  private func refreshChanged(_ current: GitHubSnapshot) async -> Bool {
    guard !githubRefreshing, !isDemo, let baseline = current.searchFingerprint else {
      return true
    }
    githubRefreshing = true
    defer { githubRefreshing = false }
    do {
      let selection = try RepositorySelection(text: settings.repositories)
      guard
        let (login, fingerprint) = try await githubService.searchFingerprint(selection: selection),
        login == current.login
      else { return false }
      let changed = fingerprint.changedIDs(since: baseline)
      let updated =
        changed.isEmpty ? [] : try await githubService.pullRequests(ids: changed, login: login)
      await pace()
      lastGitHubRefresh = Date()
      // A full refresh may have landed meanwhile; merge into the latest snapshot.
      guard let latest = github, latest.login == login, latest.selection == selection.fingerprint
      else { return true }
      var byID = Dictionary(latest.pullRequests.map { ($0.id, $0) }) { first, _ in first }
      for var pr in updated {
        pr.reviewRequested = fingerprint.found(pr.id, by: "reviews")
        byID[pr.id] = pr
      }
      var next = latest
      next.pullRequests = byID.values.sorted { $0.updatedAt > $1.updatedAt }
      next.fetchedAt = Date()
      next.searchFingerprint = fingerprint
      try apply(next)
      githubError = nil
    } catch {
      lastGitHubRefresh = Date()
      githubError = error.localizedDescription
      await pace(after: error)
    }
    return true
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
    let announced = changes.filter {
      settings.announcedKinds.contains($0.kind.rawValue) && shows($0.repository)
    }
    guard !announced.isEmpty else { return }
    Task { await announce(announced) }
  }

  /// Names the checks behind a failure before announcing it, for about a point per PR, so
  /// the banner reads "Checks failed: unit" rather than just "Checks failed".
  private func announce(_ changes: [IslandEvent]) async {
    var announced = changes
    for index in announced.indices.filter({ announced[$0].kind == .failed }).prefix(3) {
      guard
        let pr = github?.pullRequests.first(where: { $0.url == announced[index].url }),
        let details = try? await githubService.details(of: pr)
      else { continue }
      pullRequestDetails[pr.id] = details
      announced[index].note = details.failureNote
    }
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
    guard shows(event.repository) else { return }
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

  /// Every kind of announcement, in the order the showcase plays them.
  static let announcementKinds: [PRStatus] = [
    .opened, .draft, .readyForReview, .ready, .previewReady, .queued, .merged, .failed, .review,
  ]

  /// Example data only: an announcement of this kind about a fitting example PR.
  private func demoEvent(_ kind: PRStatus) -> IslandEvent? {
    let examples: [PRStatus: String] = [
      .opened: "demo4", .draft: "demo5", .readyForReview: "demo4", .ready: "demo4",
      .previewReady: "demo4",
      .queued: "demo3", .merged: "demo6", .failed: "demo2", .review: "demo1",
    ]
    guard let id = examples[kind], let pr = github?.pullRequests.first(where: { $0.id == id })
    else { return nil }
    var event = IslandEvent(
      id: "showcase-\(kind.rawValue)", title: "\(pr.repository) #\(pr.number) · \(kind.label)",
      detail: pr.title, url: pr.url, occurredAt: Date(), kind: kind, repository: pr.repository)
    if kind == .failed { event.note = demoDetails(id)?.failureNote }
    if kind == .previewReady, let preview = pr.readyPreviews.first, let url = preview.url {
      event.url = url
      event.note = pr.readyPreviews.map(\.name).joined(separator: ", ")
    }
    return event
  }

  /// Example data only: shows one announcement's banner, to preview it.
  func previewEvent(_ kind: PRStatus) {
    guard isDemo, let event = demoEvent(kind) else { return }
    showEvent(event)
  }

  /// Example data only: one PR's life for the website's captures (`--story <kind>`). #433 is in
  /// the state the announcement is about, and nothing else is live, so the live bar shows only
  /// while #433 is merging.
  func previewStory(_ kind: PRStatus) {
    guard isDemo, var snapshot = github,
      let index = snapshot.pullRequests.firstIndex(where: { $0.id == "demo3" })
    else { return }
    for other in snapshot.pullRequests.indices where other != index {
      snapshot.pullRequests[other].checks = "SUCCESS"
      snapshot.pullRequests[other].checkSummary = CheckSummary(passed: 5, failed: 0, pending: 0)
      snapshot.pullRequests[other].autoMerge = false
      snapshot.pullRequests[other].queuePosition = nil
    }
    var pr = snapshot.pullRequests[index]
    if kind != .queued {
      pr.autoMerge = false
      pr.queuePosition = nil
      pr.mergingSince = nil
      pr.checks = "SUCCESS"
      pr.checkSummary = CheckSummary(passed: 5, failed: 0, pending: 0)
    }
    switch kind {
    case .draft: pr.isDraft = true
    case .failed:
      pr.checks = "FAILURE"
      pr.checkSummary = CheckSummary(passed: 4, failed: 1, pending: 0)
    case .ready: pr.mergeStateStatus = "CLEAN"
    case .merged:
      pr.state = "MERGED"
      pr.mergedAt = Date()
    default: break
    }
    snapshot.pullRequests[index] = pr
    setGitHub(snapshot)
    showEvent(
      IslandEvent(
        id: "story-\(kind.rawValue)", title: "\(pr.repository) #\(pr.number) · \(kind.label)",
        detail: pr.title, url: pr.url, occurredAt: Date(), kind: kind, repository: pr.repository))
  }

  /// Example data only: plays each kind of announcement in turn, to preview the banners.
  func runShowcase() {
    guard isDemo else { return }
    let sequence = Self.announcementKinds.compactMap(demoEvent)
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
        detail: pr.title, url: pr.url, occurredAt: Date(), kind: kind, repository: pr.repository)
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
    guard settings.notificationsEnabled, shows(event.repository) else { return }
    let content = UNMutableNotificationContent()
    if event.kind == .failed, let note = event.note {
      content.title = "\(event.title): \(note)"
      content.body = event.detail
    } else {
      content.title = event.title
      content.body = event.note.map { "\($0) · \(event.detail)" } ?? event.detail
    }
    content.userInfo = ["url": event.url.absoluteString]
    if settings.notificationSound { content.sound = .default }
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: event.id, content: content, trigger: nil))
  }

  /// Example data only: a page for each example PR.
  private func demoDetails(_ id: String) -> PullRequestDetails? {
    guard let pr = github?.pullRequests.first(where: { $0.id == id }) else { return nil }
    let now = Date()
    let started = now.addingTimeInterval(-420)
    func check(
      _ name: String, _ outcome: Check.Outcome, seconds: TimeInterval = 180,
      errors: [Check.Annotation] = []
    ) -> Check {
      Check(
        name: name, workflow: "CI", outcome: outcome, startedAt: started,
        completedAt: outcome == .running ? nil : started.addingTimeInterval(seconds),
        url: pr.url, errors: errors)
    }
    var checks = [check("lint", .passed, seconds: 41), check("build", .passed, seconds: 212)]
    switch id {
    case "demo2":
      checks.insert(
        check(
          "unit", .failed, seconds: 301,
          errors: [
            .init(
              path: "Sources/Shortcuts/KeyMap.swift", line: 48,
              message: "XCTAssertEqual failed: (\"⌘K\") is not equal to (\"⌘⇧K\")"),
            .init(
              path: "Sources/Shortcuts/Recorder.swift", line: 112,
              message: "Fatal error: Unexpectedly found nil while unwrapping an Optional value"),
          ]), at: 0)
      checks.append(check("CI Success", .failed, seconds: 3))
    case "demo3", "demo4":
      checks += [check("unit", .running), check("e2e", .running)]
    default:
      checks += [check("unit", .passed, seconds: 287), check("e2e", .passed, seconds: 344)]
    }
    return PullRequestDetails(
      id: id,
      body: """
        \(pr.title) so the island feels instant.

        Measured on a cold launch: 1.4 s before, 0.6 s after. The cache is invalidated on every \
        push, and falls back to a full read when it's older than a day.
        """,
      author: pr.author, baseRefName: "main", headRefName: "maya/\(pr.number)",
      createdAt: now.addingTimeInterval(-26 * 3600), additions: 342, deletions: 61,
      changedFiles: 9,
      files: [
        .init(path: "Sources/Core/Cache.swift", additions: 188, deletions: 12),
        .init(path: "Sources/Core/Loader.swift", additions: 74, deletions: 31),
        .init(path: "Tests/CoreTests/CacheTests.swift", additions: 61, deletions: 0),
        .init(path: "Sources/App/Launch.swift", additions: 12, deletions: 9),
        .init(path: "README.md", additions: 7, deletions: 9),
      ],
      commitCount: 6, requestedReviewers: id == "demo4" ? ["sam", "core"] : ["sam"],
      reviews: [
        .init(author: "lena", state: "APPROVED", submittedAt: now.addingTimeInterval(-5400))
      ],
      commentCount: 4,
      comments: [
        .init(
          author: "lena", body: "Nice. Could the cache key include the locale?",
          createdAt: now.addingTimeInterval(-7200)),
        .init(
          author: pr.author ?? "maya", body: "Good call, added in the last commit.",
          createdAt: now.addingTimeInterval(-3600)),
      ],
      checks: checks, previews: pr.previews ?? [], fetchedAt: now)
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
        author: "maya", previews: [PreviewDeploy(name: "orbit-api", state: .building)]),
      PullRequest(
        id: "demo4", number: 436, repository: "orbit/web", title: "Polish onboarding animations",
        url: link, reviewDecision: "REVIEW_REQUIRED", mergeStateStatus: "BLOCKED",
        checks: "PENDING", checkSummary: CheckSummary(passed: 2, failed: 0, pending: 3),
        updatedAt: now.addingTimeInterval(-2 * hour), author: "maya",
        previews: [
          PreviewDeploy(
            name: "orbit-web", state: .ready,
            url: URL(string: "https://orbit-web-git-436.vercel.app")),
          PreviewDeploy(
            name: "orbit-docs", state: .ready,
            url: URL(string: "https://orbit-docs-git-436.vercel.app")),
        ]),
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
