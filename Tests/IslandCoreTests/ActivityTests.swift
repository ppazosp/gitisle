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

  @Test func repositoriesThatNeedYouComeFirstWithPRsInStateOrder() {
    func make(_ id: String, _ repository: String, updated: TimeInterval) -> PullRequest {
      var request = pr(id, updated: updated)
      request.repository = repository
      return request
    }
    var draft = make("draft", "a/recent", updated: 0)
    draft.isDraft = true
    let open = make("open", "a/recent", updated: 5)
    var review = make("review", "b/needs-you", updated: 500)
    review.reviewRequested = true
    var merged = make("merged", "b/needs-you", updated: 1)
    merged.state = "MERGED"
    let older = make("older", "c/older", updated: 900)

    let sections = PRGrouping.repositories(
      [draft, open, review, merged, older], window: .all, now: now, calendar: calendar)
    #expect(sections.map(\.repository) == ["b/needs-you", "a/recent", "c/older"])
    #expect(sections[0].pullRequests.map(\.id) == ["review", "merged"])
    #expect(sections[1].pullRequests.map(\.id) == ["open", "draft"])
    #expect(sections[0].counts.map(\.group) == [.needsYou, .merged])
    #expect(sections[0].owner == "b" && sections[0].name == "needs-you")
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
}
