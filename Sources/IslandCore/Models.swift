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

public struct PullRequest: Codable, Hashable, Identifiable, Sendable {
  public var id: String
  public var number: Int
  public var repository: String
  public var title: String
  public var url: URL
  public var state: String
  public var isDraft: Bool
  public var reviewDecision: String?
  public var reviewRequested: Bool
  public var mergeable: String
  public var mergeStateStatus: String
  public var checks: String?
  public var headOID: String
  public var autoMerge: Bool
  public var queuePosition: Int?
  public var updatedAt: Date
  public var mergedAt: Date?

  public init(
    id: String, number: Int, repository: String, title: String, url: URL, state: String = "OPEN",
    isDraft: Bool = false, reviewDecision: String? = nil, reviewRequested: Bool = false,
    mergeable: String = "UNKNOWN", mergeStateStatus: String = "UNKNOWN", checks: String? = nil,
    headOID: String = "", autoMerge: Bool = false, queuePosition: Int? = nil,
    updatedAt: Date = Date(), mergedAt: Date? = nil
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
    self.headOID = headOID
    self.autoMerge = autoMerge
    self.queuePosition = queuePosition
    self.updatedAt = updatedAt
    self.mergedAt = mergedAt
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

public enum ActivityPhase: String, Codable, Sendable {
  case working, waiting, finished, interrupted, unknown
  public var label: String { rawValue.capitalized }
}

public struct AgentSession: Codable, Identifiable, Sendable {
  public var id: String
  public var provider: AgentProvider
  public var source: String
  public var directory: String
  public var branch: String?
  public var model: String?
  public var phase: ActivityPhase
  public var activity: String
  public var updatedAt: Date

  public init(
    id: String, provider: AgentProvider, source: String, directory: String, branch: String? = nil,
    model: String? = nil, phase: ActivityPhase, activity: String, updatedAt: Date
  ) {
    self.id = id
    self.provider = provider
    self.source = source
    self.directory = directory
    self.branch = branch
    self.model = model
    self.phase = phase
    self.activity = activity
    self.updatedAt = updatedAt
  }

  public var project: String { URL(fileURLWithPath: directory).lastPathComponent }
  public var isActive: Bool { phase == .working || phase == .waiting }
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
  public var partial: Bool
  public var updatedAt: Date

  public init(
    provider: AgentProvider, days: Int, tokens: Int?, inputTokens: Int?, outputTokens: Int?,
    cachedTokens: Int?, cacheCreationTokens: Int?, estimatedCost: Double?, models: [UsageModel],
    partial: Bool, updatedAt: Date
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
    self.partial = partial
    self.updatedAt = updatedAt
  }
}

public struct IslandEvent: Codable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var detail: String
  public var url: URL
  public var occurredAt: Date
  public var kind: PRStatus
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
      guard merged || failed || review else { return nil }
      let kind: PRStatus = merged ? .merged : failed ? .failed : .review
      let occurrence =
        merged ? (pr.mergedAt ?? pr.updatedAt).timeIntervalSince1970.description : pr.headOID
      return IslandEvent(
        id: "\(pr.id):\(kind.rawValue):\(occurrence)",
        title: "\(pr.repository) #\(pr.number) · \(kind.label)", detail: pr.title,
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
