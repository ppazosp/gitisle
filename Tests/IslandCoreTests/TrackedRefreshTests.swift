import Foundation
import Testing

@testable import IslandCore

/// Answers requests in order and keeps them, so tests can read what was asked.
private actor RecordingTransport {
  private var responses: [Data]
  private var requests: [Data] = []
  init(_ responses: [Data]) { self.responses = responses }
  func send(_ input: Data) throws -> Data {
    requests.append(input)
    guard !responses.isEmpty else { throw Failure.exhausted }
    return responses.removeFirst()
  }
  private func variables() -> [[String: Any]] {
    requests.compactMap {
      (try? JSONSerialization.jsonObject(with: $0) as? [String: Any])?["variables"]
        as? [String: Any]
    }
  }
  /// The search strings sent, in order.
  func searches() -> [String] { variables().compactMap { $0["search"] as? String } }
  func cursors() -> [String] { variables().compactMap { $0["after"] as? String } }
  func queries() -> [String] {
    requests.compactMap {
      (try? JSONSerialization.jsonObject(with: $0) as? [String: Any])?["query"] as? String
    }
  }
  /// The PR IDs sent with the first request.
  func ids() -> [String]? { variables().first?["ids"] as? [String] }
  enum Failure: Error { case exhausted }
}

struct TrackedRefreshTests {
  private let now = Date()

  private func row(_ id: String, state: String = "OPEN") -> [String: Any] {
    [
      "id": id, "number": 7, "title": "Example", "url": "https://github.com/example/app/pull/7",
      "state": state, "updatedAt": "2026-10-11T10:00:00Z",
      "repository": ["nameWithOwner": "example/app"],
      "headRefOid": "abc", "mergeable": "MERGEABLE", "mergeStateStatus": "CLEAN",
    ]
  }

  private func page(_ rows: [[String: Any]], remaining: Int = 4_900, cursor: String? = nil)
    throws -> Data
  {
    let pageInfo: [String: Any] = [
      "hasNextPage": cursor != nil, "endCursor": cursor as Any? ?? NSNull(),
    ]
    return try JSONSerialization.data(withJSONObject: [
      "data": [
        "viewer": ["login": "person"],
        "rateLimit": ["remaining": remaining, "resetAt": "2026-10-12T20:00:00Z"],
        "search": ["nodes": rows, "pageInfo": pageInfo],
      ]
    ])
  }

  private func pr(updatedAgo: TimeInterval, _ change: (inout PullRequest) -> Void = { _ in })
    throws -> PullRequest
  {
    var value = try GitHubService.decode(row("pr"))
    value.updatedAt = now.addingTimeInterval(-updatedAgo)
    change(&value)
    return value
  }

