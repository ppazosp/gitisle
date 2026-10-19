import Foundation

public enum PRStatus: String, Codable, Sendable {
  case review, failed, conflicts, changesRequested, queued, checking, ready, draft, waiting, behind,
    blocked, merged,
    closed, unknown
  /// Only announced: one of your PRs opened ready for review, or a draft of yours marked ready.
  case opened, readyForReview
  /// Only announced: a preview deploy of one of your PRs is ready to open.
  case previewReady
  /// Only announced: one of your PRs left the merge queue without merging.
  case mergeFailed

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
    case .opened: "New PR"
    case .readyForReview: "Ready for review"
    case .previewReady: "Preview ready"
    case .mergeFailed: "Merge failed"
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
  /// The repository owner's avatar, which GitHub shows as the repository's image.
  public var ownerAvatar: URL?
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
  /// When the PR started merging: when it entered the merge queue, or, without a queue, when
  /// GitIsle first saw it set to merge with nothing left to wait for.
  public var mergingSince: Date?
  /// The merge queue's own checks, run on the commit it would merge; nil outside the queue.
  public var queueChecks: CheckSummary?
  /// The merge queue entry's state: QUEUED, AWAITING_CHECKS, MERGEABLE, UNMERGEABLE, or LOCKED.
  public var queueState: String?
  public var updatedAt: Date
  public var mergedAt: Date?
  /// When the PR was opened; nil in snapshots saved before it was read.
  public var createdAt: Date?
  /// Preview deploys of the head commit, from hosts that report them to GitHub (Vercel,
  /// Netlify, Railway, and others). Nil when they haven't been read: only active and changed
  /// PRs read them, and full searches keep what was read for the same commit.
  public var previews: [PreviewDeploy]?
  /// The PR's branch, and the branch it merges into; nil in snapshots saved before they were
  /// read.
  public var headRefName: String?
  public var baseRefName: String?
  /// The author's picture, and the PR's size: enough for its page to draw before the rest
  /// loads. Nil in snapshots saved before they were read.
  public var authorAvatar: URL?
  public var additions: Int?
  public var deletions: Int?
  public var changedFiles: Int?
  public var commitCount: Int?

  public init(
    id: String, number: Int, repository: String, title: String, url: URL, state: String = "OPEN",
    isDraft: Bool = false, reviewDecision: String? = nil, reviewRequested: Bool = false,
    mergeable: String = "UNKNOWN", mergeStateStatus: String = "UNKNOWN", checks: String? = nil,
    checkSummary: CheckSummary? = nil, headOID: String = "", autoMerge: Bool = false,
    queuePosition: Int? = nil, mergingSince: Date? = nil, queueChecks: CheckSummary? = nil,
    queueState: String? = nil, updatedAt: Date = Date(),
    mergedAt: Date? = nil, author: String? = nil, ownerAvatar: URL? = nil, createdAt: Date? = nil,
    previews: [PreviewDeploy]? = nil, headRefName: String? = nil, baseRefName: String? = nil,
    authorAvatar: URL? = nil, additions: Int? = nil, deletions: Int? = nil,
    changedFiles: Int? = nil, commitCount: Int? = nil
  ) {
    self.authorAvatar = authorAvatar
    self.additions = additions
    self.deletions = deletions
    self.changedFiles = changedFiles
    self.commitCount = commitCount
    self.headRefName = headRefName
    self.baseRefName = baseRefName
    self.createdAt = createdAt
    self.previews = previews
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
    self.queueChecks = queueChecks
    self.queueState = queueState
    self.updatedAt = updatedAt
    self.mergedAt = mergedAt
    self.author = author
    self.ownerAvatar = ownerAvatar
  }

  /// An open PR that is moving: checks running, set to merge, in the merge queue, or updated
  /// in the last 15 minutes (a push, review, or comment). Active PRs are refreshed often.
  public func isActive(at now: Date = Date()) -> Bool {
    guard state == "OPEN" else { return false }
    let checksRunning =
      checks == "PENDING" || checks == "EXPECTED" || (checkSummary?.pending ?? 0) > 0
    return checksRunning || autoMerge || queuePosition != nil
      || now.timeIntervalSince(updatedAt) < 15 * 60
  }

  /// In the merge queue, or set to merge automatically with nothing left to wait for. Set to
  /// merge while checks run or reviews are missing, a PR is still waiting, not merging.
  public var isMerging: Bool {
    guard state == "OPEN", !isDraft else { return false }
    if queuePosition != nil { return ![.conflicts, .changesRequested].contains(status) }
    return autoMerge && status == .ready
  }

