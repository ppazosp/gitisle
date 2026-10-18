import Foundation

/// Everything the PR page shows, read on demand: who opened it and who's reviewing, the files
/// it changes, and every check on the head commit.
public struct PullRequestDetails: Equatable, Sendable {
  public struct FileChange: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
      case added, modified, removed, renamed
    }

    public var path: String
    public var additions: Int
    public var deletions: Int
    public var kind: Kind

    public init(path: String, additions: Int, deletions: Int, kind: Kind = .modified) {
      self.path = path
      self.additions = additions
      self.deletions = deletions
      self.kind = kind
    }

    /// GitHub's change type: ADDED, DELETED, RENAMED, COPIED, MODIFIED, or CHANGED.
    public static func kind(_ changeType: String?) -> Kind {
      switch changeType {
      case "ADDED", "COPIED": .added
      case "DELETED": .removed
      case "RENAMED": .renamed
      default: .modified
      }
    }

    /// The file's name, after its folder.
    public var name: String { path.split(separator: "/").last.map(String.init) ?? path }
  }

  /// Someone asked to review, or who has: a person, a team, or a bot.
  public struct Reviewer: Equatable, Sendable {
    public var name: String
    public var avatar: URL?

    public init(name: String, avatar: URL? = nil) {
      self.name = name
      self.avatar = avatar
    }
  }

  public struct Review: Equatable, Sendable {
    public var author: String
    public var avatar: URL?
    /// GitHub's review state: APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED, or PENDING.
    public var state: String
    public var submittedAt: Date?

    public init(author: String, avatar: URL? = nil, state: String, submittedAt: Date?) {
      self.author = author
      self.avatar = avatar
      self.state = state
      self.submittedAt = submittedAt
    }
  }

  public var id: String
  public var author: String?
  public var authorAvatar: URL?
  public var baseRefName: String
  public var headRefName: String
  public var createdAt: Date?
  public var additions: Int
  public var deletions: Int
  public var changedFiles: Int
  public var files: [FileChange]
  public var commitCount: Int
  /// People and teams asked for a review who haven't given one yet.
  public var requestedReviewers: [Reviewer]
  /// Each reviewer's latest review.
  public var reviews: [Review]
  public var commentCount: Int
  public var checks: [Check]
  /// Preview deploys of the head commit.
  public var previews: [PreviewDeploy]
  public var fetchedAt: Date

  public init(
    id: String, author: String? = nil, authorAvatar: URL? = nil, baseRefName: String = "",
    headRefName: String = "", createdAt: Date? = nil, additions: Int = 0, deletions: Int = 0,
    changedFiles: Int = 0, files: [FileChange] = [], commitCount: Int = 0,
    requestedReviewers: [Reviewer] = [], reviews: [Review] = [], commentCount: Int = 0,
    checks: [Check] = [], previews: [PreviewDeploy] = [], fetchedAt: Date = Date()
  ) {
    self.previews = previews
    self.id = id
    self.author = author
    self.authorAvatar = authorAvatar
    self.baseRefName = baseRefName
    self.headRefName = headRefName
    self.createdAt = createdAt
    self.additions = additions
    self.deletions = deletions
    self.changedFiles = changedFiles
    self.files = files
    self.commitCount = commitCount
    self.requestedReviewers = requestedReviewers
    self.reviews = reviews
    self.commentCount = commentCount
    self.checks = checks
    self.fetchedAt = fetchedAt
  }

  /// Failed checks first: real failures with errors to read, then those without, then checks
  /// that only sum up the others. Running checks follow, then everything else.
  public var sortedChecks: [Check] {
    func rank(_ check: Check) -> Int {
      guard check.outcome == .failed else { return 10 + check.outcome.order }
      return check.isSummary ? 2 : check.errors.isEmpty ? 1 : 0
    }
    return checks.enumerated().sorted { left, right in
      let (a, b) = (rank(left.element), rank(right.element))
      return a != b ? a < b : left.offset < right.offset
    }
    .map(\.element)
  }

  /// "unit, typecheck", or "unit, typecheck +2", for a banner about the failure.
  public var failureNote: String? {
    let names = failingChecks.map(\.shortTitle)
    guard !names.isEmpty else { return nil }
    let shown = names.prefix(2).joined(separator: ", ")
    return names.count > 2 ? "\(shown) +\(names.count - 2)" : shown
  }

  /// The failed checks worth naming, without those that only sum up the others.
  public var failingChecks: [Check] {
    let failed = sortedChecks.filter { $0.outcome == .failed }
    let real = failed.filter { !$0.isSummary }
    return real.isEmpty ? failed : real
  }
}

/// One check on a PR's head commit: a GitHub Actions job or other check run, or a commit
/// status such as Vercel's.
public struct Check: Equatable, Sendable, Identifiable {
  public enum Outcome: Equatable, Sendable {
    case failed, running, passed, skipped

