import Foundation

public enum PRStatus: String, Codable, Sendable {
  case review, failed, conflicts, changesRequested, queued, checking, ready, draft, waiting, behind,
    blocked, merged,
    closed, unknown

  public var label: String {
    switch self {
    case .review: "Review requested"
    case .failed: "Checks failed"
    case .conflicts: "Merge conflicts"
    case .changesRequested: "Changes requested"
    case .queued: "In merge queue"
    case .checking: "Checks running"
    case .ready: "Ready to merge"
    case .draft: "Draft"
    case .waiting: "Waiting for review"
    case .behind: "Branch behind base"
    case .blocked: "Merge blocked"
    case .merged: "Merged"
    case .closed: "Closed"
    case .unknown: "Status unavailable"
    }
  }

  public var needsAttention: Bool {
    [.review, .failed, .conflicts, .changesRequested, .ready, .behind, .blocked].contains(self)
  }
}

/// Check runs and commit statuses on a PR's head commit, grouped by outcome.
public struct CheckSummary: Codable, Hashable, Sendable {
  public var passed: Int
  public var failed: Int
  public var pending: Int

  public init(passed: Int, failed: Int, pending: Int) {
    self.passed = passed
    self.failed = failed
    self.pending = pending
  }

  public var total: Int { passed + failed + pending }

  static let passedStates: Set<String> = ["SUCCESS", "NEUTRAL", "SKIPPED"]
  static let failedStates: Set<String> = [
    "FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "STARTUP_FAILURE", "ACTION_REQUIRED",
  ]

  /// Counts by GitHub state name. Unrecognized in-flight states count as pending.
  public init(counts: [(state: String, count: Int)]) {
    var passed = 0
    var failed = 0
    var pending = 0
    for (state, count) in counts where count > 0 {
      if Self.passedStates.contains(state) {
        passed += count
      } else if Self.failedStates.contains(state) {
        failed += count
      } else if state != "STALE" {
        pending += count
      }
    }
    self.init(passed: passed, failed: failed, pending: pending)
  }
}

public struct PullRequest: Codable, Hashable, Identifiable, Sendable {
  public var id: String
  public var number: Int
  public var repository: String
  public var title: String
  public var url: URL
  public var author: String?
  public var state: String
  public var isDraft: Bool
  public var reviewDecision: String?
  public var reviewRequested: Bool
  public var mergeable: String
  public var mergeStateStatus: String
  public var checks: String?
  public var checkSummary: CheckSummary?
  public var headOID: String
  public var autoMerge: Bool
  public var queuePosition: Int?
  /// When the PR entered the merge queue, or when auto-merge was enabled.
  public var mergingSince: Date?
  public var updatedAt: Date
  public var mergedAt: Date?

  public init(
    id: String, number: Int, repository: String, title: String, url: URL, state: String = "OPEN",
    isDraft: Bool = false, reviewDecision: String? = nil, reviewRequested: Bool = false,
    mergeable: String = "UNKNOWN", mergeStateStatus: String = "UNKNOWN", checks: String? = nil,
    checkSummary: CheckSummary? = nil, headOID: String = "", autoMerge: Bool = false,
    queuePosition: Int? = nil, mergingSince: Date? = nil, updatedAt: Date = Date(),
    mergedAt: Date? = nil, author: String? = nil
  ) {
    self.id = id
    self.number = number
    self.repository = repository
    self.title = title
    self.url = url
    self.state = state
    self.isDraft = isDraft
    self.reviewDecision = reviewDecision
    self.reviewRequested = reviewRequested
    self.mergeable = mergeable
    self.mergeStateStatus = mergeStateStatus
    self.checks = checks
    self.checkSummary = checkSummary
    self.headOID = headOID
    self.autoMerge = autoMerge
    self.queuePosition = queuePosition
    self.mergingSince = mergingSince
    self.updatedAt = updatedAt
    self.mergedAt = mergedAt
    self.author = author
  }

  /// In the merge queue, or set to merge automatically without a blocking problem.
  public var isMerging: Bool {
    guard state == "OPEN", !isDraft else { return false }
    guard queuePosition != nil || autoMerge else { return false }
    return ![.failed, .conflicts, .changesRequested].contains(status)
  }