  /// Set to merge when ready, but still waiting for checks or reviews.
  public var isWaitingToMerge: Bool { state == "OPEN" && autoMerge && !isMerging }

  /// The GitHub state this PR is in. Closed PRs are not shown.
  public var group: PRGroup? {
    switch state {
    case "MERGED": return .merged
    case "OPEN": break
    default: return nil
    }
    if isDraft { return .draft }
    if isMerging { return .merging }
    return .open
  }

  /// An open PR waiting on you: a review request, failed checks, conflicts, requested
  /// changes, or ready to merge. This flags a PR within its state; it is not a state.
  public var needsYou: Bool { group == .open && status.needsAttention }

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
  case open, merging, draft, merged

  public var label: String {
    switch self {
    case .merging: "Merging"
    case .open: "Open"
    case .draft: "Draft"
    case .merged: "Merged"
    }
  }
}

/// A time filter for activity. `days` counts today as the first day.
public enum ActivityWindow: String, CaseIterable, Codable, Sendable {
  case today, week, month

  public var label: String {
    switch self {
    case .today: "Today"
    case .week: "7 days"
    case .month: "30 days"
    }
  }

  public var days: Int {
    switch self {
    case .today: 1
    case .week: 7
    case .month: 30
    }
  }

  public func includes(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
    let start = calendar.date(
      byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))!
    return date >= start
  }
}

public struct PRSection: Identifiable, Equatable, Sendable {
  public var group: PRGroup
  public var pullRequests: [PullRequest]
  public var id: PRGroup { group }

  public init(group: PRGroup, pullRequests: [PullRequest]) {
    self.group = group
    self.pullRequests = pullRequests
  }
}

/// One repository's PRs, ordered by state as in `PRGroup` and then by activity.
public struct StateCount: Equatable, Sendable {
  public var group: PRGroup
  public var count: Int

  public init(group: PRGroup, count: Int) {
    self.group = group
    self.count = count
  }
}

public struct RepoSection: Identifiable, Equatable, Sendable {
  public var repository: String
  /// The PRs shown, after any state filter.
  public var pullRequests: [PullRequest]
  /// PRs that need you, before the state filter.
  public var needsYou: Int
  /// PR counts per state before the state filter, in display order, omitting empty states,
  /// so every state stays available to filter by.
  public var counts: [StateCount]
  public var id: String { repository }

  public init(
    repository: String, pullRequests: [PullRequest], counts: [StateCount]? = nil,
    needsYou: Int? = nil
  ) {
    self.repository = repository
    self.pullRequests = pullRequests
    self.needsYou = needsYou ?? pullRequests.count(where: \.needsYou)
    self.counts =
      counts
      ?? PRGroup.allCases.compactMap { group in
        let count = pullRequests.count { $0.group == group }
        return count > 0 ? StateCount(group: group, count: count) : nil
      }
  }

  public var owner: String { repository.split(separator: "/").first.map(String.init) ?? "" }
  public var name: String { repository.split(separator: "/").last.map(String.init) ?? repository }
  public var avatar: URL? { pullRequests.lazy.compactMap(\.ownerAvatar).first }

}

