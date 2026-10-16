import Foundation
import Testing

@testable import IslandCore

private actor FixtureTransport {
  var responses: [Data]
  /// The request bodies sent, in order.
  var sent: [String] = []
  init(_ responses: [Data]) { self.responses = responses }
  func send(_ input: Data) throws -> Data {
    sent.append(String(decoding: input, as: UTF8.self))
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

  @Test func fullRefreshRecordsWhatTheOpenSearchesFound() async throws {
    let fixture = try FixtureTransport([
      page([row("mine")]), page([row("review"), row("mine")]), page([row("old", state: "MERGED")]),
    ])
    let service = GitHubService(transport: { try await fixture.send($0) })
    let result = try await service.fetch(selection: RepositorySelection(text: ""), previous: nil)
    let fingerprint = try #require(result.searchFingerprint)
    // Merged history isn't part of the one-point check.
    #expect(fingerprint.entries.keys.sorted() == ["mine", "review"])
    #expect(fingerprint.found("mine", by: "mine") && fingerprint.found("mine", by: "reviews"))
    // Pages of 50 cost GitHub one point; pages of 100 cost two.
    let sent = await fixture.sent
    #expect(sent.count == 3 && sent.allSatisfy { $0.contains("first: 50") })
  }

  @Test func aSearchTooBigForOneCheckLeavesNoFingerprint() async throws {
    let rows = (0...100).map { row("pr\($0)") }
    let fixture = try FixtureTransport([
      page(Array(rows[0..<50]), cursor: "a"), page(Array(rows[50..<100]), cursor: "b"),
      page(Array(rows[100...])), page([]), page([]),
    ])
    let service = GitHubService(transport: { try await fixture.send($0) })
    let result = try await service.fetch(selection: RepositorySelection(text: ""), previous: nil)
    #expect(result.pullRequests.count == 101)
    #expect(result.searchFingerprint == nil)
  }

  private func check(_ searches: [[String: Any]], login: String = "person") throws -> Data {
    var data: [String: Any] = ["viewer": ["login": login]]
    for (index, search) in searches.enumerated() { data["s\(index)"] = search }
    return try JSONSerialization.data(withJSONObject: ["data": data])
  }

  @Test func oneRequestChecksEveryOpenSearch() async throws {
    let fixture = try FixtureTransport([
      check([
        ["issueCount": 1, "nodes": [["id": "a", "updatedAt": "2026-10-13T10:00:00Z"]]],
        ["issueCount": 0, "nodes": []],
        ["issueCount": 1, "nodes": [["id": "b", "updatedAt": "2026-10-13T11:00:00Z"]]],
      ])
    ])
    let service = GitHubService(transport: { try await fixture.send($0) })
    let result = try #require(
      try await service.searchFingerprint(selection: RepositorySelection(text: "example/app")))
    #expect(result.login == "person")
    #expect(result.fingerprint.entries.keys.sorted() == ["a", "b"])
    #expect(result.fingerprint.found("a", by: "mine") && result.fingerprint.found("b", by: "repos"))
    let sent = await fixture.sent
    #expect(sent.count == 1)
    let body = try #require(
      try JSONSerialization.jsonObject(with: Data(sent[0].utf8)) as? [String: Any])
    let variables = try #require(body["variables"] as? [String: String])
    #expect(variables["q2"] == "is:pr is:open repo:example/app")
  }

  @Test func theCheckGivesWayWhenASearchFindsMoreThanItCanSee() async throws {
    let fixture = try FixtureTransport([
      check([["issueCount": 101, "nodes": []], ["issueCount": 0, "nodes": []]])
    ])
    let service = GitHubService(transport: { try await fixture.send($0) })
    #expect(try await service.searchFingerprint(selection: RepositorySelection(text: "")) == nil)
  }

  @Test func anIncompleteCheckIsRejected() async throws {
    let fixture = try FixtureTransport([check([["issueCount": 0, "nodes": []]])])
    let service = GitHubService(transport: { try await fixture.send($0) })
    await #expect(throws: ProcessFailure.self) {
      try await service.searchFingerprint(selection: RepositorySelection(text: ""))
    }
  }

  @Test func fullSearchesKeepPreviewsReadForTheSameCommit() async throws {
    let fixture = try FixtureTransport([page([row("same"), row("pushed")]), page([]), page([])])
    let service = GitHubService(transport: { try await fixture.send($0) })
    let preview = PreviewDeploy(
      name: "app", state: .ready, url: URL(string: "https://app.vercel.app"))
    var same = try GitHubService.decode(row("same"))
    same.previews = [preview]
    var pushed = try GitHubService.decode(row("pushed"))
    pushed.headOID = "older"
    pushed.previews = [preview]
    let result = try await service.fetch(
      selection: RepositorySelection(text: ""),
      previous: GitHubSnapshot(login: "person", pullRequests: [same, pushed]))
    #expect(result.pullRequests.first { $0.id == "same" }?.previews == [preview])
    // A new commit's previews haven't been read yet.
    #expect(result.pullRequests.first { $0.id == "pushed" }?.previews == nil)
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

  @Test func theListCarriesWhatAPRPageDrawsFirst() throws {
    var sized = row("sized")
    sized["additions"] = 120
    sized["deletions"] = 8
    sized["changedFiles"] = 3
    sized["author"] = [
      "login": "person", "avatarUrl": "https://avatars.githubusercontent.com/u/1?v=4",
    ]
    sized["commits"] = ["totalCount": 4, "nodes": []]
    let pr = try GitHubService.decode(sized)
    #expect(pr.additions == 120 && pr.deletions == 8 && pr.changedFiles == 3)
    #expect(pr.commitCount == 4 && pr.authorAvatar?.host() == "avatars.githubusercontent.com")
    #expect(try GitHubService.decode(row("legacy")).additions == nil)
  }

  @Test func searchesKeepTheQueueChecksThatOnlyActiveRefreshesRead() async throws {
    var queued = row("queued")
    queued["mergeQueueEntry"] = [
      "position": 1, "enqueuedAt": "2026-10-11T09:58:00Z", "state": "AWAITING_CHECKS",
    ]
    var prior = try GitHubService.decode(queued)
    prior.queueChecks = CheckSummary(passed: 2, failed: 0, pending: 1)
    var requeued = queued
    requeued["mergeQueueEntry"] = ["position": 1, "enqueuedAt": "2026-10-11T10:30:00Z"]
    let active = try JSONSerialization.data(withJSONObject: [
      "data": ["viewer": ["login": "person"], "nodes": [row("plain")]]
    ])
    let fixture = try FixtureTransport([
      page([queued]), page([]), page([]), page([requeued]), page([]), page([]), active,
    ])
    let service = GitHubService(transport: { try await fixture.send($0) })
    let previous = GitHubSnapshot(login: "person", pullRequests: [prior])
    let same = try await service.fetch(selection: RepositorySelection(text: ""), previous: previous)
    #expect(same.pullRequests.first?.queueChecks == prior.queueChecks)
    // Back in the queue later is a new entry, whose checks start over.
    let again = try await service.fetch(
      selection: RepositorySelection(text: ""), previous: previous)
    #expect(again.pullRequests.first?.queueChecks == nil)
    _ = try await service.pullRequests(ids: ["plain"], login: "person")
    let sent = await fixture.sent
    #expect(!sent[0].contains("headCommit") && sent[6].contains("headCommit"))
  }

  @Test func creationTimeDecodes() throws {
    var opened = row("opened")
    opened["createdAt"] = "2026-10-13T09:00:00Z"
    #expect(try GitHubService.decode(opened).createdAt == Dates.parse("2026-10-13T09:00:00Z"))
    #expect(try GitHubService.decode(row("legacy")).createdAt == nil)
  }

  @Test func checkCountsAndAuthorDecodeFromTheRollup() throws {
    var node = row("checked")
    node["author"] = ["login": "person"]
    node["autoMergeRequest"] = ["enabledAt": "2026-10-11T09:40:00Z"]
    node["mergeQueueEntry"] = [
      "position": 2, "enqueuedAt": "2026-10-11T09:58:00Z", "state": "AWAITING_CHECKS",
      "headCommit": [
        "statusCheckRollup": [
          "state": "PENDING",
          "contexts": [
            "checkRunCountsByState": [
              ["state": "SUCCESS", "count": 2], ["state": "QUEUED", "count": 3],
            ]
          ],
        ]
      ],
    ]
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
    // Merging starts when the PR entered the queue, not when auto-merge was turned on.
    #expect(pr.mergingSince == Dates.parse("2026-10-11T09:58:00Z"))
    #expect(pr.queueState == "AWAITING_CHECKS")
    #expect(pr.queueChecks == CheckSummary(passed: 2, failed: 0, pending: 3))
    #expect(pr.checks == "PENDING")
    #expect(pr.checkSummary == CheckSummary(passed: 4, failed: 1, pending: 1))
    #expect(try GitHubService.decode(row("plain")).checkSummary == nil)
    #expect(try GitHubService.decode(row("plain")).queueChecks == nil)
    var autoMerge = row("auto")
    autoMerge["autoMergeRequest"] = ["enabledAt": "2026-10-11T09:40:00Z"]
    #expect(try GitHubService.decode(autoMerge).mergingSince == nil)
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