  /// The GitHub-style section this PR belongs to. Closed PRs are not shown.
  public var group: PRGroup? {
    switch state {
    case "MERGED": return .merged
    case "OPEN": break
    default: return nil
    }
    if isDraft { return .draft }
    if isMerging { return .merging }
    if status.needsAttention { return .needsYou }
    return .open
  }

  public var status: PRStatus {
    if state == "MERGED" { return .merged }
    if state == "CLOSED" { return .closed }
    if state != "OPEN" { return .unknown }
    if checks == "FAILURE" || checks == "ERROR" { return .failed }
    if mergeable == "CONFLICTING" { return .conflicts }
    if reviewDecision == "CHANGES_REQUESTED" { return .changesRequested }
    if reviewRequested { return .review }
    if isDraft { return .draft }
    if queuePosition != nil { return .queued }
    if checks == "PENDING" || checks == "EXPECTED" { return .checking }
    if mergeStateStatus == "CLEAN" || mergeStateStatus == "HAS_HOOKS" { return .ready }
    if reviewDecision == "REVIEW_REQUIRED" { return .waiting }
    if mergeStateStatus == "BEHIND" { return .behind }
    if mergeStateStatus == "BLOCKED" { return .blocked }
    return .unknown
  }
}

public enum PRGroup: String, CaseIterable, Sendable {
  case needsYou, merging, open, draft, merged

  public var label: String {
    switch self {
    case .needsYou: "Needs you"
    case .merging: "Merging"
    case .open: "Open"
    case .draft: "Draft"
    case .merged: "Merged"
    }
  }
}

/// A time filter for activity. `days` counts today as the first day.
public enum ActivityWindow: String, CaseIterable, Codable, Sendable {
  case today, week, all

  public var label: String {
    switch self {
    case .today: "Today"
    case .week: "7 days"
    case .all: "All"
    }
  }

  public func includes(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
    switch self {
    case .all: return true
    case .today: return date >= calendar.startOfDay(for: now)
    case .week:
      let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
      return date >= start
    }
  }
}

public struct PRSection: Identifiable, Equatable, Sendable {
  public var group: PRGroup
  public var pullRequests: [PullRequest]
  public var id: PRGroup { group }
}

/// One repository's PRs, ordered by state as in `PRGroup` and then by activity.
public struct RepoSection: Identifiable, Equatable, Sendable {
  public var repository: String
  public var pullRequests: [PullRequest]
  public var id: String { repository }

  public var owner: String { repository.split(separator: "/").first.map(String.init) ?? "" }
  public var name: String { repository.split(separator: "/").last.map(String.init) ?? repository }

  /// PR counts per state, in display order, omitting empty states.
  public var counts: [(group: PRGroup, count: Int)] {
    PRGroup.allCases.compactMap { group in
      let count = pullRequests.count { $0.group == group }
      return count > 0 ? (group, count) : nil
    }
  }

  public static func == (lhs: RepoSection, rhs: RepoSection) -> Bool {
    lhs.repository == rhs.repository && lhs.pullRequests == rhs.pullRequests
  }
}

public enum PRGrouping {
  /// Repositories that need you come first, then those merging, then by latest activity.
  public static func repositories(
    _ pullRequests: [PullRequest], window: ActivityWindow, now: Date = Date(),
    calendar: Calendar = .current
  ) -> [RepoSection] {
    var order: [String] = []
    var buckets: [String: [PullRequest]] = [:]
    for section in sections(pullRequests, window: window, now: now, calendar: calendar) {
      for pr in section.pullRequests {
        if buckets[pr.repository] == nil { order.append(pr.repository) }
        buckets[pr.repository, default: []].append(pr)
      }
    }
    func rank(_ prs: [PullRequest]) -> Int {
      PRGroup.allCases.firstIndex { group in prs.contains { $0.group == group } } ?? .max
    }
    func latest(_ prs: [PullRequest]) -> Date {
      prs.map { $0.mergedAt ?? $0.updatedAt }.max() ?? .distantPast
    }
    return order.map { RepoSection(repository: $0, pullRequests: buckets[$0] ?? []) }
      .sorted { lhs, rhs in
        let (left, right) = (rank(lhs.pullRequests), rank(rhs.pullRequests))
        if left != right { return left < right }
        let (newer, older) = (latest(lhs.pullRequests), latest(rhs.pullRequests))
        if newer != older { return newer > older }
        return lhs.repository < rhs.repository
      }
  }

