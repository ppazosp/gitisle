import Foundation

public actor GitHubService {
  private static let fields = fields(previews: false)
  /// Reads by ID also read preview deploys; searches don't, since they'd cost a point per page.
  private static let fieldsWithPreviews = fields(previews: true)

  private static func fields(previews: Bool) -> String {
    """
    fragment PRFields on PullRequest {
      id number title url state isDraft createdAt updatedAt mergedAt mergeable mergeStateStatus
      reviewDecision
      headRefOid autoMergeRequest { enabledAt } mergeQueueEntry { position enqueuedAt }
      repository { nameWithOwner owner { avatarUrl(size: 64) } } author { login }
      commits(last: 1) { nodes { commit { statusCheckRollup {
        state
        contexts(first: 0) {
          checkRunCountsByState { state count }
          statusContextCountsByState { state count }
        }
      } \(previews ? deployments : "") } } }
    }
    """
  }

  private static let deployments =
    "deployments(last: 10) { nodes { environment latestStatus { state environmentUrl } } }"

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
        search(query: $search, type: ISSUE, first: \(Self.searchPage), after: $after) {
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
    let groups =
      Self.openSearches(selection)
      + [("merged", "is:pr is:merged author:@me merged:>=\(since) sort:updated-desc")]
    var login = ""
    var prs: [String: PullRequest] = [:]
    var limited = false
    var mergedLimited = false
    var fingerprint: SearchFingerprint? = SearchFingerprint()
    for (name, search) in groups {
      var cursor: String?
      var seenCursors = Set<String>()
      var found = 0
      for page in 0..<Self.searchPages {
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
          if name != "merged", let updatedAt = node["updatedAt"] as? String {
            fingerprint?.add(id: pr.id, updatedAt: updatedAt, search: name)
          }
        }
        found += nodes.count
        // The one-point check sees one page per search; past that it can't stand in for this.
        if name != "merged", found > SearchFingerprint.pageSize { fingerprint = nil }
        guard more else { break }
        if page == Self.searchPages - 1 {
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
    // Searches don't read previews; keep those read for the same commit.
    if let previous, previous.login == login {
      let known = Dictionary(previous.pullRequests.map { ($0.id, $0) }) { first, _ in first }
      for (id, pr) in prs where pr.previews == nil {
        if let prior = known[id], prior.headOID == pr.headOID { prs[id]?.previews = prior.previews }
      }
    }
    return GitHubSnapshot(
      login: login, pullRequests: prs.values.sorted { $0.updatedAt > $1.updatedAt },
      selection: selection.fingerprint, isLimited: limited,
      mergedLimited: incremental
        ? (previous?.mergedLimited ?? false) || mergedLimited : mergedLimited,
      // A different account behind gh needs its own full sweep next time.
      mergedSweptAt: incremental ? (previous?.login == login ? sweptAt : nil) : now,
      searchFingerprint: fingerprint)
  }

  /// Search pages of 50 cost one point each where 100 cost two, and most searches fit in one.
  /// Eight pages keep the cap at 400 PRs a search.
  static let searchPage = 50
  static let searchPages = 8

  /// The searches for open PRs: yours, those waiting on your review, and watched repositories.
  static func openSearches(_ selection: RepositorySelection) -> [(String, String)] {
    var searches = [
      ("mine", "is:pr is:open author:@me"),
      ("reviews", "is:pr is:open review-requested:@me"),
    ]
    if !selection.repositories.isEmpty {
      searches.append(("repos", "is:pr is:open \(selection.searchQuery)"))
    }
    return searches
  }

  /// What the open-PR searches find now, for one point: each PR's ID and last update. Nil
  /// when a search finds more PRs than one check can see, so only a full refresh will do.
  public func searchFingerprint(selection: RepositorySelection) async throws
    -> (login: String, fingerprint: SearchFingerprint)?
  {
    let searches = Self.openSearches(selection)
    let declarations = searches.indices.map { "$q\($0): String!" }.joined(separator: ", ")
    let fields = searches.indices.map {
      """
      s\($0): search(query: $q\($0), type: ISSUE, first: \(SearchFingerprint.pageSize)) {
        issueCount nodes { ... on PullRequest { id updatedAt } } }
      """
    }
    let query = """
      query(\(declarations)) {
        viewer { login }
        rateLimit { remaining resetAt }
        \(fields.joined(separator: "\n"))
      }
      """
    var variables: [String: Any] = [:]
    for (index, search) in searches.enumerated() { variables["q\(index)"] = search.1 }
    let response = try await request(query: query, variables: variables)
    guard let data = response["data"] as? [String: Any],
      let login = (data["viewer"] as? [String: Any])?["login"] as? String
    else { throw ProcessFailure.failed("GitHub returned an incomplete pull request check.") }
    var fingerprint = SearchFingerprint()
    for (index, search) in searches.enumerated() {
      guard let result = data["s\(index)"] as? [String: Any],
        let count = result["issueCount"] as? Int,
        let nodes = result["nodes"] as? [[String: Any]]
      else { throw ProcessFailure.failed("GitHub returned an incomplete pull request check.") }
      guard count <= SearchFingerprint.pageSize else { return nil }
      for node in nodes {
        guard let id = node["id"] as? String, let updatedAt = node["updatedAt"] as? String
        else { throw ProcessFailure.failed("GitHub returned an incomplete pull request check.") }
        fingerprint.add(id: id, updatedAt: updatedAt, search: search.0)
      }
    }
    return (login, fingerprint)
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
          \(Self.fieldsWithPreviews)
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
      ownerAvatar: avatar(row["repository"]),
      createdAt: (row["createdAt"] as? String).flatMap(Dates.parse),
      previews: (commit?["deployments"] as? [String: Any]).map(previews))
  }

  /// Previews from a commit's `deployments` connection.
  static func previews(_ connection: [String: Any]) -> [PreviewDeploy] {
    let nodes = connection["nodes"] as? [[String: Any]] ?? []
    return PreviewDeploy.from(
      nodes.compactMap { node in
        guard let environment = node["environment"] as? String else { return nil }
        let status = node["latestStatus"] as? [String: Any]
        return (environment, status?["state"] as? String, status?["environmentUrl"] as? String)
      })
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

extension GitHubService {
  /// What the PR page shows, for about one point: description, reviews, files, the latest
  /// comments, and every check with its errors. Read when the page opens and while it stays open.
  public func details(of pr: PullRequest) async throws -> PullRequestDetails {
    let query = """
      query($id: ID!) {
        rateLimit { remaining resetAt }
        node(id: $id) { ... on PullRequest {
          id body author { login } baseRefName headRefName createdAt additions deletions changedFiles
          files(first: 100) { nodes { path additions deletions } }
          reviewRequests(first: 10) { nodes { requestedReviewer {
            ... on User { login } ... on Team { name } ... on Bot { login } } } }
          latestReviews(first: 10) { nodes { author { login } state submittedAt } }
          comments(last: 5) { totalCount nodes { author { login } bodyText createdAt } }
          commits(last: 1) { totalCount nodes { commit {
            \(Self.deployments)
            statusCheckRollup { contexts(first: 100) {
            nodes {
              __typename
              ... on CheckRun {
                name status conclusion detailsUrl startedAt completedAt
                annotations(first: 10) { nodes { annotationLevel path message location { start { line } } } }
                checkSuite { workflowRun { workflow { name } } }
              }
              ... on StatusContext { context state targetUrl description }
            }
          } } } } }
        } }
      }
      """
    let response = try await request(query: query, variables: ["id": pr.id])
    guard let node = (response["data"] as? [String: Any])?["node"] as? [String: Any] else {
      throw ProcessFailure.failed("GitHub could not find this pull request.")
    }
    return try Self.decodeDetails(node)
  }

  static func decodeDetails(_ node: [String: Any], now: Date = Date()) throws -> PullRequestDetails
  {
    guard let id = node["id"] as? String else {
      throw ProcessFailure.failed("GitHub returned an incomplete pull request.")
    }
    func nodes(_ value: Any?) -> [[String: Any]] {
      (value as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
    }
    func login(_ value: Any?) -> String? { (value as? [String: Any])?["login"] as? String }
    let files = nodes(node["files"]).compactMap { file -> PullRequestDetails.FileChange? in
      guard let path = file["path"] as? String else { return nil }
      return .init(
        path: path, additions: file["additions"] as? Int ?? 0,
        deletions: file["deletions"] as? Int ?? 0)
    }
    let requested = nodes(node["reviewRequests"]).compactMap { request -> String? in
      let reviewer = request["requestedReviewer"] as? [String: Any]
      return (reviewer?["login"] ?? reviewer?["name"]) as? String
    }
    let reviews = nodes(node["latestReviews"]).compactMap { review -> PullRequestDetails.Review? in
      guard let author = login(review["author"]), let state = review["state"] as? String else {
        return nil
      }
      return .init(
        author: author, state: state,
        submittedAt: (review["submittedAt"] as? String).flatMap(Dates.parse))
    }
    let commentsConnection = node["comments"] as? [String: Any]
    let comments = nodes(commentsConnection).compactMap { comment -> PullRequestDetails.Comment? in
      guard let created = (comment["createdAt"] as? String).flatMap(Dates.parse) else { return nil }
      return .init(
        author: login(comment["author"]) ?? "ghost", body: comment["bodyText"] as? String ?? "",
        createdAt: created)
    }
    let commits = node["commits"] as? [String: Any]
    let commit = nodes(commits).last?["commit"] as? [String: Any]
    let contexts = ((commit?["statusCheckRollup"] as? [String: Any])?["contexts"])
    let checks = nodes(contexts).compactMap(Self.decodeCheck)
    return PullRequestDetails(
      id: id, body: node["body"] as? String ?? "", author: login(node["author"]),
      baseRefName: node["baseRefName"] as? String ?? "",
      headRefName: node["headRefName"] as? String ?? "",
      createdAt: (node["createdAt"] as? String).flatMap(Dates.parse),
      additions: node["additions"] as? Int ?? 0, deletions: node["deletions"] as? Int ?? 0,
      changedFiles: node["changedFiles"] as? Int ?? files.count, files: files,
      commitCount: commits?["totalCount"] as? Int ?? 0, requestedReviewers: requested,
      reviews: reviews, commentCount: commentsConnection?["totalCount"] as? Int ?? comments.count,
      comments: comments, checks: checks,
      previews: (commit?["deployments"] as? [String: Any]).map(previews) ?? [], fetchedAt: now)
  }

  static func decodeCheck(_ node: [String: Any]) -> Check? {
    func link(_ value: Any?) -> URL? {
      guard let text = value as? String, let url = URL(string: text), url.scheme == "https"
      else { return nil }
      return url
    }
    if node["__typename"] as? String == "StatusContext" {
      guard let context = node["context"] as? String else { return nil }
      return Check(
        name: context, outcome: Check.outcome(state: node["state"] as? String),
        url: link(node["targetUrl"]), summary: node["description"] as? String)
    }
    guard let name = node["name"] as? String else { return nil }
    let annotations = ((node["annotations"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? [])
      .map { annotation in
        (
          level: annotation["annotationLevel"] as? String ?? "",
          path: annotation["path"] as? String ?? "",
          line: ((annotation["location"] as? [String: Any])?["start"] as? [String: Any])?["line"]
            as? Int,
          message: annotation["message"] as? String ?? ""
        )
      }
    let workflow =
      (((node["checkSuite"] as? [String: Any])?["workflowRun"] as? [String: Any])?["workflow"]
      as? [String: Any])?["name"] as? String
    return Check(
      name: name, workflow: workflow,
      outcome: Check.outcome(
        status: node["status"] as? String, conclusion: node["conclusion"] as? String),
      startedAt: (node["startedAt"] as? String).flatMap(Dates.parse),
      completedAt: (node["completedAt"] as? String).flatMap(Dates.parse),
      url: link(node["detailsUrl"]), errors: Check.errors(annotations))
  }
}

public enum Dates {
  public static func parse(_ value: String) -> Date? {
    (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value))
      ?? (try? Date.ISO8601FormatStyle().parse(value))
  }
}
