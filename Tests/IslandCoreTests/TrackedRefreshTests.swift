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

  private func page(_ rows: [[String: Any]], remaining: Int = 4_900) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "data": [
        "viewer": ["login": "person"],
        "rateLimit": ["remaining": remaining, "resetAt": "2026-10-12T20:00:00Z"],
        "search": ["nodes": rows, "pageInfo": ["hasNextPage": false, "endCursor": NSNull()]],
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
      selection: try RepositorySelection(text: "").fingerprint, mergedSweptAt: swept)
    let result = try await service.fetch(
      selection: RepositorySelection(text: ""), previous: previous)
    let searches = await transport.searches()
    let yesterday = now.addingTimeInterval(-86_400 - 60).formatted(
      .iso8601.year().month().day().dateSeparator(.dash))
    #expect(searches.contains { $0.contains("is:merged") && $0.contains("merged:>=\(yesterday)") })
    #expect(result.pullRequests.contains { $0.id == "old" })
    #expect(result.mergedSweptAt == swept)
  }

  @Test func staleSweepReadsTheFullMonth() async throws {
    let transport = RecordingTransport([try page([]), try page([]), try page([])])
    let service = GitHubService(transport: { try await transport.send($0) })
    let previous = GitHubSnapshot(
      login: "person", pullRequests: [], selection: try RepositorySelection(text: "").fingerprint,
      mergedSweptAt: now.addingTimeInterval(-2 * 86_400))
    let result = try await service.fetch(
      selection: RepositorySelection(text: ""), previous: previous)
    let searches = await transport.searches()
    let month = now.addingTimeInterval(-30 * 86_400).formatted(
      .iso8601.year().month().day().dateSeparator(.dash))
    #expect(searches.contains { $0.contains("merged:>=\(month)") })
    #expect(result.mergedSweptAt.map { abs($0.timeIntervalSince(now)) < 60 } == true)
  }
}