  public static func sections(
    _ pullRequests: [PullRequest], window: ActivityWindow, now: Date = Date(),
    calendar: Calendar = .current
  ) -> [PRSection] {
    var buckets: [PRGroup: [PullRequest]] = [:]
    for pr in pullRequests {
      guard let group = pr.group else { continue }
      let activity = group == .merged ? (pr.mergedAt ?? pr.updatedAt) : pr.updatedAt
      guard window.includes(activity, now: now, calendar: calendar) else { continue }
      buckets[group, default: []].append(pr)
    }
    return PRGroup.allCases.compactMap { group in
      guard var rows = buckets[group], !rows.isEmpty else { return nil }
      switch group {
      case .merging:
        rows.sort {
          ($0.queuePosition ?? .max, $1.updatedAt) < ($1.queuePosition ?? .max, $0.updatedAt)
        }
      case .merged:
        rows.sort { ($0.mergedAt ?? $0.updatedAt) > ($1.mergedAt ?? $1.updatedAt) }
      default:
        rows.sort { $0.updatedAt > $1.updatedAt }
      }
      return PRSection(group: group, pullRequests: rows)
    }
  }
}

public struct GitHubSnapshot: Codable, Sendable {
  public var login: String
  public var pullRequests: [PullRequest]
  public var fetchedAt: Date
  public var selection: String
  public var isLimited: Bool

  public init(
    login: String, pullRequests: [PullRequest], fetchedAt: Date = Date(), selection: String = "",
    isLimited: Bool = false
  ) {
    self.login = login
    self.pullRequests = pullRequests
    self.fetchedAt = fetchedAt
    self.selection = selection
    self.isLimited = isLimited
  }
}

public enum AgentProvider: String, Codable, CaseIterable, Sendable {
  case codex, claude
  public var label: String { self == .codex ? "Codex" : "Claude Code" }
}

/// One value for a calendar day, keyed by its local `yyyy-MM-dd` date.
public struct DailyValue: Equatable, Identifiable, Sendable {
  public var day: String
  public var value: Double
  public var id: String { day }

  public init(day: String, value: Double) {
    self.day = day
    self.value = value
  }
}

public struct UsageModel: Identifiable, Sendable {
  public var id: String { name }
  public var name: String
  public var tokens: Int?
  public var estimatedCost: Double?

  public init(name: String, tokens: Int?, estimatedCost: Double?) {
    self.name = name
    self.tokens = tokens
    self.estimatedCost = estimatedCost
  }
}

public struct UsageSummary: Sendable {
  public var provider: AgentProvider
  public var days: Int
  public var tokens: Int?
  public var inputTokens: Int?
  public var outputTokens: Int?
  public var cachedTokens: Int?
  public var cacheCreationTokens: Int?
  public var estimatedCost: Double?
  public var models: [UsageModel]
  public var daily: [DailyValue]
  public var partial: Bool
  public var updatedAt: Date

  public init(
    provider: AgentProvider, days: Int, tokens: Int?, inputTokens: Int?, outputTokens: Int?,
    cachedTokens: Int?, cacheCreationTokens: Int?, estimatedCost: Double?, models: [UsageModel],
    daily: [DailyValue] = [], partial: Bool, updatedAt: Date
  ) {
    self.provider = provider
    self.days = days
    self.tokens = tokens
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.cachedTokens = cachedTokens
    self.cacheCreationTokens = cacheCreationTokens
    self.estimatedCost = estimatedCost
    self.models = models
    self.daily = daily
    self.partial = partial
    self.updatedAt = updatedAt
  }
}

/// Personal GitHub activity counts for the same windows as local usage.
public struct GitHubStats: Equatable, Sendable {
  public struct Window: Equatable, Sendable {
    public var days: Int
    public var opened: Int
    public var merged: Int
    public var reviewed: Int

    public init(days: Int, opened: Int, merged: Int, reviewed: Int) {
      self.days = days
      self.opened = opened
      self.merged = merged
      self.reviewed = reviewed
    }
  }

