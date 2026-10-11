import Foundation
import Testing

@testable import IslandCore

struct IslandCoreTests {
  private func pr(_ id: String = "PR1") -> PullRequest {
    PullRequest(
      id: id, number: 12, repository: "example/app", title: "A change",
      url: URL(string: "https://github.com/example/app/pull/12")!, headOID: "abc")
  }

  @Test func draftWithGreenChecksIsNotReady() {
    var request = pr()
    request.isDraft = true
    request.checks = "SUCCESS"
    request.mergeStateStatus = "CLEAN"
    #expect(request.status == .draft)
    #expect(!request.status.needsAttention)
  }

  @Test func successfulChecksAloneDoNotProveMergeReadiness() {
    var request = pr()
    request.checks = "SUCCESS"
    #expect(request.status == .unknown)
  }

  @Test func queuedPRKeepsItsQueueStateWhileChecksRun() {
    var request = pr()
    request.queuePosition = 3
    request.checks = "PENDING"
    #expect(request.status == .queued)
  }

  @Test func blockedAndBehindBranchesDoNotInventAReviewRequirement() {
    var request = pr()
    request.mergeStateStatus = "BLOCKED"
    #expect(request.status == .blocked)
    request.mergeStateStatus = "BEHIND"
    #expect(request.status == .behind)
    request.reviewDecision = "REVIEW_REQUIRED"
    #expect(request.status == .waiting)
  }

  @Test func disappearanceDoesNotBecomeAMergeNotification() {
    let previous = GitHubSnapshot(login: "person", pullRequests: [pr()])
    let current = GitHubSnapshot(login: "person", pullRequests: [])
    #expect(GitHubChanges.events(previous: previous, current: current).isEmpty)
  }

  @Test func observedMergeProducesOneStableEvent() {
    let previous = GitHubSnapshot(login: "person", pullRequests: [pr()])
    var merged = pr()
    merged.state = "MERGED"
    merged.mergedAt = Date(timeIntervalSince1970: 123)
    let current = GitHubSnapshot(login: "person", pullRequests: [merged])
    let events = GitHubChanges.events(previous: previous, current: current)
    #expect(events.count == 1)
    #expect(events.first?.kind == .merged)
    #expect(GitHubChanges.events(previous: current, current: current).isEmpty)
  }

  @Test func newCommitCanNotifyEvenWhenPreviousCommitFailed() {
    var prior = pr()
    prior.checks = "FAILURE"
    var changed = prior
    changed.headOID = "def"
    let events = GitHubChanges.events(
      previous: GitHubSnapshot(login: "person", pullRequests: [prior]),
      current: GitHubSnapshot(login: "person", pullRequests: [changed]))
    #expect(events.count == 1)
    #expect(events.first?.kind == .failed)
  }

