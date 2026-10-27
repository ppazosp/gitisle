import Foundation
import Testing

@testable import IslandCore

struct PullRequestTrendsTests {
  /// Sunday 11 October 2026, 14:00 in Madrid.
  private let now = Date(timeIntervalSince1970: 1_791_720_000)
  private let hour = 3600.0
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return calendar
  }

  /// A PR merged `mergedAgo` seconds ago, opened `took` seconds before that.
  private func merged(
    _ id: String, repository: String = "a/web", mergedAgo: TimeInterval, took: TimeInterval,
    lines: (Int, Int) = (10, 5), author: String = "me"
  ) -> PullRequest {
    let mergedAt = now.addingTimeInterval(-mergedAgo)
    return PullRequest(
      id: id, number: 1, repository: repository, title: id,
      url: URL(string: "https://github.com/a/web/pull/1")!, state: "MERGED", updatedAt: mergedAt,
      mergedAt: mergedAt, author: author, createdAt: mergedAt.addingTimeInterval(-took),
      additions: lines.0, deletions: lines.1)
  }

  private var pullRequests: [PullRequest] {
    [
      // Merged at 13:00, 12:00 and 11:00 today; opened at 12:30, yesterday 06:00, and 09:00.
      merged("fast", mergedAgo: 1 * hour, took: 0.5 * hour, lines: (40, 10)),
      merged("slow", repository: "a/api", mergedAgo: 2 * hour, took: 30 * hour, lines: (300, 100)),
      merged("middle", mergedAgo: 3 * hour, took: 2 * hour, lines: (100, 20)),
      // Ten days ago: in 30 days, not in 7.
      merged("old", repository: "b/docs", mergedAgo: 240 * hour, took: 4 * hour),
      // Someone else's merge counts nowhere.
      merged("theirs", mergedAgo: 1 * hour, took: 1 * hour, author: "them"),
      // Still open, opened at 09:00: it counts as opened.
      PullRequest(
        id: "open", number: 2, repository: "a/web", title: "open",
        url: URL(string: "https://github.com/a/web/pull/2")!, author: "me",
        createdAt: now.addingTimeInterval(-5 * hour)),
    ]
  }

  @Test func todayIsHourByHour() {
    let today = PullRequestTrends(
      pullRequests: pullRequests, login: "me", days: 1, now: now, calendar: calendar)
    #expect(today.lines.count == 24)
    #expect(today.added == 440 && today.removed == 130)
    #expect(today.lines[13].added == 40 && today.lines[12].added == 300)
    #expect(today.lines[11].removed == 20)
    #expect(today.mergedByHour[11] == 1 && today.mergedByHour[12] == 1)
    #expect(today.mergedByHour[13] == 1 && today.mergedByHour.reduce(0, +) == 3)
    // The PR opened yesterday merged today, so today only has three openings.
    #expect(today.openedByHour[9] == 2 && today.openedByHour[12] == 1)
    #expect(today.openedByHour.reduce(0, +) == 3)
  }

  @Test func longerPeriodsAreDayByDayAndTheChartAlwaysCovers30Days() {
    let month = PullRequestTrends(
      pullRequests: pullRequests, login: "me", days: 30, now: now, calendar: calendar)
    #expect(month.lines.count == 30)
    #expect(month.added == 450 && month.removed == 135)
    #expect(month.opened.count == 30 && month.merged.count == 30)
    #expect(month.merged.last?.value == 3)
    #expect(month.merged.reduce(0) { $0 + $1.value } == 4)
    #expect(month.opened.reduce(0) { $0 + $1.value } == 5)

    let week = PullRequestTrends(
      pullRequests: pullRequests, login: "me", days: 7, now: now, calendar: calendar)
    #expect(week.lines.count == 7 && week.added == 440)
    // The daily chart doesn't depend on the period.
    #expect(week.merged == month.merged)
  }

  @Test func theRepositoryFilterAppliesToEverything() {
    let api = PullRequestTrends(
      pullRequests: pullRequests, login: "me", repositories: ["a/api"], days: 30, now: now,
      calendar: calendar)
    #expect(api.added == 300 && api.removed == 100)
    #expect(api.merged.reduce(0) { $0 + $1.value } == 1)
    #expect(api.opened.reduce(0) { $0 + $1.value } == 1)
    #expect(api.mergedByHour.reduce(0, +) == 1 && api.mergedByHour[12] == 1)
  }

  @Test func nothingYetIsAllZeros() {
    let empty = PullRequestTrends(
      pullRequests: [], login: "me", days: 7, now: now, calendar: calendar)
    #expect(empty.lines.count == 7 && empty.added == 0 && empty.removed == 0)
    #expect(empty.openedByHour == Array(repeating: 0, count: 24))
    #expect(empty.merged.allSatisfy { $0.value == 0 })
  }
}
