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

  @Test func checkCountsAndAuthorDecodeFromTheRollup() throws {
    var node = row("checked")
    node["author"] = ["login": "person"]
    node["mergeQueueEntry"] = ["position": 2, "enqueuedAt": "2026-10-11T09:58:00Z"]
    node["commits"] = [
      "nodes": [
        [
          "commit": [
            "statusCheckRollup": [
              "state": "PENDING",
              "contexts": [
                "checkRunCountsByState": [
                  ["state": "SUCCESS", "count": 4], ["state": "IN_PROGRESS", "count": 1],
                ],
                "statusContextCountsByState": [["state": "FAILURE", "count": 1]],
              ],
            ]
          ]
        ]
      ]
    ]
    let pr = try GitHubService.decode(node)
    #expect(pr.author == "person")
    #expect(pr.queuePosition == 2)
    #expect(pr.mergingSince == Dates.parse("2026-10-11T09:58:00Z"))
    #expect(pr.checks == "PENDING")
    #expect(pr.checkSummary == CheckSummary(passed: 4, failed: 1, pending: 1))
    #expect(try GitHubService.decode(row("plain")).checkSummary == nil)
  }

  @Test func repositoryAvatarsOnlyComeFromGitHubsAvatarHost() {
    let github = "https://avatars.githubusercontent.com/u/1?v=4"
    #expect(
      GitHubService.avatar(["owner": ["avatarUrl": github]])?.absoluteString == github)
    #expect(GitHubService.avatar(["owner": ["avatarUrl": "https://example.com/a.png"]]) == nil)
    #expect(
      GitHubService.avatar(["owner": ["avatarUrl": "http://avatars.githubusercontent.com/u/1"]])
        == nil)
    #expect(GitHubService.avatar(nil) == nil)
  }

  @Test func statsReadEachWindowAndTheContributionCalendar() async throws {
    var data: [String: Any] = [
      "viewer": [
        "login": "person",
        "contributionsCollection": [
          "contributionCalendar": [
            "weeks": [
              [
                "contributionDays": [
                  ["date": "2026-10-10", "contributionCount": 2],
                  ["date": "2026-10-11", "contributionCount": 5],
                ]
              ]
            ]
          ]
        ],
      ]
    ]
    for days in [1, 7, 30] {
      data["opened\(days)"] = ["issueCount": days]
      data["merged\(days)"] = ["issueCount": days * 2]
      data["reviewed\(days)"] = ["issueCount": days * 3]
    }
    let fixture = try FixtureTransport([JSONSerialization.data(withJSONObject: ["data": data])])
    let service = GitHubService(transport: { try await fixture.send($0) })
    let stats = try await service.stats()
    #expect(stats.login == "person")
    #expect(stats.window(days: 7) == .init(days: 7, opened: 7, merged: 14, reviewed: 21))
    #expect(stats.daily.map(\.value) == [2, 5])
  }

  @Test func incompleteStatsAreRejected() async throws {
    let response = try JSONSerialization.data(withJSONObject: [
      "data": ["viewer": ["login": "person"], "opened1": ["issueCount": 1]]
    ])
    let fixture = FixtureTransport([response])
    let service = GitHubService(transport: { try await fixture.send($0) })
    await #expect(throws: ProcessFailure.self) { try await service.stats() }
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