  @Test func switchingAccountsOrRepositorySelectionDoesNotReplayEvents() {
    var failed = pr()
    failed.checks = "FAILURE"
    let previous = GitHubSnapshot(login: "first", pullRequests: [pr()])
    #expect(
      GitHubChanges.events(
        previous: previous, current: GitHubSnapshot(login: "second", pullRequests: [failed])
      ).isEmpty)
    #expect(
      GitHubChanges.events(
        previous: previous,
        current: GitHubSnapshot(login: "first", pullRequests: [failed], selection: "other/repo")
      ).isEmpty)
    #expect(GitHubChanges.events(previous: nil, current: previous).isEmpty)
  }

  @Test func repositoryNamesCannotInjectSearchOrShellSyntax() throws {
    #expect(throws: RepositorySelection.SelectionError.self) {
      try RepositorySelection(text: "owner/repo state:closed")
    }
    #expect(throws: RepositorySelection.SelectionError.self) {
      try RepositorySelection(text: "owner/repo;id")
    }
    #expect(throws: RepositorySelection.SelectionError.self) {
      try RepositorySelection(text: "owner/")
    }
    let selection = try RepositorySelection(text: "owner/app, owner/tools\nowner/app")
    #expect(selection.repositories == ["owner/app", "owner/tools"])
  }

  @Test func desktopSessionIsIdentifiedFromOriginatorAndHandlesInterruptedTurns() throws {
    let head = Data(
      """
      {"type":"session_meta","payload":{"id":"thread","cwd":"/projects/app","originator":"Codex Desktop","source":"vscode"}}
      """.utf8)
    let tail = Data(
      """
      {"type":"turn_context","payload":{"model":"example-model"}}
      {"type":"event_msg","payload":{"type":"task_started"}}
      {"type":"event_msg","payload":{"type":"turn_aborted"}}
      {"unfinished":
      """.utf8)
    let session = try #require(
      AgentLogReader.parse(
        head: head, tail: tail, provider: .codex, fallbackID: "fallback", modified: Date()))
    #expect(session.source == "Codex desktop")
    #expect(session.model == "example-model")
    #expect(session.phase == .interrupted)
  }

  @Test func claudeFinishedTurnRemainsFinishedAfterMetadataRows() throws {
    let head = Data(
      """
      {"type":"user","sessionId":"session","cwd":"/projects/app","gitBranch":"feature","message":{"content":"private prompt"}}
      """.utf8)
    let tail = Data(
      """
      {"type":"assistant","sessionId":"session","message":{"model":"example-model","stop_reason":"tool_use","content":[{"type":"tool_use","name":"Bash","input":{"command":"private command"}}]}}
      {"type":"assistant","message":{"model":"example-model","stop_reason":"end_turn","content":[]}}
      {"type":"custom-title","customTitle":"private title"}
      """.utf8)
    let session = try #require(
      AgentLogReader.parse(
        head: head, tail: tail, provider: .claude, fallbackID: "fallback", modified: Date()))
    #expect(session.phase == .finished)
    #expect(session.activity == "Turn completed")
    #expect(session.branch == "feature")
  }

  @Test func invalidGithubRowsDoNotProduceInventedPRs() {
    #expect(throws: ProcessFailure.self) { try GitHubService.decode(["id": "missing-fields"]) }
  }

  @Test func newlyRequestedReviewProducesAnEventAfterInitialConnection() {
    let previous = GitHubSnapshot(login: "person", pullRequests: [])
    var requested = pr()
    requested.reviewRequested = true
    #expect(
      GitHubChanges.events(
        previous: previous, current: GitHubSnapshot(login: "person", pullRequests: [requested])
      ).count == 1)
  }

  @Test func missingOrOverflowingUsageRemainsUnavailable() {
    #expect(UsageMath.tokens([Int.max, 1]) == nil)
    #expect(UsageMath.tokens([10, nil]) == nil)
    #expect(UsageMath.tokens([0, 0]) == 0)
    #expect(UsageMath.costs([1, Double.infinity]) == nil)
    #expect(UsageMath.costs([1, nil]) == nil)
  }

  @Test func subprocessDrainsOutputAndEnforcesDeadline() async throws {
    let output = try await ProcessRunner.run(
      URL(fileURLWithPath: "/bin/echo"), arguments: ["hello"])
    #expect(String(decoding: output, as: UTF8.self) == "hello\n")
    await #expect(throws: ProcessFailure.self) {
      try await ProcessRunner.run(
        URL(fileURLWithPath: "/bin/sleep"), arguments: ["2"], deadline: 0.05)
    }
  }

  @Test func continuousOutputCannotPreventTheResponseLimit() async {
    await #expect(throws: ProcessFailure.self) {
      try await ProcessRunner.run(
        URL(fileURLWithPath: "/usr/bin/yes"), arguments: [], limit: 32_768)
    }
  }

  @Test func cancellationStopsAnOwnedChildProcess() async throws {
    let task = Task {
      try await ProcessRunner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"])
    }
    try await Task.sleep(for: .milliseconds(50))
    task.cancel()
    await #expect(throws: ProcessFailure.self) { try await task.value }
  }

  @Test func repeatedAsyncCommandsReturnAfterTheirChildExits() async throws {
    for _ in 0..<8 {
      let result = try await ProcessRunner.run(
        URL(fileURLWithPath: "/bin/sleep"), arguments: ["0.03"])
      #expect(result.isEmpty)
      await Task.yield()
    }
  }
}
