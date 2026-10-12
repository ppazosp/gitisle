import Foundation

public actor GitHubService {
  private static let fields = """
    fragment PRFields on PullRequest {
      id number title url state isDraft updatedAt mergedAt mergeable mergeStateStatus reviewDecision
      headRefOid autoMergeRequest { enabledAt } mergeQueueEntry { position enqueuedAt }
      repository { nameWithOwner owner { avatarUrl(size: 64) } } author { login }
      commits(last: 1) { nodes { commit { statusCheckRollup {
        state
        contexts(first: 0) {
          checkRunCountsByState { state count }
          statusContextCountsByState { state count }
        }
      } } } }
    }
    """

  private let transport: (@Sendable (Data) async throws -> Data)?
  /// The GraphQL budget GitHub reported with the last response, for pacing refreshes.
  public private(set) var budget: RateBudget?

  public init(transport: (@Sendable (Data) async throws -> Data)? = nil) {
    self.transport = transport
  }

  public func fetch(selection: RepositorySelection, previous: GitHubSnapshot?) async throws
    -> GitHubSnapshot
  {
    let query = """
      query($search: String!, $after: String) {
        viewer { login }
        rateLimit { remaining resetAt }
        search(query: $search, type: ISSUE, first: 100, after: $after) {
          nodes { ...PRFields }
          pageInfo { hasNextPage endCursor }
        }
      }
      \(Self.fields)
      """
    // Merged history covers the longest activity window, 30 days. It rarely changes, so between
    // daily full sweeps only merges since the day before the last refresh are read.
    let now = Date()
    let sameAccount = previous.map { $0.selection == selection.fingerprint } ?? false
    let sweptAt = sameAccount ? previous?.mergedSweptAt : nil
    let incremental = sweptAt.map { now.timeIntervalSince($0) < 86_400 } ?? false
    let mergedFrom =
      incremental
      ? (previous?.fetchedAt ?? now).addingTimeInterval(-86_400)
      : now.addingTimeInterval(-30 * 86_400)
    let since = mergedFrom.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    var groups = [
      ("mine", "is:pr is:open author:@me"),
      ("reviews", "is:pr is:open review-requested:@me"),
      ("merged", "is:pr is:merged author:@me merged:>=\(since) sort:updated-desc"),
    ]
    if !selection.repositories.isEmpty {
      groups.append(("repos", "is:pr is:open \(selection.searchQuery)"))
    }
    var login = ""
    var prs: [String: PullRequest] = [:]
    var limited = false
    var mergedLimited = false
    for (name, search) in groups {
      var cursor: String?
      var seenCursors = Set<String>()
      for page in 0..<4 {
        var variables: [String: Any] = ["search": search]
        if let cursor { variables["after"] = cursor }
        let response = try await request(query: query, variables: variables)
        guard let data = response["data"] as? [String: Any],
          let viewer = data["viewer"] as? [String: Any],
          let currentLogin = viewer["login"] as? String,
          let result = data["search"] as? [String: Any],
          let nodes = result["nodes"] as? [[String: Any]],
          let info = result["pageInfo"] as? [String: Any], let more = info["hasNextPage"] as? Bool
        else {
          throw ProcessFailure.failed("GitHub returned an incomplete pull request list.")
        }
        guard login.isEmpty || login == currentLogin else {
          throw ProcessFailure.failed("The GitHub account changed during refresh. Refresh again.")
        }
        login = currentLogin
        for node in nodes {
          var pr = try Self.decode(node)
          pr.reviewRequested = name == "reviews" || prs[pr.id]?.reviewRequested == true
          prs[pr.id] = pr
        }
        guard more else { break }
        if page == 3 {
          // Merged PRs are sorted newest first, so a cap keeps the most recent ones;
          // that is history, not missing open work.
          if name == "merged" { mergedLimited = true } else { limited = true }
          break
        }
        guard let next = info["endCursor"] as? String, seenCursors.insert(next).inserted else {
          throw ProcessFailure.failed("GitHub returned an invalid pagination cursor.")
        }
        cursor = next
      }
    }
    // PRs disappearing from open search may be merged, closed, or no longer searchable.
    // Read their identities explicitly; disappearance alone never means "merged".
    if let previous, previous.login == login, previous.selection == selection.fingerprint {
      let missing = previous.pullRequests.filter { $0.state == "OPEN" && prs[$0.id] == nil }
      for chunk in stride(from: 0, to: missing.count, by: 25) {
        let ids = Array(missing[chunk..<min(chunk + 25, missing.count)]).map(\.id)
        let extra = try await request(
          query:
            "query($ids: [ID!]!) { viewer { login } nodes(ids: $ids) { ...PRFields } }\n\(Self.fields)",
          variables: ["ids": ids])
        guard let extraData = extra["data"] as? [String: Any],
          (extraData["viewer"] as? [String: Any])?["login"] as? String == login,
          let nodes = extraData["nodes"] as? [Any]
        else {
          throw ProcessFailure.failed("GitHub could not verify recently changed PRs.")
        }
        for node in nodes {
          guard let value = node as? [String: Any] else { continue }
          let pr = try Self.decode(value)
          prs[pr.id] = pr
        }
      }
      // Keep history from the same day the full sweep starts at, so a PR merged just over
      // 30 days ago doesn't drop out between sweeps and come back.
      let format = Date.ISO8601FormatStyle().year().month().day().dateSeparator(.dash)
      let monthAgo = now.addingTimeInterval(-30 * 86_400)
      let monthStart = (try? Date(monthAgo.formatted(format), strategy: format)) ?? monthAgo
      for pr in previous.pullRequests where pr.state != "OPEN" && prs[pr.id] == nil {
        if (pr.mergedAt ?? pr.updatedAt) >= monthStart { prs[pr.id] = pr }
      }
    }
    return GitHubSnapshot(
      login: login, pullRequests: prs.values.sorted { $0.updatedAt > $1.updatedAt },
      selection: selection.fingerprint, isLimited: limited,
      mergedLimited: incremental
        ? (previous?.mergedLimited ?? false) || mergedLimited : mergedLimited,
      // A different account behind gh needs its own full sweep next time.
      mergedSweptAt: incremental ? (previous?.login == login ? sweptAt : nil) : now)
  }

  /// Re-reads known PRs by ID: one cheap request per 100 PRs, and no search index delay.
  /// PRs GitHub can no longer resolve (deleted, or access lost) are left out.
  public func pullRequests(ids: [String], login: String) async throws -> [PullRequest] {
    var result: [PullRequest] = []
    for chunk in stride(from: 0, to: ids.count, by: 100) {
      let batch = Array(ids[chunk..<min(chunk + 100, ids.count)])
      let response = try await request(
        query: """
          query($ids: [ID!]!) { viewer { login } rateLimit { remaining resetAt }
            nodes(ids: $ids) { ...PRFields } }
          \(Self.fields)
          """,
        variables: ["ids": batch], allowMissingNodes: true)
      guard let data = response["data"] as? [String: Any],
        (data["viewer"] as? [String: Any])?["login"] as? String == login,
        let nodes = data["nodes"] as? [Any]
      else { throw ProcessFailure.failed("GitHub could not refresh the active PRs.") }
      for case let node as [String: Any] in nodes { result.append(try Self.decode(node)) }
    }
    return result
  }

  private func request(
    query: String, variables: [String: Any], allowMissingNodes: Bool = false
  ) async throws -> [String: Any] {
    let body = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
    let output: Data
    if let transport {
      output = try await transport(body)
    } else {
      guard let gh = ProcessRunner.executable("gh") else {
        throw ProcessFailure.unavailable("GitHub CLI (gh)")
      }
      output = try await ProcessRunner.run(
        gh, arguments: ["api", "graphql", "--input", "-"], input: body)
    }
    guard let json = try JSONSerialization.jsonObject(with: output) as? [String: Any] else {
      throw ProcessFailure.failed("GitHub returned an unreadable response.")
    }
    if let limit = (json["data"] as? [String: Any])?["rateLimit"] as? [String: Any],
      let remaining = limit["remaining"] as? Int,
      let reset = (limit["resetAt"] as? String).flatMap(Dates.parse)
    {
      budget = RateBudget(remaining: remaining, resetAt: reset)
    }
    var errors = json["errors"] as? [[String: Any]] ?? []
    // A deleted PR or lost access shows up as a missing node; the rest of the batch is fine.
    if allowMissingNodes { errors.removeAll { $0["type"] as? String == "NOT_FOUND" } }
    if !errors.isEmpty {
      throw ProcessFailure.failed(
        errors.compactMap { $0["message"] as? String }.joined(separator: "\n"))
    }
    return json
  }

  public static func decode(_ row: [String: Any]) throws -> PullRequest {
    guard let id = row["id"] as? String, let number = row["number"] as? Int,
      let title = row["title"] as? String, let link = row["url"] as? String,
      let url = URL(string: link), url.scheme == "https", url.host == "github.com",
      let repo = (row["repository"] as? [String: Any])?["nameWithOwner"] as? String,
      let state = row["state"] as? String, let updated = row["updatedAt"] as? String,
      let updatedAt = Dates.parse(updated)
    else {
      throw ProcessFailure.failed(
        "GitHub returned an incomplete PR. Keeping the previous snapshot.")
    }
    let commits = (row["commits"] as? [String: Any])?["nodes"] as? [[String: Any]]
    let commit = commits?.last?["commit"] as? [String: Any]
    let rollup = commit?["statusCheckRollup"] as? [String: Any]
    let contexts = rollup?["contexts"] as? [String: Any]
    let counts = ["checkRunCountsByState", "statusContextCountsByState"].flatMap { key in
      (contexts?[key] as? [[String: Any]] ?? []).compactMap { entry -> (String, Int)? in
        guard let state = entry["state"] as? String, let count = entry["count"] as? Int else {
          return nil
        }
        return (state, count)
      }
    }
    let summary = CheckSummary(counts: counts)
    let queue = row["mergeQueueEntry"] as? [String: Any]
    let autoMerge = row["autoMergeRequest"] as? [String: Any]
    let mergingSince = ((queue?["enqueuedAt"] ?? autoMerge?["enabledAt"]) as? String)
      .flatMap(Dates.parse)
    return PullRequest(
      id: id, number: number, repository: repo, title: title, url: url, state: state,
      isDraft: row["isDraft"] as? Bool ?? false, reviewDecision: row["reviewDecision"] as? String,
      mergeable: row["mergeable"] as? String ?? "UNKNOWN",
      mergeStateStatus: row["mergeStateStatus"] as? String ?? "UNKNOWN",
      checks: rollup?["state"] as? String, checkSummary: summary.total > 0 ? summary : nil,
      headOID: row["headRefOid"] as? String ?? "",
      autoMerge: autoMerge != nil,
      queuePosition: queue?["position"] as? Int, mergingSince: mergingSince,
      updatedAt: updatedAt, mergedAt: (row["mergedAt"] as? String).flatMap(Dates.parse),
      author: (row["author"] as? [String: Any])?["login"] as? String,
      ownerAvatar: avatar(row["repository"]))
  }

  /// Only GitHub's own avatar host is accepted, so a response cannot point the app elsewhere.
  static func avatar(_ repository: Any?) -> URL? {
    let owner = (repository as? [String: Any])?["owner"] as? [String: Any]
    guard let link = owner?["avatarUrl"] as? String, let url = URL(string: link),
      url.scheme == "https", url.host == "avatars.githubusercontent.com"
    else { return nil }
    return url
  }

  /// Personal PR counts for today, 7 days, and 30 days, plus daily contributions.
  /// Search counts include organizations that the contribution graph may hide.
  public func stats(now: Date = Date(), calendar: Calendar = .current) async throws -> GitHubStats {
    let windows = [1, 7, 30]
    var variables: [String: Any] = [:]
    var fields: [String] = []
    var declarations = ["$from: DateTime!", "$to: DateTime!"]
    let today = calendar.startOfDay(for: now)
    for days in windows {
      let start = calendar.date(byAdding: .day, value: -(days - 1), to: today)!
      let since = start.formatted(.iso8601)
      let searches = [
        ("opened", "is:pr author:@me created:>=\(since)"),
        ("merged", "is:pr author:@me is:merged merged:>=\(since)"),
        ("reviewed", "is:pr reviewed-by:@me -author:@me updated:>=\(since)"),
      ]
      for (name, search) in searches {
        let key = "\(name)\(days)"
        variables[key] = search
        declarations.append("$\(key): String!")
        fields.append("\(key): search(query: $\(key), type: ISSUE, first: 0) { issueCount }")
      }
    }
    let first = calendar.date(byAdding: .day, value: -29, to: today)!
    variables["from"] = first.formatted(.iso8601)
    variables["to"] = now.formatted(.iso8601)
    let query = """
      query(\(declarations.joined(separator: ", "))) {
        viewer { login contributionsCollection(from: $from, to: $to) {
          contributionCalendar { weeks { contributionDays { date contributionCount } } }
        } }
        \(fields.joined(separator: "\n  "))
      }
      """
    let response = try await request(query: query, variables: variables)
    guard let data = response["data"] as? [String: Any],
      let viewer = data["viewer"] as? [String: Any], let login = viewer["login"] as? String
    else { throw ProcessFailure.failed("GitHub returned incomplete statistics.") }
    func count(_ key: String) throws -> Int {
      guard let value = (data[key] as? [String: Any])?["issueCount"] as? Int else {
        throw ProcessFailure.failed("GitHub returned incomplete statistics.")
      }
      return value
    }
    let results = try windows.map { days in
      GitHubStats.Window(
        days: days, opened: try count("opened\(days)"), merged: try count("merged\(days)"),
        reviewed: try count("reviewed\(days)"))
    }
    let collection = viewer["contributionsCollection"] as? [String: Any]
    let weeks =
      (collection?["contributionCalendar"] as? [String: Any])?["weeks"] as? [[String: Any]] ?? []
    let daily = weeks.flatMap { $0["contributionDays"] as? [[String: Any]] ?? [] }
      .compactMap { day -> DailyValue? in
        guard let date = day["date"] as? String, let count = day["contributionCount"] as? Int
        else { return nil }
        return DailyValue(day: date, value: Double(count))
      }
    return GitHubStats(login: login, windows: results, daily: daily, fetchedAt: now)
  }
}

public enum Dates {
  public static func parse(_ value: String) -> Date? {
    (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value))
      ?? (try? Date.ISO8601FormatStyle().parse(value))
  }
}