    var order: Int {
      switch self {
      case .failed: 0
      case .running: 1
      case .passed: 2
      case .skipped: 3
      }
    }
  }

  /// A line the check reported against the code, such as a failing test or a type error.
  public struct Annotation: Equatable, Sendable {
    public var path: String
    public var line: Int?
    public var message: String

    public init(path: String, line: Int?, message: String) {
      self.path = path
      self.line = line
      self.message = message
    }

    /// "conformance.ts:24", or the file alone without a line. Nil for errors a runner logged
    /// against the workflow itself, whose line numbers point into the log.
    public var location: String? {
      guard path != ".github", !path.isEmpty else { return nil }
      let file = path.split(separator: "/").last.map(String.init) ?? path
      return line.map { "\(file):\($0)" } ?? file
    }

    /// The message's first line; stack traces follow it.
    public var headline: String {
      message.split(whereSeparator: \.isNewline).first.map(String.init) ?? message
    }
  }

  public var name: String
  /// The workflow a job belongs to, such as "CI"; nil for other checks and statuses.
  public var workflow: String?
  public var outcome: Outcome
  public var startedAt: Date?
  public var completedAt: Date?
  /// Where the check's log or details live.
  public var url: URL?
  /// A status's own explanation, such as Vercel's "Deployment has failed".
  public var summary: String?
  /// The errors worth reading, without runner noise.
  public var errors: [Annotation]

  public var id: String { "\(workflow ?? "")/\(name)" }

  /// "CI / unit", or the name alone outside a workflow. Reusable workflows name a job
  /// "unit / unit"; the repeat is dropped.
  public var title: String {
    var parts = ([workflow].compactMap { $0 } + name.components(separatedBy: " / "))
    parts = parts.enumerated().filter { $0.offset == 0 || parts[$0.offset - 1] != $0.element }
      .map(\.element)
    return parts.joined(separator: " / ")
  }

  /// A check that fails because others did, such as "All required checks pass" or "CI Success",
  /// which teams add so branch protection needs only one.
  public var isSummary: Bool {
    if errors.contains(where: {
      $0.message.range(of: #"^\d+ job\(s\) failed"#, options: .regularExpression) != nil
    }) {
      return true
    }
    return name.range(
      of:
        #"^(ci (success|passed)|all (required )?(checks|jobs) (pass|passed|succeeded)|required checks)$"#,
      options: [.regularExpression, .caseInsensitive]) != nil
  }

  /// The job's own name, such as "unit", for a banner.
  public var shortTitle: String { title.components(separatedBy: " / ").last ?? name }

  public var duration: TimeInterval? {
    guard let startedAt, let completedAt else { return nil }
    return max(0, completedAt.timeIntervalSince(startedAt))
  }

  public init(
    name: String, workflow: String? = nil, outcome: Outcome, startedAt: Date? = nil,
    completedAt: Date? = nil, url: URL? = nil, summary: String? = nil, errors: [Annotation] = []
  ) {
    self.name = name
    self.workflow = workflow
    self.outcome = outcome
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.url = url
    self.summary = summary
    self.errors = errors
  }

  /// A check run's outcome from its status and conclusion.
  public static func outcome(status: String?, conclusion: String?) -> Outcome {
    switch conclusion {
    case "FAILURE", "TIMED_OUT", "STARTUP_FAILURE", "ACTION_REQUIRED", "CANCELLED": return .failed
    case "SUCCESS": return .passed
    case "SKIPPED", "NEUTRAL", "STALE": return .skipped
    default: return status == "COMPLETED" ? .skipped : .running
    }
  }

  /// A commit status's outcome from its state.
  public static func outcome(state: String?) -> Outcome {
    switch state {
    case "FAILURE", "ERROR": .failed
    case "SUCCESS": .passed
    default: .running
    }
  }

  /// Keeps the annotations a person would read. Runners add "Process completed with exit code
  /// 1" against the workflow file, and notices about runner images, to every failure.
  public static func errors(
    _ annotations: [(level: String, path: String, line: Int?, message: String)]
  )
    -> [Annotation]
  {
    var seen = Set<String>()
    return annotations.compactMap { annotation in
      guard annotation.level == "FAILURE" || annotation.level == "WARNING" else { return nil }
      let message = annotation.message.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !message.isEmpty,
        !(annotation.path == ".github"
          && message.range(
            of: #"^Process completed with exit code \d+\.?$"#, options: .regularExpression)
            != nil)
      else { return nil }
      // Matrix jobs repeat the same error once per job.
      guard seen.insert("\(annotation.path):\(annotation.line ?? 0):\(message)").inserted else {
        return nil
      }
      return Annotation(path: annotation.path, line: annotation.line, message: message)
    }
  }
}