  public var login: String
  public var windows: [Window]
  /// Contributions per day for the last 30 days, oldest first.
  public var daily: [DailyValue]
  public var fetchedAt: Date

  public init(login: String, windows: [Window], daily: [DailyValue], fetchedAt: Date = Date()) {
    self.login = login
    self.windows = windows
    self.daily = daily
    self.fetchedAt = fetchedAt
  }

  public func window(days: Int) -> Window? { windows.first { $0.days == days } }
}

public struct IslandEvent: Codable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var detail: String
  public var url: URL
  public var occurredAt: Date
  public var kind: PRStatus

  public init(
    id: String, title: String, detail: String, url: URL, occurredAt: Date, kind: PRStatus
  ) {
    self.id = id
    self.title = title
    self.detail = detail
    self.url = url
    self.occurredAt = occurredAt
    self.kind = kind
  }

  /// Merging announcements show in the island but are not system notifications.
  public var notifiesSystem: Bool { kind != .queued }
}

public enum GitHubChanges {
  public static func events(previous: GitHubSnapshot?, current: GitHubSnapshot) -> [IslandEvent] {
    guard let previous, previous.login == current.login, previous.selection == current.selection
    else { return [] }
    let old = Dictionary(
      previous.pullRequests.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return current.pullRequests.compactMap { pr in
      guard let prior = old[pr.id] else {
        guard pr.reviewRequested else { return nil }
        return IslandEvent(
          id: "\(pr.id):review:\(pr.headOID)",
          title: "\(pr.repository) #\(pr.number) · Review requested",
          detail: pr.title, url: pr.url, occurredAt: current.fetchedAt, kind: .review)
      }
      let merged = prior.state == "OPEN" && pr.state == "MERGED"
      let failed = pr.status == .failed && (prior.status != .failed || prior.headOID != pr.headOID)
      let review = pr.reviewRequested && !prior.reviewRequested
      // Only your own PRs announce merging; watched repositories would be too noisy.
      let merging = pr.isMerging && !prior.isMerging && pr.author == current.login
      guard merged || failed || review || merging else { return nil }
      let kind: PRStatus = merged ? .merged : failed ? .failed : review ? .review : .queued
      let occurrence =
        merged ? (pr.mergedAt ?? pr.updatedAt).timeIntervalSince1970.description : pr.headOID
      return IslandEvent(
        id: "\(pr.id):\(kind.rawValue):\(occurrence)",
        title: "\(pr.repository) #\(pr.number) · \(kind == .queued ? "Merging" : kind.label)",
        detail: pr.title,
        url: pr.url, occurredAt: current.fetchedAt, kind: kind)
    }
  }
}

public enum UsageMath {
  public static func tokens(_ values: [Int?]) -> Int? {
    guard !values.isEmpty else { return nil }
    var total = 0
    for value in values {
      guard let value, value >= 0 else { return nil }
      let (sum, overflow) = total.addingReportingOverflow(value)
      guard !overflow else { return nil }
      total = sum
    }
    return total
  }
  public static func costs(_ values: [Double?]) -> Double? {
    guard !values.isEmpty else { return nil }
    var total = 0.0
    for value in values {
      guard let value, value.isFinite, value >= 0 else { return nil }
      total += value
      guard total.isFinite else { return nil }
    }
    return total
  }
}

public struct RepositorySelection: Sendable {
  public var repositories: [String]

  public init(text: String) throws {
    let names = text.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
    let valid = names.allSatisfy { name in
      let parts = name.split(separator: "/", omittingEmptySubsequences: false)
      return parts.count == 2
        && parts.allSatisfy { part in
          !part.isEmpty
            && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
        }
    }
    guard valid, names.count <= 20 else { throw SelectionError.invalid }
    repositories = Array(Set(names)).sorted()
  }

  public var fingerprint: String { repositories.joined(separator: ",") }
  public var searchQuery: String { repositories.map { "repo:\($0)" }.joined(separator: " ") }

  public enum SelectionError: LocalizedError {
    case invalid
    public var errorDescription: String? {
      "Use owner/repository names, separated by commas or new lines (up to 20)."
    }
  }
}
