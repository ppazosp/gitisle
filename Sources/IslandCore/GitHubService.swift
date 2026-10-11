import Foundation

public actor GitHubService {
  private static let fields = """
    fragment PRFields on PullRequest {
      id number title url state isDraft updatedAt mergedAt mergeable mergeStateStatus reviewDecision
      headRefOid autoMergeRequest { enabledAt } mergeQueueEntry { position }
      repository { nameWithOwner }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
    }
    """

  private let transport: (@Sendable (Data) async throws -> Data)?

  public init(transport: (@Sendable (Data) async throws -> Data)? = nil) {
    self.transport = transport
  }

  public func fetch(selection: RepositorySelection, previous: GitHubSnapshot?) async throws
    -> GitHubSnapshot
  {
    let query = """
      query($search: String!, $after: String) {
        viewer { login }
        search(query: $search, type: ISSUE, first: 25, after: $after) {
          nodes { ...PRFields }
          pageInfo { hasNextPage endCursor }
        }
      }
      \(Self.fields)
      """
    let since = Date().addingTimeInterval(-7 * 86_400).formatted(
      .iso8601.year().month().day().dateSeparator(.dash))
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
          limited = true
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
      for pr in previous.pullRequests where pr.state != "OPEN" && prs[pr.id] == nil {
        if Date().timeIntervalSince(pr.updatedAt) < 7 * 86_400 { prs[pr.id] = pr }
      }
    }
    return GitHubSnapshot(
      login: login, pullRequests: prs.values.sorted { $0.updatedAt > $1.updatedAt },
      selection: selection.fingerprint, isLimited: limited)
  }

  private func request(query: String, variables: [String: Any]) async throws -> [String:
    Any]
  {
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
    if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
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
    let queue = row["mergeQueueEntry"] as? [String: Any]
    return PullRequest(
      id: id, number: number, repository: repo, title: title, url: url, state: state,
      isDraft: row["isDraft"] as? Bool ?? false, reviewDecision: row["reviewDecision"] as? String,
      mergeable: row["mergeable"] as? String ?? "UNKNOWN",
      mergeStateStatus: row["mergeStateStatus"] as? String ?? "UNKNOWN",
      checks: rollup?["state"] as? String, headOID: row["headRefOid"] as? String ?? "",
      autoMerge: row["autoMergeRequest"] is [String: Any],
      queuePosition: queue?["position"] as? Int,
      updatedAt: updatedAt, mergedAt: (row["mergedAt"] as? String).flatMap(Dates.parse))
  }
}

public enum Dates {
  public static func parse(_ value: String) -> Date? {
    (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value))
      ?? (try? Date.ISO8601FormatStyle().parse(value))
  }
}