public enum PRGrouping {
  /// Repositories that need you come first, then those merging, then by latest activity.
  /// An empty `states` set shows every state; `needsYouOnly` keeps only PRs that need you.
  /// Repositories with nothing left are omitted; order and counts ignore the filters so
  /// they stay stable while filtering.
  public static func repositories(
    _ pullRequests: [PullRequest], window: ActivityWindow, states: Set<PRGroup> = [],
    needsYouOnly: Bool = false, now: Date = Date(), calendar: Calendar = .current
  ) -> [RepoSection] {
    var order: [String] = []
    var buckets: [String: [PullRequest]] = [:]
    for section in sections(pullRequests, window: window, now: now, calendar: calendar) {
      for pr in section.pullRequests {
        if buckets[pr.repository] == nil { order.append(pr.repository) }
        buckets[pr.repository, default: []].append(pr)
      }
    }
    // A stack reads bottom to top, together.
    for (repository, prs) in buckets { buckets[repository] = PRStacks.ordered(prs) }
    // Repositories that need you come first, then by their most advanced open work.
    func rank(_ prs: [PullRequest]) -> Int {
      if prs.contains(where: \.needsYou) { return 0 }
      return 1 + (PRGroup.allCases.firstIndex { group in prs.contains { $0.group == group } } ?? 99)
    }
    func latest(_ prs: [PullRequest]) -> Date {
      prs.map { $0.mergedAt ?? $0.updatedAt }.max() ?? .distantPast
    }
    let ordered = order.map { RepoSection(repository: $0, pullRequests: buckets[$0] ?? []) }
      .sorted { lhs, rhs in
        let (left, right) = (rank(lhs.pullRequests), rank(rhs.pullRequests))
        if left != right { return left < right }
        let (newer, older) = (latest(lhs.pullRequests), latest(rhs.pullRequests))
        if newer != older { return newer > older }
        return lhs.repository < rhs.repository
      }
    guard !states.isEmpty || needsYouOnly else { return ordered }
    return ordered.compactMap { section in
      let shown = section.pullRequests.filter { pr in
        // A closure, not `map(states.contains)`: release builds miscompile that method
        // reference and crash when a state filter is pressed.
        (states.isEmpty || (pr.group.map { states.contains($0) } ?? false))
          && (!needsYouOnly || pr.needsYou)
      }
      guard !shown.isEmpty else { return nil }
      return RepoSection(
        repository: section.repository, pullRequests: shown, counts: section.counts,
        needsYou: section.needsYou)
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
      case .open:
        // PRs waiting on you lead their column.
        rows.sort { lhs, rhs in
          lhs.needsYou != rhs.needsYou ? lhs.needsYou : lhs.updatedAt > rhs.updatedAt
        }
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
  /// More merged PRs exist in the last 30 days than were fetched; only the newest are kept.
  public var mergedLimited: Bool?
  /// When the full 30 days of merged PRs were last read. In between, refreshes read only
  /// recent merges and keep the rest.
  public var mergedSweptAt: Date?
  /// What the open-PR searches found, to compare the next one-point check against. Nil when a
  /// search found more than one check can see, or for snapshots saved before it existed.
  public var searchFingerprint: SearchFingerprint?

  public init(
    login: String, pullRequests: [PullRequest], fetchedAt: Date = Date(), selection: String = "",
    isLimited: Bool = false, mergedLimited: Bool = false, mergedSweptAt: Date? = nil,
    searchFingerprint: SearchFingerprint? = nil
  ) {
    self.searchFingerprint = searchFingerprint
    self.mergedLimited = mergedLimited
    self.mergedSweptAt = mergedSweptAt
    self.login = login
    self.pullRequests = pullRequests
    self.fetchedAt = fetchedAt
    self.selection = selection
    self.isLimited = isLimited
  }
}

/// What GitHub reports is left of the hourly GraphQL budget.
public struct RateBudget: Equatable, Sendable {
  public var remaining: Int
  public var resetAt: Date

  public init(remaining: Int, resetAt: Date) {
    self.remaining = remaining
    self.resetAt = resetAt
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
  public var dailyCost: [DailyValue]
  public var partial: Bool
  public var updatedAt: Date

  public init(
    provider: AgentProvider, days: Int, tokens: Int?, inputTokens: Int?, outputTokens: Int?,
    cachedTokens: Int?, cacheCreationTokens: Int?, estimatedCost: Double?, models: [UsageModel],
    daily: [DailyValue] = [], dailyCost: [DailyValue] = [], partial: Bool, updatedAt: Date
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
    self.dailyCost = dailyCost
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

/// A PR's preview deploy, one per project: the head commit's, or an earlier commit's when a
/// later push didn't touch that project.
public struct PreviewDeploy: Codable, Hashable, Sendable {
  public enum State: String, Codable, Sendable {
    case ready, building, failed
  }

  /// The project, such as "omnia-docs" from Vercel's "Preview – omnia-docs".
  public var name: String
  public var state: State
  /// Where the preview lives, once it's ready.
  public var url: URL?
  /// The commit it was built from; nil when not known.
  public var commit: String?

  public init(name: String, state: State, url: URL? = nil, commit: String? = nil) {
    self.name = name
    self.state = state
    self.url = url
    self.commit = commit
  }

  /// What one commit says about its previews: its deployments, and its commit statuses. Vercel
  /// reports a build only as a status ("Vercel – omnia-docs"); the deployment, with its link,
  /// appears once the build is done.
  public struct CommitSignals: Sendable {
    public var oid: String
    public var deployments: [(environment: String, state: String?, url: String?)]
    public var statuses: [(context: String, state: String, description: String?)]

    public init(
      oid: String, deployments: [(environment: String, state: String?, url: String?)] = [],
      statuses: [(context: String, state: String, description: String?)] = []
    ) {
      self.oid = oid
      self.deployments = deployments
      self.statuses = statuses
    }
  }

  /// Previews from a PR's latest commits, oldest first. Each project shows its newest state, so
  /// a commit that only retired a project's deploy, as Vercel does when a push doesn't touch it,
  /// keeps showing the earlier one.
  public static func from(commits: [CommitSignals]) -> [PreviewDeploy] {
    var latest: [String: PreviewDeploy] = [:]
    var order: [String] = []
    for commit in commits {
      let deployed = from(commit.deployments)
      var found = Dictionary(deployed.map { ($0.name, $0) }) { first, _ in first }
      var names = deployed.map(\.name)
      // A build in progress, or one that failed, says more than a deploy that finished before.
      for status in commit.statuses {
        guard let name = vercelProject(status.context) else { continue }
        let state: State? =
          switch status.state {
          case "PENDING", "EXPECTED": .building
          case "FAILURE", "ERROR": .failed
          default: nil
          }
        guard let state else { continue }
        if found[name] == nil { names.append(name) }
        found[name] = PreviewDeploy(name: name, state: state)
      }
      for name in names {
        guard var preview = found[name] else { continue }
        if latest[name] == nil { order.append(name) }
        preview.commit = commit.oid
        latest[name] = preview
      }
    }
    return order.compactMap { latest[$0] }
  }

  /// "omnia-docs" from Vercel's status context "Vercel – omnia-docs".
  static func vercelProject(_ context: String) -> String? {
    guard let match = context.firstMatch(of: /^Vercel\s*[–—-]\s*(.+)$/) else { return nil }
    return String(match.1)
  }

  /// Previews from GitHub's deployments for one commit: the newest per environment, without
  /// those replaced by a later deploy or retired after a merge. Production deploys are left out.
  public static func from(
    _ deployments: [(environment: String, state: String?, url: String?)]
  ) -> [PreviewDeploy] {
    var latest: [String: PreviewDeploy] = [:]
    var order: [String] = []
    for deployment in deployments {
      let environment = deployment.environment
      guard !environment.localizedCaseInsensitiveContains("production") else { continue }
      let state: State? =
        switch deployment.state {
        case "SUCCESS": .ready
        case "FAILURE", "ERROR": .failed
        case "PENDING", "QUEUED", "IN_PROGRESS", "WAITING": .building
        default: nil
        }
      let name = environment.replacingOccurrences(
        of: #"^Preview\s*[–—-]\s*"#, with: "", options: .regularExpression)
      if latest[name] == nil { order.append(name) }
      guard let state else {
        latest[name] = nil
        continue
      }
      let url = deployment.url.flatMap(URL.init(string:)).flatMap {
        $0.scheme == "https" ? $0 : nil
      }
      latest[name] = PreviewDeploy(name: name, state: state, url: state == .ready ? url : nil)
    }
    return order.compactMap { latest[$0] }
  }
}

extension PullRequest {
  /// Previews you can open now.
  public var readyPreviews: [PreviewDeploy] {
    (previews ?? []).filter { $0.state == .ready && $0.url != nil }
  }
}

public struct IslandEvent: Codable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var detail: String
  public var url: URL
  public var occurredAt: Date
  public var kind: PRStatus
  /// The PR's repository, as `owner/name`; nil in ledgers saved before it was recorded.
  public var repository: String?
  /// More about the change when it's known, such as the checks that failed.
  public var note: String?

  public init(
    id: String, title: String, detail: String, url: URL, occurredAt: Date, kind: PRStatus,
    repository: String? = nil
  ) {
    self.repository = repository
    self.id = id
    self.title = title
    self.detail = detail
    self.url = url
    self.occurredAt = occurredAt
    self.kind = kind
  }

}

public enum MergeTiming {
  /// Starts the merging clock for PRs set to merge without a merge queue, which GitHub doesn't
  /// time: from when GitIsle first saw them merging, kept while they stay merging.
  public static func stamped(_ current: GitHubSnapshot, previous: GitHubSnapshot?)
    -> GitHubSnapshot
  {
    let prior = Dictionary(
      (previous?.pullRequests ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var next = current
    for index in next.pullRequests.indices {
      let pr = next.pullRequests[index]
      guard pr.isMerging, pr.mergingSince == nil else { continue }
      let before = prior[pr.id]
      next.pullRequests[index].mergingSince =
        before?.isMerging == true ? (before?.mergingSince ?? current.fetchedAt) : current.fetchedAt
    }
    return next
  }
}

public enum GitHubChanges {
  public static func events(previous: GitHubSnapshot?, current: GitHubSnapshot) -> [IslandEvent] {
    guard let previous, previous.login == current.login, previous.selection == current.selection
    else { return [] }
    let old = Dictionary(
      previous.pullRequests.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    func event(_ pr: PullRequest, _ kind: PRStatus, _ occurrence: String, url: URL? = nil)
      -> IslandEvent
    {
      let label: String =
        switch kind {
        case .queued: "Merging"
        case .draft: "New draft PR"
        default: kind.label
        }
      return IslandEvent(
        id: "\(pr.id):\(kind.rawValue):\(occurrence)",
        title: "\(pr.repository) #\(pr.number) · \(label)", detail: pr.title, url: url ?? pr.url,
        occurredAt: current.fetchedAt, kind: kind, repository: pr.repository)
    }
    return current.pullRequests.flatMap { pr -> [IslandEvent] in
      // Only your own PRs announce opening, merging, or being ready; watched repositories would
      // be too noisy.
      let mine = pr.author == current.login
      guard let prior = old[pr.id] else {
        if pr.reviewRequested { return [event(pr, .review, pr.headOID)] }
        // A PR of yours first seen soon after it was opened; one that only showed up again,
        // such as a reopened PR, stays quiet. The slack covers search delays between refreshes.
        guard mine, pr.state == "OPEN", let created = pr.createdAt,
          created >= previous.fetchedAt.addingTimeInterval(-600)
        else { return [] }
        return [event(pr, pr.isDraft ? .draft : .opened, "created")]
      }
      let merged = prior.state == "OPEN" && pr.state == "MERGED"
      let failed = pr.status == .failed && (prior.status != .failed || prior.headOID != pr.headOID)
      let review = pr.reviewRequested && !prior.reviewRequested
      let merging = mine && pr.isMerging && !prior.isMerging
      // Left the merge queue without merging, as when its checks fail or a push removes it. An
      // entry that had passed may only be waiting for GitHub to mark the PR merged.
      let leftQueue =
        mine && prior.queuePosition != nil && pr.queuePosition == nil && pr.state == "OPEN"
        && !["MERGEABLE", "LOCKED"].contains(prior.queueState ?? "")
      // Once per commit, and not while or right after merging: "Merged" or "Merge failed" says
      // more.
      let ready =
        mine && pr.status == .ready && !pr.isMerging && !prior.isMerging
        && (prior.status != .ready || prior.headOID != pr.headOID)
      // Marking a draft ready can also make it ready to merge, so both can announce.
      let undrafted = mine && prior.isDraft && !pr.isDraft && pr.state == "OPEN"
      var events = undrafted ? [event(pr, .readyForReview, pr.headOID)] : []
      // A preview of your PR that became ready on this commit. Previews GitIsle reads for the
      // first time stay quiet, so updating or relaunching never replays them.
      if mine, pr.state == "OPEN", prior.previews != nil {
        // An earlier commit's preview, still showing after a push, isn't new.
        func key(_ preview: PreviewDeploy, _ head: String) -> String {
          "\(preview.name)@\(preview.commit ?? head)"
        }
        let before = Set(prior.readyPreviews.map { key($0, prior.headOID) })
        let fresh = pr.readyPreviews.filter {
          ($0.commit ?? pr.headOID) == pr.headOID && !before.contains(key($0, pr.headOID))
        }
        if let first = fresh.first {
          var ready = event(pr, .previewReady, pr.headOID, url: first.url)
          ready.note = fresh.map(\.name).joined(separator: ", ")
          events.append(ready)
        }
      }
      if leftQueue {
        // Once per time in the queue.
        let entered = prior.mergingSince ?? prior.updatedAt
        events.append(event(pr, .mergeFailed, entered.timeIntervalSince1970.description))
      }
      guard merged || failed || review || merging || ready else { return events }
      let kind: PRStatus =
        merged ? .merged : failed ? .failed : review ? .review : merging ? .queued : .ready
      // Each time a PR starts merging is its own occurrence, so merging it again after a
      // failure announces again.
      let occurrence =
        merged
        ? (pr.mergedAt ?? pr.updatedAt).timeIntervalSince1970.description
        : kind == .queued
          ? (pr.mergingSince ?? current.fetchedAt).timeIntervalSince1970.description
          : pr.headOID
      events.append(event(pr, kind, occurrence))
      return events
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
