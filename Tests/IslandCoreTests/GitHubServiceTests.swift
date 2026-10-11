import Foundation
import Testing

@testable import IslandCore

private actor FixtureTransport {
  var responses: [Data]
  init(_ responses: [Data]) { self.responses = responses }
  func send(_ input: Data) throws -> Data {
    guard !responses.isEmpty else { throw Failure.exhausted }
    return responses.removeFirst()
  }
  enum Failure: Error { case exhausted }
}

struct GitHubServiceTests {
  private func row(_ id: String, state: String = "OPEN") -> [String: Any] {
    [
      "id": id, "number": 12, "title": "Example", "url": "https://github.com/example/app/pull/12",
      "state": state, "updatedAt": "2026-10-11T10:00:00Z",
      "repository": ["nameWithOwner": "example/app"],
      "headRefOid": "abc", "mergeable": "MERGEABLE", "mergeStateStatus": "CLEAN",
    ]
  }
  private func page(_ rows: [[String: Any]], login: String = "person", cursor: String? = nil) throws
    -> Data
  {
    try JSONSerialization.data(withJSONObject: [
      "data": [
        "viewer": ["login": login],
        "search": [
          "nodes": rows,
          "pageInfo": ["hasNextPage": cursor != nil, "endCursor": cursor as Any? ?? NSNull()],
        ],
      ]
    ])
  }

  @Test func paginatedGroupsDeduplicateAndKeepReviewRequests() async throws {
    let fixture = try FixtureTransport([
      page([row("first")], cursor: "next"), page([row("second")]),
      page([row("first")]), page([]),
    ])
    let service = GitHubService(transport: { try await fixture.send($0) })
    let result = try await service.fetch(selection: RepositorySelection(text: ""), previous: nil)
    #expect(result.pullRequests.count == 2)
    #expect(result.pullRequests.first { $0.id == "first" }?.reviewRequested == true)
    #expect(!result.isLimited)
  }

  @Test func accountSwitchDuringPaginationRejectsTheSnapshot() async throws {
    let fixture = try FixtureTransport([page([]), page([], login: "another-person")])
    let service = GitHubService(transport: { try await fixture.send($0) })
    await #expect(throws: ProcessFailure.self) {
      try await service.fetch(selection: RepositorySelection(text: ""), previous: nil)
    }
  }

  @Test func missingOpenPRIsReadBeforeItBecomesMerged() async throws {
    let closed = try JSONSerialization.data(withJSONObject: [
      "data": ["viewer": ["login": "person"], "nodes": [row("known", state: "MERGED")]]
    ])
    let fixture = try FixtureTransport([page([]), page([]), page([]), closed])
    let service = GitHubService(transport: { try await fixture.send($0) })
    let prior = try GitHubService.decode(row("known"))
    let result = try await service.fetch(
      selection: RepositorySelection(text: ""),
      previous: GitHubSnapshot(login: "person", pullRequests: [prior]))
    #expect(result.pullRequests.first?.state == "MERGED")
  }

  @Test func graphqlErrorsRejectPartialData() async throws {
    let response = try JSONSerialization.data(withJSONObject: [
      "data": ["viewer": ["login": "person"]], "errors": [["message": "Unavailable"]],
    ])
    let fixture = FixtureTransport([response])
    let service = GitHubService(transport: { try await fixture.send($0) })
    await #expect(throws: ProcessFailure.self) {
      try await service.fetch(selection: RepositorySelection(text: ""), previous: nil)
    }
  }
}
