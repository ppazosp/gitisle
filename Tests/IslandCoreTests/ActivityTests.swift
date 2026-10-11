import Foundation
import Testing

@testable import IslandCore

struct ActivityTests {
  private let now = Date(timeIntervalSince1970: 1_791_720_000)
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return calendar
  }

  private func pr(_ id: String, updated: TimeInterval = 0) -> PullRequest {
    PullRequest(
      id: id, number: 12, repository: "example/app", title: "A change",
      url: URL(string: "https://github.com/example/app/pull/12")!, headOID: "abc",
      updatedAt: now.addingTimeInterval(-updated), author: "person")
  }

  @Test func pullRequestsFallIntoGitHubStyleSections() {
    var draft = pr("draft")
    draft.isDraft = true
    draft.checks = "FAILURE"
    var queued = pr("queued")
    queued.queuePosition = 2
    var autoMerge = pr("auto")
    autoMerge.autoMerge = true
    autoMerge.checks = "PENDING"
    var review = pr("review")
    review.reviewRequested = true
    var waiting = pr("waiting")
    waiting.reviewDecision = "REVIEW_REQUIRED"
    var merged = pr("merged")
    merged.state = "MERGED"
    var closed = pr("closed")
    closed.state = "CLOSED"

    #expect(draft.group == .draft)
    #expect(queued.group == .merging)
    #expect(autoMerge.group == .merging)
    #expect(review.group == .needsYou)
    #expect(waiting.group == .open)
    #expect(merged.group == .merged)
    #expect(closed.group == nil)
  }

  @Test func failingAutoMergeNeedsAttentionInsteadOfLookingMerged() {
    var request = pr("auto")
    request.autoMerge = true
    request.checks = "FAILURE"
    #expect(!request.isMerging)
    #expect(request.group == .needsYou)
  }

  @Test func sectionsKeepGroupOrderAndQueueOrder() {
    var second = pr("second", updated: 10)
    second.queuePosition = 2
    var first = pr("first", updated: 20)
    first.queuePosition = 1
    var review = pr("review")
    review.reviewRequested = true
    let sections = PRGrouping.sections(
      [second, review, first], window: .all, now: now, calendar: calendar)
    #expect(sections.map(\.group) == [.needsYou, .merging])
    #expect(sections[1].pullRequests.map(\.id) == ["first", "second"])
  }

  @Test func activityWindowUsesLocalDaysAndMergeTime() {
    let startOfToday = calendar.startOfDay(for: now)
    var mergedToday = pr("merged", updated: 0)
    mergedToday.state = "MERGED"
    mergedToday.mergedAt = startOfToday.addingTimeInterval(60)
    var mergedLastWeek = mergedToday
    mergedLastWeek.id = "old"
    mergedLastWeek.mergedAt = startOfToday.addingTimeInterval(-3 * 86_400)
    let yesterday = pr("yesterday", updated: now.timeIntervalSince(startOfToday) + 60)
    let all = [mergedToday, mergedLastWeek, yesterday]

    let today = PRGrouping.sections(all, window: .today, now: now, calendar: calendar)
    #expect(today.flatMap(\.pullRequests).map(\.id) == ["merged"])
    let week = PRGrouping.sections(all, window: .week, now: now, calendar: calendar)
    #expect(week.flatMap(\.pullRequests).count == 3)
    #expect(
      ActivityWindow.week.includes(
        startOfToday.addingTimeInterval(-6 * 86_400), now: now, calendar: calendar))
    #expect(
      !ActivityWindow.week.includes(
        startOfToday.addingTimeInterval(-6 * 86_400 - 1), now: now, calendar: calendar))
  }

  @Test func checkCountsSeparatePassingFailingAndRunning() {
    let summary = CheckSummary(counts: [
      ("SUCCESS", 3), ("SKIPPED", 1), ("NEUTRAL", 1), ("FAILURE", 1), ("TIMED_OUT", 1),
      ("IN_PROGRESS", 2), ("QUEUED", 1), ("EXPECTED", 1), ("STALE", 4), ("PENDING", 0),
    ])
    #expect(summary.passed == 5)
    #expect(summary.failed == 2)
    #expect(summary.pending == 4)
    #expect(summary.total == 11)
  }

  @Test func ownPRStartingToMergeAnnouncesItOnceWithoutASystemNotification() {
    let open = pr("mine")
    var merging = open
    merging.queuePosition = 1
    let previous = GitHubSnapshot(login: "person", pullRequests: [open])
    let current = GitHubSnapshot(login: "person", pullRequests: [merging])
    let events = GitHubChanges.events(previous: previous, current: current)
    #expect(events.map(\.kind) == [.queued])
    #expect(events.first?.notifiesSystem == false)
    #expect(events.first?.title.hasSuffix("Merging") == true)
    #expect(GitHubChanges.events(previous: current, current: current).isEmpty)
  }

  @Test func watchedPRsFromOthersDoNotAnnounceMerging() {
    var open = pr("theirs")
    open.author = "someone-else"
    var merging = open
    merging.autoMerge = true
    let events = GitHubChanges.events(
      previous: GitHubSnapshot(login: "person", pullRequests: [open]),
      current: GitHubSnapshot(login: "person", pullRequests: [merging]))
    #expect(events.isEmpty)
  }

  @Test func cachedSnapshotsWithoutNewFieldsStillDecode() throws {
    let legacy = Data(
      """
      {"id":"PR1","number":1,"repository":"example/app","title":"Old","url":"https://github.com/example/app/pull/1",
       "state":"OPEN","isDraft":false,"reviewRequested":false,"mergeable":"UNKNOWN","mergeStateStatus":"UNKNOWN",
       "headOID":"abc","autoMerge":false,"updatedAt":0}
      """.utf8)
    let decoded = try JSONDecoder().decode(PullRequest.self, from: legacy)
    #expect(decoded.checkSummary == nil)
    #expect(decoded.author == nil)
  }

  @Test func claudeTitleChosenByPersonOutranksGeneratedNames() throws {
    let head = Data(
      """
      {"type":"user","sessionId":"session","cwd":"/projects/app","message":{"content":"private prompt"}}
      """.utf8)
    let tail = Data(
      """
      {"type":"agent-name","agentName":"Generated name"}
      {"type":"custom-title","customTitle":"  Chosen title  "}
      {"type":"agent-name","agentName":"Later generated name"}
      """.utf8)
    let session = try #require(
      AgentLogReader.parse(
        head: head, tail: tail, provider: .claude, fallbackID: "fallback", modified: now))
    #expect(session.title == "Chosen title")

    let untitled = try #require(
      AgentLogReader.parse(
        head: head, tail: Data(), provider: .claude, fallbackID: "fallback", modified: now))
    #expect(untitled.title == nil)
  }

  @Test func codexIndexKeepsTheLatestNonEmptyThreadName() {
    let index = Data(
      """
      {"id":"a","thread_name":"First name","updated_at":"2026-10-11T10:00:00Z"}
      {"id":"b","thread_name":"Other"}
      {"id":"a","thread_name":"Renamed"}
      {"id":"b","thread_name":"   "}
      not json
      """.utf8)
    #expect(AgentLogReader.parseCodexIndex(index) == ["a": "Renamed", "b": "Other"])
  }

  @Test func codexSessionsPickUpTitlesFromTheIndex() async throws {
    let home = FileManager.default.temporaryDirectory
      .appendingPathComponent("gitisle-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let sessions = home.appendingPathComponent("sessions/2026/10/11")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    try Data(
      """
      {"type":"session_meta","payload":{"id":"thread","cwd":"/projects/app","originator":"codex_cli"}}
      {"type":"event_msg","payload":{"type":"task_started"}}
      """.utf8
    ).write(to: sessions.appendingPathComponent("rollout-thread.jsonl"))
    try Data(#"{"id":"thread","thread_name":"Ship the island"}"#.utf8)
      .write(to: home.appendingPathComponent("session_index.jsonl"))
    let reader = AgentLogReader()
    let found = await reader.sessions(
      codexHome: home, claudeHome: home.appendingPathComponent("missing"))
    #expect(found.map(\.title) == ["Ship the island"])
  }
}