  @Test func activeMeansOpenAndMoving() throws {
    #expect(try pr(updatedAgo: 60).isActive(at: now))
    #expect(try !pr(updatedAgo: 3_600).isActive(at: now))
    #expect(try pr(updatedAgo: 3_600) { $0.checks = "PENDING" }.isActive(at: now))
    #expect(
      try pr(updatedAgo: 3_600) { $0.checkSummary = CheckSummary(passed: 2, failed: 0, pending: 1) }
        .isActive(at: now))
    #expect(try pr(updatedAgo: 3_600) { $0.autoMerge = true }.isActive(at: now))
    #expect(try pr(updatedAgo: 3_600) { $0.queuePosition = 1 }.isActive(at: now))
    #expect(try !pr(updatedAgo: 60) { $0.state = "MERGED" }.isActive(at: now))
  }

  @Test func knownPRsRefreshByIDAndSkipMissingOnes() async throws {
    let answer = try JSONSerialization.data(withJSONObject: [
      "data": [
        "viewer": ["login": "person"],
        "rateLimit": ["remaining": 4_321, "resetAt": "2026-10-12T20:00:00Z"],
        "nodes": [row("a", state: "MERGED"), NSNull()],
      ],
      "errors": [["type": "NOT_FOUND", "message": "Could not resolve to a node"]],
    ])
    let transport = RecordingTransport([answer])
    let service = GitHubService(transport: { try await transport.send($0) })
    let result = try await service.pullRequests(ids: ["a", "gone"], login: "person")
    #expect(result.map(\.id) == ["a"])
    #expect(result.first?.state == "MERGED")
    #expect(await service.budget?.remaining == 4_321)
    #expect(await transport.ids() == ["a", "gone"])
  }

  @Test func refreshByIDRejectsADifferentAccount() async throws {
    let answer = try JSONSerialization.data(withJSONObject: [
      "data": ["viewer": ["login": "someone-else"], "nodes": [row("a")]]
    ])
    let transport = RecordingTransport([answer])
    let service = GitHubService(transport: { try await transport.send($0) })
    await #expect(throws: ProcessFailure.self) {
      try await service.pullRequests(ids: ["a"], login: "person")
    }
  }

  @Test func recentSweepReadsOnlyRecentMergesAndKeepsHistory() async throws {
    let transport = RecordingTransport([try page([]), try page([]), try page([])])
    let service = GitHubService(transport: { try await transport.send($0) })
    var old = try GitHubService.decode(row("old", state: "MERGED"))
    old.updatedAt = now.addingTimeInterval(-5 * 86_400)
    let swept = now.addingTimeInterval(-3_600)
    let previous = GitHubSnapshot(
      login: "person", pullRequests: [old], fetchedAt: now.addingTimeInterval(-60),
      selection: try RepositorySelection(text: "").fingerprint, mergedSweptAt: swept,
      mergedHistory: MergedHistory(nextCursor: "cached-older"))
    let result = try await service.fetch(
      selection: RepositorySelection(text: ""), previous: previous)
    let searches = await transport.searches()
    let yesterday = now.addingTimeInterval(-86_400 - 60).formatted(
      .iso8601.year().month().day().dateSeparator(.dash))
    #expect(searches.contains { $0.contains("is:merged") && $0.contains("merged:>=\(yesterday)") })
    #expect(result.pullRequests.contains { $0.id == "old" })
    #expect(result.mergedHistory?.nextCursor == "cached-older")
  }

  @Test func firstHistoryPageUses74AndOlderPageAdvancesTheCursor() async throws {
    let transport = RecordingTransport([
      try page([]), try page([]),
      try page([row("recent", state: "MERGED")], cursor: "history-2"),
      try page([row("older", state: "MERGED")], cursor: "history-3"),
    ])
    let service = GitHubService(transport: { try await transport.send($0) })
    let snapshot = try await service.fetch(selection: RepositorySelection(text: ""), previous: nil)
    let searches = await transport.searches()
    #expect(searches.count == 3)
    #expect(searches.last == "is:pr is:merged author:@me sort:updated-desc")
    #expect(snapshot.pullRequests.map(\.id) == ["recent"])
    let cursor = try #require(snapshot.mergedHistory?.nextCursor)
    #expect(cursor == "history-2")
    let older = try await service.morePullRequests(
      after: cursor, login: "person", selection: RepositorySelection(text: ""))
    #expect(older.pullRequests.map(\.id) == ["older"])
    #expect(older.nextCursor == "history-3")
    #expect(await transport.cursors() == ["history-2"])
    let queries = await transport.queries()
    #expect(queries.count == 4)
    #expect(queries.prefix(2).allSatisfy { $0.contains("first: 50") })
    #expect(queries.suffix(2).allSatisfy { $0.contains("first: 74") })
  }

  @Test func cappedReviewSearchCanFetchAnotherPage() async throws {
    let selection = try RepositorySelection(text: "")
    let reviewPages = try (1...GitHubService.searchPages).map { index in
      try page([row("review-\(index)")], cursor: "page-\(index + 1)")
    }
    let transport = RecordingTransport(
      [try page([])] + reviewPages + [try page([]), try page([row("more-review")])])
    let service = GitHubService(transport: { try await transport.send($0) })
    let snapshot = try await service.fetch(selection: selection, previous: nil)
    let progress = try #require(snapshot.openSearchProgress?["reviews"])
    let cursor = try #require(progress.nextCursor)
    #expect(progress.pages == GitHubService.searchPages)
    #expect(cursor == "page-9")
    let next = try await service.morePullRequests(
      after: cursor, login: "person", selection: selection, openSearch: "reviews")
    #expect(next.pullRequests.map(\.id) == ["more-review"])
    #expect(next.pullRequests.first?.reviewRequested == true)
    #expect(next.nextCursor == nil)
    #expect(await transport.searches().last == "is:pr is:open review-requested:@me")
    #expect(await transport.cursors().last == "page-9")
    #expect(await transport.queries().last?.contains("first: 74") == true)
  }
}
